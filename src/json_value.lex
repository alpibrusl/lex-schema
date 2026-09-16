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

import "std.bytes" as bytes

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
# Multibyte input is parsed, not sanitised. Every non-ASCII character used to
# be replaced with "?" before parsing, because the scanner mixed byte and
# character indexing; with every position character-indexed, UTF-8 round-trips
# (alpibrusl/lex-lang#890).
fn parse(src :: Str) -> Result[Json, ParseErr] {
  let safe := src
  match parse_value(safe, 0) {
    Err(e1) => Err(e1),
    Ok(step) => {
      let end := skip_ws(safe, step.pos)
      if str.is_empty(char_at(safe, end)) {
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
  if str.is_empty(char_at(src, p1)) {
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
# Advance the cursor past a run of JSON whitespace (RFC 8259 §2: space,
# tab, LF, CR — nothing else). One tail-recursive step per whitespace
# character, each an O(1) `char_at`; the run between tokens is tiny, so
# this is O(total whitespace) = O(n) across the document with ZERO string
# copies.
#
# It must stay this way. A previous "optimization" sliced the whole
# remaining input (`str.slice(src, p, len)`) on every call and trimmed it
# — O(n) copied bytes per token, which made the whole parser O(n²): a
# ~1MB pretty-printed document took 193s of CPU and then blew the
# 10M-step limit instead of returning. `skip_digits` right below uses
# this same cursor pattern; keep them consistent.
fn is_json_ws(c :: Str) -> Bool {
  c == " " or c == "\t" or c == "\n" or c == "\r"
}

fn skip_ws(src :: Str, p :: Int) -> Int {
  if str.is_empty(char_at(src, p)) {
    p
  } else {
    if is_json_ws(char_at(src, p)) {
      skip_ws(src, p + 1)
    } else {
      p
    }
  }
}

# ---- Keyword literals (true / false / null) -----------------------
#
# `true`/`false`/`null` are ASCII, so `str.len` (bytes) is also the character
# length. `slice` clamps at the end of input, so a truncated tail simply fails
# the comparison; no separate bounds check is needed, and adding one would mean
# a whole-string length call in a hot path (see `char_len_slow`).
fn parse_literal(src :: Str, p :: Int, word :: Str, value :: Json) -> Result[ParseStep, ParseErr] {
  let n := str.len(word)
  let seen := str.slice(src, p, p + n)
  if seen == word {
    Ok({ pos: p + n, value: value })
  } else {
    Err({ pos: p, message: str.concat("expected `", str.concat(word, "`")) })
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
  if str.is_empty(char_at(src, p)) {
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

# Encode a Unicode scalar value as UTF-8.
#
# This replaces a lookup table that returned ASCII directly and mapped EVERY
# code point above U+007E to "?", so `\u00e9` came back as `?` rather than
# `é`. That was the same "destroy it rather than fail" convention as the old
# multi-byte sanitiser, and it is no longer needed: with the scanner
# character-indexed, the parser can return the real character
# (alpibrusl/lex-lang#890).
#
# The table is not replaced with a bigger table — `bytes.u8(cp)` already gives
# the right byte for ASCII, so every one of its arms was an identity mapping.
#
# Division and remainder stand in for shift and mask: `cp / 64` is `cp >> 6`
# and `cp % 64` is `cp & 0x3F`, which is the arithmetic UTF-8 is defined in.
# An unpaired surrogate encodes to bytes that are not valid UTF-8; `to_str`
# rejects them and U+FFFD, the standard replacement character, is substituted
# rather than silently emitting something else.
fn codepoint_to_str(cp :: Int) -> Str
  examples {
    codepoint_to_str(60) => "<",
    codepoint_to_str(32) => " ",
    codepoint_to_str(233) => "é",
    codepoint_to_str(8212) => "—",
    codepoint_to_str(128025) => "🐙"
  }
{
  let bs := if cp < 128 {
    [bytes.u8(cp)]
  } else {
    if cp < 2048 {
      [bytes.u8(192 + cp / 64), bytes.u8(128 + cp % 64)]
    } else {
      if cp < 65536 {
        [bytes.u8(224 + cp / 4096), bytes.u8(128 + cp / 64 % 64), bytes.u8(128 + cp % 64)]
      } else {
        [bytes.u8(240 + cp / 262144), bytes.u8(128 + cp / 4096 % 64), bytes.u8(128 + cp / 64 % 64), bytes.u8(128 + cp % 64)]
      }
    }
  }
  match bytes.to_str(bytes.concat_all(bs)) {
    Err(_) => "�",
    Ok(t) => t,
  }
}

# The four hex digits of a `\uXXXX` escape whose backslash-u sits at `p`.
fn hex4(src :: Str, p :: Int) -> Int {
  hex_to_int(char_at(src, p + 1)) * 4096 + hex_to_int(char_at(src, p + 2)) * 256 + hex_to_int(char_at(src, p + 3)) * 16 + hex_to_int(char_at(src, p + 4))
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
    None => Err({ pos: char_len_slow(src), message: "unterminated string" }),
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

# SURROGATE PAIRS. Anything above U+FFFF reaches JSON as a UTF-16 surrogate
# PAIR — an octopus is "\\uD83D\\uDC19". Decoding the halves independently
# yields two unpaired surrogates, which are not Unicode scalar values and do
# not encode, so `\\u` recombines a high surrogate with the low one that
# follows it. A high surrogate NOT followed by a low one is left alone and
# becomes U+FFFD.
fn parse_escape(src :: Str, p :: Int) -> Result[StringStep, ParseErr] {
  if str.is_empty(char_at(src, p)) {
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
      "u" => if str.is_empty(char_at(src, p + 4)) {
        Err({ pos: p, message: "incomplete \\uXXXX escape" })
      } else {
        let cp := hex4(src, p)
        if cp >= 55296 and cp <= 56319 and char_at(src, p + 5) == "\\" and char_at(src, p + 6) == "u" and not str.is_empty(char_at(src, p + 10)) {
          let lo := hex4(src, p + 6)
          if lo >= 56320 and lo <= 57343 {
            Ok({ pos: p + 11, text: codepoint_to_str(65536 + (cp - 55296) * 1024 + (lo - 56320)) })
          } else {
            Ok({ pos: p + 5, text: codepoint_to_str(cp) })
          }
        } else {
          Ok({ pos: p + 5, text: codepoint_to_str(cp) })
        }
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
#
# CHARACTER-indexed, not byte-indexed. `std.str` mixes the two conventions and
# says so in its own spec: `len` and `char_at` count BYTES, while `slice`,
# `find`, `find_any` and `split` count CHARACTERS (alpibrusl/lex-lang#890).
# This scanner takes its positions from `find_any` and extracts with `slice`,
# so every position here is a character index; reading with `str.char_at` was
# the one byte-indexed step, and on multibyte input it landed mid-sequence and
# returned "". That is why `parse` used to fail on a literal em dash, and why
# the old workaround replaced non-ASCII with "?" rather than fail.
#
# On cost, since an earlier comment here had it wrong and the wrong version is
# what forced the "?" workaround: `str.slice` is NOT O(p) from the start of the
# string. Its documented cost is the distance from the previous slice or find
# on the same string, so a scan that only ever moves FORWARD is O(1) amortised
# per character. Measured: single-character slices walking a string forward are
# linear (2K/8K/32K chars -> 1/4/17 ms), while touching an earlier position
# between reads is quadratic (2K/8K -> 2/23 ms).
#
# The rule this imposes on the scanner is therefore: never look backwards.
# Extract a run before probing past its end, and never call a whole-string
# length function from a bounds check — see `char_len_slow`.
fn char_at(src :: Str, p :: Int) -> Str {
  str.slice(src, p, p + 1)
}

# End-of-input position in CHARACTERS, for error messages only.
#
# O(n) time AND O(n) allocation: it splits the whole document into a list of
# one-character strings. Calling it from a bounds check — once per character
# scanned — is what made `parse` quadratic; a 4x larger escape-dense input
# took 47x longer, and large documents hit the 10M-step budget outright.
#
# The scanner must never call this. Bounds checks use `char_at` instead:
# `str.slice` clamps, so an index at or past the end yields "", which is an
# exact end-of-input test in O(1). This remains only on error paths, which
# run once and then stop parsing.
fn char_len_slow(src :: Str) -> Int {
  list.len(str.split(src, ""))
}

# Like `char_at`, but past-the-end returns `""` instead of erroring.
# Lets dispatch sites use `match` directly on the result.
fn peek_char(src :: Str, p :: Int) -> Str {
  char_at(src, p)
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
fn hex_digit(d :: Int) -> Str {
  match d {
    0 => "0",
    1 => "1",
    2 => "2",
    3 => "3",
    4 => "4",
    5 => "5",
    6 => "6",
    7 => "7",
    8 => "8",
    9 => "9",
    10 => "a",
    11 => "b",
    12 => "c",
    13 => "d",
    14 => "e",
    _ => "f",
  }
}

# The 1-character string for byte `n` (0..255). Control bytes 0x00-0x1f are
# valid single-byte UTF-8, so `to_str` always succeeds here.
fn char_of_byte(n :: Int) -> Str {
  match bytes.to_str(bytes.u8(n)) {
    Ok(c) => c,
    Err(_) => "",
  }
}

# JSON (RFC 8259 §7) requires EVERY control character U+0000-U+001F to be
# escaped. The fast replace chain above only covers `"` `\` `\n` `\r` `\t`;
# a raw ESC / form-feed / NUL (common in bash, grep, ANSI-coloured tool
# output) would otherwise be emitted verbatim, producing a string that
# `json.dumps`, Ollama's `/api/chat`, and any strict JSON parser reject as
# an invalid control character (this is exactly what 400'd local qwen tool
# turns after a tool result carried an ANSI escape). Escape the remaining
# 0x00-0x08, 0x0b, 0x0c, 0x0e-0x1f to `\u00XX`. One native `str.replace`
# per code point, so still O(n); done last so the `\` in `\u00XX` isn't
# re-escaped by the backslash pass.
fn escape_controls(s :: Str) -> Str {
  list.fold(list.range(0, 32), s, fn (acc :: Str, n :: Int) -> Str {
    if n == 9 or n == 10 or n == 13 {
      acc
    } else {
      str.replace(acc, char_of_byte(n), str.concat("\\u00", str.concat(hex_digit(n / 16), hex_digit(n % 16))))
    }
  })
}

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
  let s5 := str.replace(s4, "\t", "\\t")
  escape_controls(s5)
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

