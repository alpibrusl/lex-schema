# lex-schema — first-class JSON ADT + parser
#
# A hand-rolled JSON parser that produces a structurally-tagged
# `Json` ADT — closing the runtime-safety gap that polymorphic
# `json.parse` leaves open (lex-lang#322). Once the input has been
# turned into a `Json` value, every downstream extractor is total:
# `j_str` on a `JBool` is a typed error, not a VM panic.
#
# This module is the foundation of the "safe mode" path. Use it
# when you can't fully trust the input (HTTP bodies from untrusted
# clients, files copied across systems, etc.). For inputs you do
# trust (in-process serialization, well-typed producers) the
# regular `from_json` + `check_xxx` pipeline is cheaper.
#
# Effects: none. The parser is a pure fold over the input string.
#
# Performance: O(n) on the input length. String runs are extracted
# in a single `str.slice` per escape-free chunk; array and object
# accumulators use `list.cons` + `list.reverse` to avoid the O(n²)
# `list.concat`-per-element shape.

import "std.str" as str

import "std.int" as int

import "std.float" as float

import "std.list" as list

import "./error" as e

import "./constraints" as c

import "./field" as f

# ---- Json ADT -----------------------------------------------------
type Json = JNull | JBool(Bool) | JInt(Int) | JFloat(Float) | JStr(Str) | JList(List[Json]) | JObj(List[(Str, Json)])

type ParseErr = { pos :: Int, message :: Str }

# A parse step returns the new cursor + value, or a ParseErr.
# Encoded as Result so it threads cleanly through `match`.
type ParseStep = { pos :: Int, value :: Json }

# ---- Public entry point -------------------------------------------
# Parse a complete JSON document. Trailing whitespace is allowed
# but trailing non-whitespace garbage is a parse error.
# Replace any literal multi-byte (non-ASCII) character with "?" before
# parsing. The scanner advances byte-by-byte while `str.len`/`str.slice`
# disagree on char vs byte boundaries for multi-byte UTF-8, which made
# `parse` fail on literal `—`, `→`, etc. inside strings. This mirrors the
# existing `parse_into_errors` convention (non-ASCII BMP -> "?").
fn sanitise_multibyte(src :: Str) -> Str {
  str.join(list.map(str.split(src, ""), fn (ch :: Str) -> Str {
    if str.len(ch) > 1 {
      "?"
    } else {
      ch
    }
  }), "")
}

# ASCII input needs no sanitising, and `str.is_ascii` (lex >= 0.10.14)
# decides that in one VM step; the per-char `sanitise_multibyte` pass
# only runs for input that actually has multi-byte chars.
fn parse(src :: Str) -> Result[Json, ParseErr] {
  let safe := if str.is_ascii(src) {
    src
  } else {
    sanitise_multibyte(src)
  }
  match parse_value(safe, 0) {
    Err(e1) => Err(e1),
    Ok(step) => {
      let end := skip_ws(safe, step.pos)
      if end == str.len(safe) {
        Ok(step.value)
      } else {
        Err({ pos: end, message: "trailing characters after JSON value" })
      }
    },
  }
}

# Parse and surface the failure as an `Errors` list — same shape as
# the rest of the library, so callers can drop it into `and_then`.
fn parse_into_errors(src :: Str) -> Result[Json, e.Errors] {
  match parse(src) {
    Ok(j) => Ok(j),
    Err(p) => Err(e.single("", e.code_parse(), str.concat(p.message, str.concat(" at byte ", int.to_str(p.pos))))),
  }
}

# ---- Top-level value dispatch -------------------------------------
fn parse_value(src :: Str, p :: Int) -> Result[ParseStep, ParseErr] {
  let p1 := skip_ws(src, p)
  if p1 >= str.len(src) {
    Err({ pos: p1, message: "unexpected end of input" })
  } else {
    let c := char_at(src, p1)
    match c {
      "{" => parse_object(src, p1),
      "[" => parse_array(src, p1),
      "\"" => parse_string_value(src, p1),
      "t" => parse_literal(src, p1, "true", JBool(true)),
      "f" => parse_literal(src, p1, "false", JBool(false)),
      "n" => parse_literal(src, p1, "null", JNull),
      _ => parse_number(src, p1),
    }
  }
}

# ---- Whitespace ---------------------------------------------------
# One recursive call per whitespace CHARACTER used to cost one
# interpreter step per character — fine for the few spaces between
# tokens, but a document with a long run of whitespace (a large
# indented/pretty-printed JSON blob, or one with padding) could exceed
# the VM's step budget and panic instead of returning a ParseErr. This
# does the same trim in a constant number of host calls: str.trim
# already strips both ends in one step, and str.find locates where the
# untrimmed prefix ends. `trimmed`'s first character is guaranteed
# non-whitespace (or `trimmed` is empty), so no whitespace-only prefix
# of `rest` can produce a false earlier match — the found offset is
# always the true length of the leading run.
fn skip_ws(src :: Str, p :: Int) -> Int {
  if p >= str.len(src) {
    p
  } else {
    let rest := str.slice(src, p, str.len(src))
    let trimmed := str.trim(rest)
    if str.is_empty(trimmed) {
      str.len(src)
    } else {
      match str.find(rest, trimmed, 0) {
        Some(offset) => p + offset,
        None => p,
      }
    }
  }
}

# ---- Keyword literals (true / false / null) -----------------------
fn parse_literal(src :: Str, p :: Int, word :: Str, value :: Json) -> Result[ParseStep, ParseErr] {
  let n := str.len(word)
  if p + n > str.len(src) {
    Err({ pos: p, message: str.concat("expected `", str.concat(word, "`")) })
  } else {
    let seen := str.slice(src, p, p + n)
    if seen == word {
      Ok({ pos: p + n, value: value })
    } else {
      Err({ pos: p, message: str.concat("expected `", str.concat(word, "`")) })
    }
  }
}

# ---- Numbers ------------------------------------------------------
#
# JSON number grammar (RFC 8259 §6):
#
#   number = [ minus ] int [ frac ] [ exp ]
#   int    = zero / ( digit1-9 *digit )
#   frac   = decimal-point 1*digit
#   exp    = e [ minus / plus ] 1*digit
#
# Lex's `float` literal grammar doesn't support exponents (filed as
# #325) so we can't directly write `2.5e10` as a Lex literal — but
# `str.to_float` accepts scientific notation, which is enough for
# the round-trip. We lex the JSON number into a substring and pass
# that substring to `str.to_float` / `str.to_int`.
fn parse_number(src :: Str, p :: Int) -> Result[ParseStep, ParseErr] {
  let start := p
  let p1 := if char_at(src, p) == "-" {
    p + 1
  } else {
    p
  }
  let p2 := skip_digits(src, p1)
  if p2 == p1 {
    Err({ pos: p, message: "expected number" })
  } else {
    let p3 := if peek_char(src, p2) == "." {
      skip_digits(src, p2 + 1)
    } else {
      p2
    }
    let p4 := match peek_char(src, p3) {
      "e" => skip_exponent(src, p3 + 1),
      "E" => skip_exponent(src, p3 + 1),
      _ => p3,
    }
    let text := str.slice(src, start, p4)
    if p3 == p2 and p4 == p3 {
      match str.to_int(text) {
        Some(n) => Ok({ pos: p4, value: JInt(n) }),
        None => match str.to_float(text) {
          Some(x) => Ok({ pos: p4, value: JFloat(x) }),
          None => Err({ pos: start, message: "invalid number" }),
        },
      }
    } else {
      match str.to_float(text) {
        Some(x) => Ok({ pos: p4, value: JFloat(x) }),
        None => Err({ pos: start, message: "invalid number" }),
      }
    }
  }
}

fn skip_digits(src :: Str, p :: Int) -> Int {
  if p >= str.len(src) {
    p
  } else {
    let c := char_at(src, p)
    if is_digit(c) {
      skip_digits(src, p + 1)
    } else {
      p
    }
  }
}

fn skip_exponent(src :: Str, p :: Int) -> Int {
  let p1 := match peek_char(src, p) {
    "+" => p + 1,
    "-" => p + 1,
    _ => p,
  }
  skip_digits(src, p1)
}

fn is_digit(c :: Str) -> Bool {
  match c {
    "0" => true,
    "1" => true,
    "2" => true,
    "3" => true,
    "4" => true,
    "5" => true,
    "6" => true,
    "7" => true,
    "8" => true,
    "9" => true,
    _ => false,
  }
}

fn hex_to_int(h :: Str) -> Int
  examples {
    hex_to_int("0") => 0,
    hex_to_int("a") => 10,
    hex_to_int("F") => 15
  }
{
  match h {
    "0" => 0,
    "1" => 1,
    "2" => 2,
    "3" => 3,
    "4" => 4,
    "5" => 5,
    "6" => 6,
    "7" => 7,
    "8" => 8,
    "9" => 9,
    "a" => 10,
    "b" => 11,
    "c" => 12,
    "d" => 13,
    "e" => 14,
    "f" => 15,
    "A" => 10,
    "B" => 11,
    "C" => 12,
    "D" => 13,
    "E" => 14,
    "F" => 15,
    _ => 0,
  }
}

# Map a Unicode BMP code point to a Lex Str. ASCII 0-126 are returned
# directly; anything above U+007E becomes "?" — same convention as
# the multi-byte sanitiser in parse_into_errors.
fn codepoint_to_ascii_str(cp :: Int) -> Str
  examples {
    codepoint_to_ascii_str(60) => "<",
    codepoint_to_ascii_str(62) => ">",
    codepoint_to_ascii_str(38) => "&",
    codepoint_to_ascii_str(32) => " ",
    codepoint_to_ascii_str(9000) => "?"
  }
{
  match cp {
    0 => " ",
    9 => "\t",
    10 => "\n",
    13 => "\r",
    32 => " ",
    33 => "!",
    34 => "\"",
    35 => "#",
    36 => "$",
    37 => "%",
    38 => "&",
    39 => "'",
    40 => "(",
    41 => ")",
    42 => "*",
    43 => "+",
    44 => ",",
    45 => "-",
    46 => ".",
    47 => "/",
    48 => "0",
    49 => "1",
    50 => "2",
    51 => "3",
    52 => "4",
    53 => "5",
    54 => "6",
    55 => "7",
    56 => "8",
    57 => "9",
    58 => ":",
    59 => ";",
    60 => "<",
    61 => "=",
    62 => ">",
    63 => "?",
    64 => "@",
    65 => "A",
    66 => "B",
    67 => "C",
    68 => "D",
    69 => "E",
    70 => "F",
    71 => "G",
    72 => "H",
    73 => "I",
    74 => "J",
    75 => "K",
    76 => "L",
    77 => "M",
    78 => "N",
    79 => "O",
    80 => "P",
    81 => "Q",
    82 => "R",
    83 => "S",
    84 => "T",
    85 => "U",
    86 => "V",
    87 => "W",
    88 => "X",
    89 => "Y",
    90 => "Z",
    91 => "[",
    92 => "\\",
    93 => "]",
    94 => "^",
    95 => "_",
    96 => "`",
    97 => "a",
    98 => "b",
    99 => "c",
    100 => "d",
    101 => "e",
    102 => "f",
    103 => "g",
    104 => "h",
    105 => "i",
    106 => "j",
    107 => "k",
    108 => "l",
    109 => "m",
    110 => "n",
    111 => "o",
    112 => "p",
    113 => "q",
    114 => "r",
    115 => "s",
    116 => "t",
    117 => "u",
    118 => "v",
    119 => "w",
    120 => "x",
    121 => "y",
    122 => "z",
    123 => "{",
    124 => "|",
    125 => "}",
    126 => "~",
    _ => "?",
  }
}

# ---- Strings ------------------------------------------------------
#
# JSON strings escape `\"`, `\\`, `\/`, `\b`, `\f`, `\n`, `\r`,
# `\t`, and `\uXXXX`. We implement everything except `\uXXXX`
# surrogate pair joining (BMP characters work; supplementary chars
# would need 4-hex-digit decoding + UTF-16 surrogate-pair joining).
fn parse_string_value(src :: Str, p :: Int) -> Result[ParseStep, ParseErr] {
  match parse_string_raw(src, p) {
    Err(e1) => Err(e1),
    Ok(r) => Ok({ pos: r.pos, value: JStr(r.text) }),
  }
}

type StringStep = { pos :: Int, text :: Str }

# `parse_string_raw` extracts a Str without wrapping in JStr —
# used both for top-level strings and for object keys.
fn parse_string_raw(src :: Str, p :: Int) -> Result[StringStep, ParseErr] {
  if char_at(src, p) != "\"" {
    Err({ pos: p, message: "expected `\"`" })
  } else {
    str_loop(src, p + 1, p + 1, [])
  }
}

# Jump to the next quote or backslash in one builtin call
# (`str.find_any`, lex >= 0.10.14) instead of recursing once per
# character. VM steps then scale with the number of escapes in the
# string, not its length: the old per-char loop spent 40 to 80 steps
# per character and hit the 10M-step budget on ~200 KB of string
# content (lex-lang#768). Indices are byte offsets because
# `sanitise_multibyte` has already made the input single-byte.
#
# `acc` accumulates chunks via `list.cons` (O(1) each) instead of
# `str.concat` (which copies both operands, making the old
# accumulation O(n^2) in the number of escapes — flagged but left
# unfixed by #31: "a string with an escape every few characters is
# quadratic... a chunk list would be the fix"). Reproduced live: an
# agent's normal, unremarkable conversation history — nothing
# adversarial, no single huge value, just many turns of ordinary
# escape-dense text — hit the 10M-step budget in this exact function
# by growing large enough for `str.concat`'s copying to dominate.
# `list.reverse` + `str.join` run once, at the closing quote, not on
# every escape.
fn str_loop(src :: Str, chunk_start :: Int, p :: Int, acc :: List[Str]) -> Result[StringStep, ParseErr] {
  match str.find_any(src, "\"\\", p) {
    None => Err({ pos: str.len(src), message: "unterminated string" }),
    Some(q) => {
      let acc2 := list.cons(str.slice(src, chunk_start, q), acc)
      if char_at(src, q) == "\"" {
        Ok({ pos: q + 1, text: str.join(list.reverse(acc2), "") })
      } else {
        match parse_escape(src, q + 1) {
          Err(e1) => Err(e1),
          Ok(s) => str_loop(src, s.pos, s.pos, list.cons(s.text, acc2)),
        }
      }
    },
  }
}

fn parse_escape(src :: Str, p :: Int) -> Result[StringStep, ParseErr] {
  if p >= str.len(src) {
    Err({ pos: p, message: "unterminated escape" })
  } else {
    let c := char_at(src, p)
    match c {
      "\"" => Ok({ pos: p + 1, text: "\"" }),
      "\\" => Ok({ pos: p + 1, text: "\\" }),
      "/" => Ok({ pos: p + 1, text: "/" }),
      "n" => Ok({ pos: p + 1, text: "\n" }),
      "r" => Ok({ pos: p + 1, text: "\r" }),
      "t" => Ok({ pos: p + 1, text: "\t" }),
      "b" => Ok({ pos: p + 1, text: "" }),
      "f" => Ok({ pos: p + 1, text: "" }),
      "u" => if p + 4 >= str.len(src) {
        Err({ pos: p, message: "incomplete \\uXXXX escape" })
      } else {
        let h1 := char_at(src, p + 1)
        let h2 := char_at(src, p + 2)
        let h3 := char_at(src, p + 3)
        let h4 := char_at(src, p + 4)
        let cp := hex_to_int(h1) * 4096 + hex_to_int(h2) * 256 + hex_to_int(h3) * 16 + hex_to_int(h4)
        Ok({ pos: p + 5, text: codepoint_to_ascii_str(cp) })
      },
      _ => Err({ pos: p, message: str.concat("invalid escape `\\", str.concat(c, "`")) }),
    }
  }
}

# ---- Arrays -------------------------------------------------------
fn parse_array(src :: Str, p :: Int) -> Result[ParseStep, ParseErr] {
  if char_at(src, p) != "[" {
    Err({ pos: p, message: "expected `[`" })
  } else {
    let p1 := skip_ws(src, p + 1)
    if peek_char(src, p1) == "]" {
      Ok({ pos: p1 + 1, value: JList([]) })
    } else {
      array_loop(src, p1, [])
    }
  }
}

# Builds the accumulator in reverse via `list.cons` (O(1) prepend)
# and pays a single `list.reverse` at the close — O(n) total
# instead of the O(n²) the old `list.concat` shape paid.
fn array_loop(src :: Str, p :: Int, acc :: List[Json]) -> Result[ParseStep, ParseErr] {
  match parse_value(src, p) {
    Err(e1) => Err(e1),
    Ok(step) => {
      let acc2 := list.cons(step.value, acc)
      let p1 := skip_ws(src, step.pos)
      match peek_char(src, p1) {
        "]" => Ok({ pos: p1 + 1, value: JList(list.reverse(acc2)) }),
        "," => array_loop(src, skip_ws(src, p1 + 1), acc2),
        _ => Err({ pos: p1, message: "expected `,` or `]`" }),
      }
    },
  }
}

# ---- Objects ------------------------------------------------------
fn parse_object(src :: Str, p :: Int) -> Result[ParseStep, ParseErr] {
  if char_at(src, p) != "{" {
    Err({ pos: p, message: "expected `{`" })
  } else {
    let p1 := skip_ws(src, p + 1)
    if peek_char(src, p1) == "}" {
      Ok({ pos: p1 + 1, value: JObj([]) })
    } else {
      object_loop(src, p1, [])
    }
  }
}

# Same cons-then-reverse pattern as `array_loop` — O(n) builder.
fn object_loop(src :: Str, p :: Int, acc :: List[(Str, Json)]) -> Result[ParseStep, ParseErr] {
  match parse_string_raw(src, p) {
    Err(e1) => Err(e1),
    Ok(key) => {
      let p1 := skip_ws(src, key.pos)
      if peek_char(src, p1) != ":" {
        Err({ pos: p1, message: "expected `:` after object key" })
      } else {
        match parse_value(src, p1 + 1) {
          Err(e1) => Err(e1),
          Ok(step) => {
            let acc2 := list.cons((key.text, step.value), acc)
            let p2 := skip_ws(src, step.pos)
            match peek_char(src, p2) {
              "}" => Ok({ pos: p2 + 1, value: JObj(list.reverse(acc2)) }),
              "," => object_loop(src, skip_ws(src, p2 + 1), acc2),
              _ => Err({ pos: p2, message: "expected `,` or `}`" }),
            }
          },
        }
      }
    },
  }
}

# ---- Character helpers --------------------------------------------
# Return the char at position `p` as a single-char `Str`, or "" past the end.
# Uses `str.char_at` (O(1)) rather than `str.slice(src, p, p+1)` whose codepoint
# index resolves via `char_indices().nth(p)` — O(p) — which made the whole parse
# O(n²) (and blew the VM step limit on large inputs). `sanitise_multibyte` has
# already collapsed every multi-byte char to a single ASCII byte, so direct byte
# indexing is correct here.
fn char_at(src :: Str, p :: Int) -> Str {
  str.char_at(src, p)
}

# Like `char_at`, but past-the-end returns `""` instead of erroring.
# Lets dispatch sites use `match` directly on the result.
fn peek_char(src :: Str, p :: Int) -> Str {
  if p >= str.len(src) {
    ""
  } else {
    char_at(src, p)
  }
}

# ============================================================
# Walker / extractor surface
# ============================================================
# Resolve a key in a JObj. Returns the wrapped Json, or None if the
# key is absent or the value isn't an object. The library never
# panics on a missing key — that's the whole point of the ADT.
fn get_field(j :: Json, key :: Str) -> Option[Json] {
  match j {
    JObj(entries) => find_entry(entries, key),
    _ => None,
  }
}

fn find_entry(entries :: List[(Str, Json)], key :: Str) -> Option[Json] {
  list.fold(entries, None, fn (acc :: Option[Json], pair :: (Str, Json)) -> Option[Json] {
    match acc {
      Some(_) => acc,
      None => match pair {
        (k, v) => if k == key {
          Some(v)
        } else {
          None
        },
      },
    }
  })
}

# ---- Type coercion at the ADT level -------------------------------
#
# Each `as_xxx` returns `Option[T]`: `Some(v)` if the variant is the
# expected one, `None` otherwise. The caller decides whether absence
# is an error (use `j_str` etc. for the error-emitting versions).
fn as_str(j :: Json) -> Option[Str] {
  match j {
    JStr(s) => Some(s),
    _ => None,
  }
}

fn as_int(j :: Json) -> Option[Int] {
  match j {
    JInt(n) => Some(n),
    _ => None,
  }
}

fn as_float(j :: Json) -> Option[Float] {
  match j {
    JFloat(x) => Some(x),
    JInt(n) => Some(int.to_float(n)),
    _ => None,
  }
}

fn as_bool(j :: Json) -> Option[Bool] {
  match j {
    JBool(b) => Some(b),
    _ => None,
  }
}

fn as_list(j :: Json) -> Option[List[Json]] {
  match j {
    JList(xs) => Some(xs),
    _ => None,
  }
}

fn as_obj(j :: Json) -> Option[List[(Str, Json)]] {
  match j {
    JObj(xs) => Some(xs),
    _ => None,
  }
}

fn is_null(j :: Json) -> Bool {
  match j {
    JNull => true,
    _ => false,
  }
}

# Pretty-printed variant tag — used in error messages.
fn type_name(j :: Json) -> Str {
  match j {
    JNull => "null",
    JBool(_) => "boolean",
    JInt(_) => "integer",
    JFloat(_) => "number",
    JStr(_) => "string",
    JList(_) => "array",
    JObj(_) => "object",
  }
}

# ---- Error-emitting field extractors ------------------------------
#
# `j_str` / `j_int` / `j_float` / `j_bool` / `j_list` / `j_obj` take
# a path, a parent `Json` value, a field name, and (where relevant)
# a constraint list. They emit a single `error.Error` for a missing
# field, a type mismatch, or a constraint failure.
#
# The `_optional_*` variants treat absence as Ok(None).
fn j_str(path_prefix :: Str, parent :: Json, field :: Str, checks :: List[c.StrCheck]) -> Result[Str, e.Errors] {
  let p := join_path(path_prefix, field)
  match get_field(parent, field) {
    None => Err(e.single(p, e.code_missing(), "field is required")),
    Some(j) => match as_str(j) {
      Some(s) => f.check_str(p, s, checks),
      None => Err(e.single(p, e.code_type(), str.concat("expected string, got ", type_name(j)))),
    },
  }
}

fn j_int(path_prefix :: Str, parent :: Json, field :: Str, checks :: List[c.IntCheck]) -> Result[Int, e.Errors] {
  let p := join_path(path_prefix, field)
  match get_field(parent, field) {
    None => Err(e.single(p, e.code_missing(), "field is required")),
    Some(j) => match as_int(j) {
      Some(n) => f.check_int(p, n, checks),
      None => Err(e.single(p, e.code_type(), str.concat("expected integer, got ", type_name(j)))),
    },
  }
}

fn j_float(path_prefix :: Str, parent :: Json, field :: Str, checks :: List[c.FloatCheck]) -> Result[Float, e.Errors] {
  let p := join_path(path_prefix, field)
  match get_field(parent, field) {
    None => Err(e.single(p, e.code_missing(), "field is required")),
    Some(j) => match as_float(j) {
      Some(x) => f.check_float(p, x, checks),
      None => Err(e.single(p, e.code_type(), str.concat("expected number, got ", type_name(j)))),
    },
  }
}

fn j_bool(path_prefix :: Str, parent :: Json, field :: Str) -> Result[Bool, e.Errors] {
  let p := join_path(path_prefix, field)
  match get_field(parent, field) {
    None => Err(e.single(p, e.code_missing(), "field is required")),
    Some(j) => match as_bool(j) {
      Some(b) => Ok(b),
      None => Err(e.single(p, e.code_type(), str.concat("expected boolean, got ", type_name(j)))),
    },
  }
}

fn j_obj(path_prefix :: Str, parent :: Json, field :: Str) -> Result[Json, e.Errors] {
  let p := join_path(path_prefix, field)
  match get_field(parent, field) {
    None => Err(e.single(p, e.code_missing(), "field is required")),
    Some(j) => match as_obj(j) {
      Some(_) => Ok(j),
      None => Err(e.single(p, e.code_type(), str.concat("expected object, got ", type_name(j)))),
    },
  }
}

fn j_list(path_prefix :: Str, parent :: Json, field :: Str) -> Result[List[Json], e.Errors] {
  let p := join_path(path_prefix, field)
  match get_field(parent, field) {
    None => Err(e.single(p, e.code_missing(), "field is required")),
    Some(j) => match as_list(j) {
      Some(xs) => Ok(xs),
      None => Err(e.single(p, e.code_type(), str.concat("expected array, got ", type_name(j)))),
    },
  }
}

# ---- Optional extractors ------------------------------------------
fn j_optional_str(path_prefix :: Str, parent :: Json, field :: Str, checks :: List[c.StrCheck]) -> Result[Option[Str], e.Errors] {
  let p := join_path(path_prefix, field)
  match get_field(parent, field) {
    None => Ok(None),
    Some(j) => if is_null(j) {
      Ok(None)
    } else {
      match as_str(j) {
        Some(s) => match f.check_str(p, s, checks) {
          Ok(v) => Ok(Some(v)),
          Err(es) => Err(es),
        },
        None => Err(e.single(p, e.code_type(), str.concat("expected string or null, got ", type_name(j)))),
      }
    },
  }
}

fn j_optional_int(path_prefix :: Str, parent :: Json, field :: Str, checks :: List[c.IntCheck]) -> Result[Option[Int], e.Errors] {
  let p := join_path(path_prefix, field)
  match get_field(parent, field) {
    None => Ok(None),
    Some(j) => if is_null(j) {
      Ok(None)
    } else {
      match as_int(j) {
        Some(n) => match f.check_int(p, n, checks) {
          Ok(v) => Ok(Some(v)),
          Err(es) => Err(es),
        },
        None => Err(e.single(p, e.code_type(), str.concat("expected integer or null, got ", type_name(j)))),
      }
    },
  }
}

# ---- Path joining -------------------------------------------------
fn join_path(prefix :: Str, leaf :: Str) -> Str {
  if str.is_empty(prefix) {
    leaf
  } else {
    str.concat(prefix, str.concat(".", leaf))
  }
}

# ============================================================
# Dotted-path navigation
# ============================================================
#
# `get_path(j, "user.address.zip")` walks dotted segments. Each
# segment must resolve through `get_field` (so the intermediate
# nodes are objects); on any mismatch the result is `None`.
#
# This is a read-only mirror of pydantic's nested field access; it
# doesn't decode types — only navigates. Pair with `as_str` /
# `as_int` to extract a typed leaf.
fn get_path(j :: Json, path :: Str) -> Option[Json] {
  let segments := str.split(path, ".")
  list.fold(segments, Some(j), fn (acc :: Option[Json], seg :: Str) -> Option[Json] {
    match acc {
      None => None,
      Some(j_inner) => get_field(j_inner, seg),
    }
  })
}

# Error-emitting variants — same shape as `j_str` / `j_int` but the
# field argument is a dotted path. The path appears verbatim in the
# error so a missing leaf surfaces as `user.address.zip: ...`.
fn j_str_at(j :: Json, path :: Str, checks :: List[c.StrCheck]) -> Result[Str, e.Errors] {
  match get_path(j, path) {
    None => Err(e.single(path, e.code_missing(), "field is required")),
    Some(v) => match as_str(v) {
      Some(s) => f.check_str(path, s, checks),
      None => Err(e.single(path, e.code_type(), str.concat("expected string, got ", type_name(v)))),
    },
  }
}

fn j_int_at(j :: Json, path :: Str, checks :: List[c.IntCheck]) -> Result[Int, e.Errors] {
  match get_path(j, path) {
    None => Err(e.single(path, e.code_missing(), "field is required")),
    Some(v) => match as_int(v) {
      Some(n) => f.check_int(path, n, checks),
      None => Err(e.single(path, e.code_type(), str.concat("expected integer, got ", type_name(v)))),
    },
  }
}

fn j_optional_str_at(j :: Json, path :: Str, checks :: List[c.StrCheck]) -> Result[Option[Str], e.Errors] {
  match get_path(j, path) {
    None => Ok(None),
    Some(v) => if is_null(v) {
      Ok(None)
    } else {
      match as_str(v) {
        Some(s) => match f.check_str(path, s, checks) {
          Ok(s2) => Ok(Some(s2)),
          Err(es) => Err(es),
        },
        None => Err(e.single(path, e.code_type(), str.concat("expected string or null, got ", type_name(v)))),
      }
    },
  }
}

# ============================================================
# Stringify (Json → Str)
# ============================================================
#
# Inverse of `parse`. Useful for tests (round-tripping), debug
# logging, and re-serializing after a validated transformation.
# Output is compact (no whitespace); use `stringify_pretty` for
# indented output.
fn stringify(j :: Json) -> Str {
  match j {
    JNull => "null",
    JBool(b) => if b {
      "true"
    } else {
      "false"
    },
    JInt(n) => int.to_str(n),
    JFloat(x) => float.to_str(x),
    JStr(s) => str.concat("\"", str.concat(escape_str(s), "\"")),
    JList(xs) => {
      let parts := list.map(xs, fn (item :: Json) -> Str {
        stringify(item)
      })
      str.concat("[", str.concat(str.join(parts, ","), "]"))
    },
    JObj(es) => {
      let parts := list.map(es, fn (pair :: (Str, Json)) -> Str {
        match pair {
          (k, v) => str.concat(str.concat("\"", str.concat(escape_str(k), "\":")), stringify(v)),
        }
      })
      str.concat("{", str.concat(str.join(parts, ","), "}"))
    },
  }
}

# Two-space indented variant. Top-level value gets no leading
# whitespace; nested objects/arrays are indented.
fn stringify_pretty(j :: Json) -> Str {
  stringify_at(j, 0)
}

fn stringify_at(j :: Json, depth :: Int) -> Str {
  match j {
    JNull => "null",
    JBool(b) => if b {
      "true"
    } else {
      "false"
    },
    JInt(n) => int.to_str(n),
    JFloat(x) => float.to_str(x),
    JStr(s) => str.concat("\"", str.concat(escape_str(s), "\"")),
    JList(xs) => if list.is_empty(xs) {
      "[]"
    } else {
      let inner_indent := indent_str(depth + 1)
      let close_indent := indent_str(depth)
      let parts := list.map(xs, fn (item :: Json) -> Str {
        str.concat(inner_indent, stringify_at(item, depth + 1))
      })
      str.concat("[\n", str.concat(str.join(parts, ",\n"), str.concat("\n", str.concat(close_indent, "]"))))
    },
    JObj(es) => if list.is_empty(es) {
      "{}"
    } else {
      let inner_indent := indent_str(depth + 1)
      let close_indent := indent_str(depth)
      let parts := list.map(es, fn (pair :: (Str, Json)) -> Str {
        match pair {
          (k, v) => str.concat(inner_indent, str.concat("\"", str.concat(escape_str(k), str.concat("\": ", stringify_at(v, depth + 1))))),
        }
      })
      str.concat("{\n", str.concat(str.join(parts, ",\n"), str.concat("\n", str.concat(close_indent, "}"))))
    },
  }
}

# Escape a Str for embedding inside JSON quotes. We escape the
# characters that the parser also knows how to round-trip: `"`,
# `\`, `\n`, `\r`, `\t`. The pair is exact: any output of
# `stringify` parses back via `parse`.
#
# Five whole-string `str.replace` passes, backslash first so the
# backslashes the other passes introduce are not escaped again. Each
# pass is one builtin call that runs in O(n) native time, so escaping
# costs a constant number of VM steps however long the string is.
# The previous shape (a per-char fold with `str.concat`) copied the
# accumulator on every step and was O(n²), and a per-char `list.map`
# still spends VM steps per char, which exhausts the step budget on a
# ~500 K char string (lex-lang#768).
fn escape_str(s :: Str) -> Str
  examples {
    escape_str("plain") => "plain",
    escape_str("a\"b") => "a\\\"b",
    escape_str("a\\b") => "a\\\\b",
    escape_str("a\nb\rc\td") => "a\\nb\\rc\\td",
    escape_str("\\\"") => "\\\\\\\""
  }
{
  let s1 := str.replace(s, "\\", "\\\\")
  let s2 := str.replace(s1, "\"", "\\\"")
  let s3 := str.replace(s2, "\n", "\\n")
  let s4 := str.replace(s3, "\r", "\\r")
  str.replace(s4, "\t", "\\t")
}

fn indent_str(depth :: Int) -> Str {
  if depth <= 0 {
    ""
  } else {
    str.concat("  ", indent_str(depth - 1))
  }
}

# Alias kept for source compatibility — identical to `stringify`.
fn encode(j :: Json) -> Str {
  stringify(j)
}

