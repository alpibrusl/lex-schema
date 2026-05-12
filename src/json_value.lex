# lex-pydantic — first-class JSON ADT + parser
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
# Performance note: `str.slice` is O(input) per call, so this
# parser is O(n^2) on the input length. For multi-megabyte
# payloads, profile before adopting; for typical request bodies
# under a few hundred KB it's perfectly adequate.

import "std.str"   as str
import "std.int"   as int
import "std.float" as float
import "std.list"  as list

import "./error" as e
import "./constraints" as c
import "./field" as f

# ---- Json ADT -----------------------------------------------------

type Json =
    JNull
  | JBool(Bool)
  | JInt(Int)
  | JFloat(Float)
  | JStr(Str)
  | JList(List[Json])
  | JObj(List[(Str, Json)])

# Parser failure carries a byte offset into the input and a message.
type ParseErr = { pos :: Int, message :: Str }

# A parse step returns the new cursor + value, or a ParseErr.
# Encoded as Result so it threads cleanly through `match`.
type ParseStep = { pos :: Int, value :: Json }

# ---- Helper constructors ------------------------------------------
#
# Lex's record-alias unfolding only triggers when a Record and a
# Con(alias) meet at the *top* of a unification pair. Once they're
# nested under another constructor (`Result[Json, ParseErr]`,
# `Option[StringStep]`, ...) the coercion stops applying. The cure
# is to call a helper whose return type is the alias name — the
# constructor's return type pins the produced value to the
# nominal form so callers see `ParseErr` end-to-end.

fn mk_err(pos :: Int, message :: Str) -> ParseErr {
  { pos: pos, message: message }
}

fn mk_step(pos :: Int, value :: Json) -> ParseStep {
  { pos: pos, value: value }
}

fn mk_string_step(pos :: Int, text :: Str) -> StringStep {
  { pos: pos, text: text }
}

# ---- Public entry point -------------------------------------------

# Parse a complete JSON document. Trailing whitespace is allowed
# but trailing non-whitespace garbage is a parse error.
fn parse(src :: Str) -> Result[Json, ParseErr] {
  match parse_value(src, 0) {
    Err(e1) => Err(e1),
    Ok(step) => {
      let end := skip_ws(src, step.pos)
      if end == str.len(src) {
        Ok(step.value)
      } else {
        Err(mk_err(end, "trailing characters after JSON value"))
      }
    },
  }
}

# Parse and surface the failure as an `Errors` list — same shape as
# the rest of the library, so callers can drop it into `and_then`.
fn parse_into_errors(src :: Str) -> Result[Json, List[e.Error]] {
  match parse(src) {
    Ok(j)  => Ok(j),
    Err(p) => Err(e.single("", e.code_parse(),
      str.concat(p.message,
        str.concat(" at byte ", int.to_str(p.pos))))),
  }
}

# ---- Top-level value dispatch -------------------------------------

fn parse_value(src :: Str, p :: Int) -> Result[ParseStep, ParseErr] {
  let p1 := skip_ws(src, p)
  if p1 >= str.len(src) {
    Err(mk_err(p1, "unexpected end of input"))
  } else {
    let c := char_at(src, p1)
    match c {
      "{"  => parse_object(src, p1),
      "["  => parse_array(src, p1),
      "\"" => parse_string_value(src, p1),
      "t"  => parse_literal(src, p1, "true",  JBool(true)),
      "f"  => parse_literal(src, p1, "false", JBool(false)),
      "n"  => parse_literal(src, p1, "null",  JNull),
      _    => parse_number(src, p1),
    }
  }
}

# ---- Whitespace ---------------------------------------------------

fn skip_ws(src :: Str, p :: Int) -> Int {
  if p >= str.len(src) { p }
  else {
    let c := char_at(src, p)
    if c == " " or c == "\t" or c == "\n" or c == "\r" {
      skip_ws(src, p + 1)
    } else { p }
  }
}

# ---- Keyword literals (true / false / null) -----------------------

fn parse_literal(
  src :: Str,
  p :: Int,
  word :: Str,
  value :: Json
) -> Result[ParseStep, ParseErr] {
  let n := str.len(word)
  if p + n > str.len(src) {
    Err(mk_err(p, str.concat("expected `", str.concat(word, "`"))))
  } else {
    let seen := str.slice(src, p, p + n)
    if seen == word {
      Ok(mk_step(p + n, value))
    } else {
      Err(mk_err(p, str.concat("expected `", str.concat(word, "`"))))
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
  let p1 := if char_at(src, p) == "-" { p + 1 } else { p }
  let p2 := skip_digits(src, p1)
  if p2 == p1 {
    Err(mk_err(p, "expected number"))
  } else {
    let p3 := if peek_char(src, p2) == "." {
      skip_digits(src, p2 + 1)
    } else { p2 }
    let p4 := match peek_char(src, p3) {
      "e" => skip_exponent(src, p3 + 1),
      "E" => skip_exponent(src, p3 + 1),
      _   => p3,
    }
    let text := str.slice(src, start, p4)
    # Integer if no `.`, `e`, or `E` consumed.
    if p3 == p2 and p4 == p3 {
      match str.to_int(text) {
        Some(n) => Ok(mk_step(p4, JInt(n))),
        None    => match str.to_float(text) {
          Some(x) => Ok(mk_step(p4, JFloat(x))),
          None    => Err(mk_err(start, "invalid number")),
        },
      }
    } else {
      match str.to_float(text) {
        Some(x) => Ok(mk_step(p4, JFloat(x))),
        None    => Err(mk_err(start, "invalid number")),
      }
    }
  }
}

fn skip_digits(src :: Str, p :: Int) -> Int {
  if p >= str.len(src) { p }
  else {
    let c := char_at(src, p)
    if is_digit(c) { skip_digits(src, p + 1) } else { p }
  }
}

fn skip_exponent(src :: Str, p :: Int) -> Int {
  let p1 := match peek_char(src, p) {
    "+" => p + 1,
    "-" => p + 1,
    _   => p,
  }
  skip_digits(src, p1)
}

fn is_digit(c :: Str) -> Bool {
  match c {
    "0" => true, "1" => true, "2" => true, "3" => true, "4" => true,
    "5" => true, "6" => true, "7" => true, "8" => true, "9" => true,
    _   => false,
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
    Ok(r)   => Ok(mk_step(r.pos, JStr(r.text))),
  }
}

type StringStep = { pos :: Int, text :: Str }

# `parse_string_raw` extracts a Str without wrapping in JStr —
# used both for top-level strings and for object keys.
fn parse_string_raw(src :: Str, p :: Int) -> Result[StringStep, ParseErr] {
  if char_at(src, p) != "\"" {
    Err(mk_err(p, "expected `\"`"))
  } else {
    # Two-cursor scan: `chunk_start` marks the start of the current
    # escape-free run, `p` is the read head. We only `str.concat`
    # when we hit an escape — for the common case (no escapes) the
    # whole string is extracted with a single O(n) `str.slice`,
    # avoiding the O(n²) char-by-char accumulator the original
    # implementation paid for every input.
    str_loop(src, p + 1, p + 1, "")
  }
}

fn str_loop(
  src :: Str,
  chunk_start :: Int,
  p :: Int,
  acc :: Str
) -> Result[StringStep, ParseErr] {
  if p >= str.len(src) {
    Err(mk_err(p, "unterminated string"))
  } else {
    let c := char_at(src, p)
    if c == "\"" {
      let chunk := str.slice(src, chunk_start, p)
      let out := if str.is_empty(acc) { chunk } else { str.concat(acc, chunk) }
      Ok(mk_string_step(p + 1, out))
    } else {
      if c == "\\" {
        let chunk := str.slice(src, chunk_start, p)
        let acc2 := if str.is_empty(acc) { chunk } else { str.concat(acc, chunk) }
        match parse_escape(src, p + 1) {
          Err(e1) => Err(e1),
          Ok(s)   => str_loop(src, s.pos, s.pos, str.concat(acc2, s.text)),
        }
      } else {
        # No escape — stay inside the current chunk; advance the
        # read head without copying.
        str_loop(src, chunk_start, p + 1, acc)
      }
    }
  }
}

fn parse_escape(src :: Str, p :: Int) -> Result[StringStep, ParseErr] {
  if p >= str.len(src) {
    Err(mk_err(p, "unterminated escape"))
  } else {
    let c := char_at(src, p)
    # Lex's string-literal grammar supports `\n`, `\t`, `\r`, `\\`,
    # `\"`, `\0` only — so we can't materialize `\b` / `\f` /
    # `\uXXXX` here without runtime char-code construction. The
    # full set is rare in real JSON; we accept the common subset
    # and error on the rest with a clear message so callers can
    # decide whether to pre-process input or open a bug.
    match c {
      "\"" => Ok(mk_string_step(p + 1, "\"")),
      "\\" => Ok(mk_string_step(p + 1, "\\")),
      "/"  => Ok(mk_string_step(p + 1, "/")),
      "n"  => Ok(mk_string_step(p + 1, "\n")),
      "r"  => Ok(mk_string_step(p + 1, "\r")),
      "t"  => Ok(mk_string_step(p + 1, "\t")),
      "b"  => Err(mk_err(p, "`\\b` escape not yet supported")),
      "f"  => Err(mk_err(p, "`\\f` escape not yet supported")),
      "u"  => Err(mk_err(p, "`\\uXXXX` escapes not yet supported")),
      _    => Err(mk_err(p, str.concat("invalid escape `\\", str.concat(c, "`")))),
    }
  }
}

# ---- Arrays -------------------------------------------------------

fn parse_array(src :: Str, p :: Int) -> Result[ParseStep, ParseErr] {
  if char_at(src, p) != "[" {
    Err(mk_err(p, "expected `[`"))
  } else {
    let p1 := skip_ws(src, p + 1)
    if peek_char(src, p1) == "]" {
      Ok(mk_step(p1 + 1, JList([])))
    } else {
      array_loop(src, p1, [])
    }
  }
}

fn array_loop(
  src :: Str,
  p :: Int,
  acc :: List[Json]
) -> Result[ParseStep, ParseErr] {
  match parse_value(src, p) {
    Err(e1)   => Err(e1),
    Ok(step) => {
      let acc2 := list.concat(acc, [step.value])
      let p1 := skip_ws(src, step.pos)
      match peek_char(src, p1) {
        "]" => Ok(mk_step(p1 + 1, JList(acc2))),
        "," => array_loop(src, skip_ws(src, p1 + 1), acc2),
        _   => Err(mk_err(p1, "expected `,` or `]`")),
      }
    },
  }
}

# ---- Objects ------------------------------------------------------

fn parse_object(src :: Str, p :: Int) -> Result[ParseStep, ParseErr] {
  if char_at(src, p) != "{" {
    Err(mk_err(p, "expected `{`"))
  } else {
    let p1 := skip_ws(src, p + 1)
    if peek_char(src, p1) == "}" {
      Ok(mk_step(p1 + 1, JObj([])))
    } else {
      object_loop(src, p1, [])
    }
  }
}

fn object_loop(
  src :: Str,
  p :: Int,
  acc :: List[(Str, Json)]
) -> Result[ParseStep, ParseErr] {
  match parse_string_raw(src, p) {
    Err(e1) => Err(e1),
    Ok(key) => {
      let p1 := skip_ws(src, key.pos)
      if peek_char(src, p1) != ":" {
        Err(mk_err(p1, "expected `:` after object key"))
      } else {
        match parse_value(src, p1 + 1) {
          Err(e1)   => Err(e1),
          Ok(step) => {
            let acc2 := list.concat(acc, [(key.text, step.value)])
            let p2 := skip_ws(src, step.pos)
            match peek_char(src, p2) {
              "}" => Ok(mk_step(p2 + 1, JObj(acc2))),
              "," => object_loop(src, skip_ws(src, p2 + 1), acc2),
              _   => Err(mk_err(p2, "expected `,` or `}`")),
            }
          },
        }
      }
    },
  }
}

# ---- Character helpers --------------------------------------------

# Return the byte at position `p` as a single-char `Str`. Asserts
# `p < len`; callers must guard.
fn char_at(src :: Str, p :: Int) -> Str { str.slice(src, p, p + 1) }

# Like `char_at`, but past-the-end returns `""` instead of erroring.
# Lets dispatch sites use `match` directly on the result.
fn peek_char(src :: Str, p :: Int) -> Str {
  if p >= str.len(src) { "" } else { char_at(src, p) }
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
      None    => match pair { (k, v) => if k == key { Some(v) } else { None } },
    }
  })
}

# ---- Type coercion at the ADT level -------------------------------
#
# Each `as_xxx` returns `Option[T]`: `Some(v)` if the variant is the
# expected one, `None` otherwise. The caller decides whether absence
# is an error (use `j_str` etc. for the error-emitting versions).

fn as_str(j :: Json)   -> Option[Str]   { match j { JStr(s)   => Some(s),   _ => None } }
fn as_int(j :: Json)   -> Option[Int]   { match j { JInt(n)   => Some(n),   _ => None } }
fn as_float(j :: Json) -> Option[Float] {
  match j {
    JFloat(x) => Some(x),
    JInt(n)   => Some(int.to_float(n)),  # JSON numbers are floats
    _ => None,
  }
}
fn as_bool(j :: Json)  -> Option[Bool]  { match j { JBool(b)  => Some(b),   _ => None } }
fn as_list(j :: Json)  -> Option[List[Json]] { match j { JList(xs) => Some(xs), _ => None } }
fn as_obj(j :: Json)   -> Option[List[(Str, Json)]] { match j { JObj(xs) => Some(xs), _ => None } }
fn is_null(j :: Json)  -> Bool { match j { JNull => true, _ => false } }

# Pretty-printed variant tag — used in error messages.
fn type_name(j :: Json) -> Str {
  match j {
    JNull     => "null",
    JBool(_)  => "boolean",
    JInt(_)   => "integer",
    JFloat(_) => "number",
    JStr(_)   => "string",
    JList(_)  => "array",
    JObj(_)   => "object",
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

fn j_str(
  path_prefix :: Str,
  parent :: Json,
  field :: Str,
  checks :: List[c.StrCheck]
) -> Result[Str, List[e.Error]] {
  let p := join_path(path_prefix, field)
  match get_field(parent, field) {
    None    => Err(e.single(p, e.code_missing(), "field is required")),
    Some(j) => match as_str(j) {
      Some(s) => f.check_str(p, s, checks),
      None    => Err(e.single(p, e.code_type(),
        str.concat("expected string, got ", type_name(j)))),
    },
  }
}

fn j_int(
  path_prefix :: Str,
  parent :: Json,
  field :: Str,
  checks :: List[c.IntCheck]
) -> Result[Int, List[e.Error]] {
  let p := join_path(path_prefix, field)
  match get_field(parent, field) {
    None    => Err(e.single(p, e.code_missing(), "field is required")),
    Some(j) => match as_int(j) {
      Some(n) => f.check_int(p, n, checks),
      None    => Err(e.single(p, e.code_type(),
        str.concat("expected integer, got ", type_name(j)))),
    },
  }
}

fn j_float(
  path_prefix :: Str,
  parent :: Json,
  field :: Str,
  checks :: List[c.FloatCheck]
) -> Result[Float, List[e.Error]] {
  let p := join_path(path_prefix, field)
  match get_field(parent, field) {
    None    => Err(e.single(p, e.code_missing(), "field is required")),
    Some(j) => match as_float(j) {
      Some(x) => f.check_float(p, x, checks),
      None    => Err(e.single(p, e.code_type(),
        str.concat("expected number, got ", type_name(j)))),
    },
  }
}

fn j_bool(
  path_prefix :: Str,
  parent :: Json,
  field :: Str
) -> Result[Bool, List[e.Error]] {
  let p := join_path(path_prefix, field)
  match get_field(parent, field) {
    None    => Err(e.single(p, e.code_missing(), "field is required")),
    Some(j) => match as_bool(j) {
      Some(b) => Ok(b),
      None    => Err(e.single(p, e.code_type(),
        str.concat("expected boolean, got ", type_name(j)))),
    },
  }
}

fn j_obj(
  path_prefix :: Str,
  parent :: Json,
  field :: Str
) -> Result[Json, List[e.Error]] {
  let p := join_path(path_prefix, field)
  match get_field(parent, field) {
    None    => Err(e.single(p, e.code_missing(), "field is required")),
    Some(j) => match as_obj(j) {
      Some(_) => Ok(j),
      None    => Err(e.single(p, e.code_type(),
        str.concat("expected object, got ", type_name(j)))),
    },
  }
}

fn j_list(
  path_prefix :: Str,
  parent :: Json,
  field :: Str
) -> Result[List[Json], List[e.Error]] {
  let p := join_path(path_prefix, field)
  match get_field(parent, field) {
    None    => Err(e.single(p, e.code_missing(), "field is required")),
    Some(j) => match as_list(j) {
      Some(xs) => Ok(xs),
      None     => Err(e.single(p, e.code_type(),
        str.concat("expected array, got ", type_name(j)))),
    },
  }
}

# ---- Optional extractors ------------------------------------------

fn j_optional_str(
  path_prefix :: Str,
  parent :: Json,
  field :: Str,
  checks :: List[c.StrCheck]
) -> Result[Option[Str], List[e.Error]] {
  let p := join_path(path_prefix, field)
  match get_field(parent, field) {
    None    => Ok(None),
    Some(j) => if is_null(j) {
      Ok(None)
    } else {
      match as_str(j) {
        Some(s) => match f.check_str(p, s, checks) {
          Ok(v)   => Ok(Some(v)),
          Err(es) => Err(es),
        },
        None    => Err(e.single(p, e.code_type(),
          str.concat("expected string or null, got ", type_name(j)))),
      }
    },
  }
}

fn j_optional_int(
  path_prefix :: Str,
  parent :: Json,
  field :: Str,
  checks :: List[c.IntCheck]
) -> Result[Option[Int], List[e.Error]] {
  let p := join_path(path_prefix, field)
  match get_field(parent, field) {
    None    => Ok(None),
    Some(j) => if is_null(j) {
      Ok(None)
    } else {
      match as_int(j) {
        Some(n) => match f.check_int(p, n, checks) {
          Ok(v)   => Ok(Some(v)),
          Err(es) => Err(es),
        },
        None    => Err(e.single(p, e.code_type(),
          str.concat("expected integer or null, got ", type_name(j)))),
      }
    },
  }
}

# ---- Path joining -------------------------------------------------

fn join_path(prefix :: Str, leaf :: Str) -> Str {
  if str.is_empty(prefix) { leaf }
  else { str.concat(prefix, str.concat(".", leaf)) }
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
      None    => None,
      Some(j_inner) => get_field(j_inner, seg),
    }
  })
}

# Error-emitting variants — same shape as `j_str` / `j_int` but the
# field argument is a dotted path. The path appears verbatim in the
# error so a missing leaf surfaces as `user.address.zip: ...`.

fn j_str_at(
  j :: Json,
  path :: Str,
  checks :: List[c.StrCheck]
) -> Result[Str, List[e.Error]] {
  match get_path(j, path) {
    None    => Err(e.single(path, e.code_missing(), "field is required")),
    Some(v) => match as_str(v) {
      Some(s) => f.check_str(path, s, checks),
      None    => Err(e.single(path, e.code_type(),
        str.concat("expected string, got ", type_name(v)))),
    },
  }
}

fn j_int_at(
  j :: Json,
  path :: Str,
  checks :: List[c.IntCheck]
) -> Result[Int, List[e.Error]] {
  match get_path(j, path) {
    None    => Err(e.single(path, e.code_missing(), "field is required")),
    Some(v) => match as_int(v) {
      Some(n) => f.check_int(path, n, checks),
      None    => Err(e.single(path, e.code_type(),
        str.concat("expected integer, got ", type_name(v)))),
    },
  }
}

fn j_optional_str_at(
  j :: Json,
  path :: Str,
  checks :: List[c.StrCheck]
) -> Result[Option[Str], List[e.Error]] {
  match get_path(j, path) {
    None    => Ok(None),
    Some(v) => if is_null(v) {
      Ok(None)
    } else {
      match as_str(v) {
        Some(s) => match f.check_str(path, s, checks) {
          Ok(s2)  => Ok(Some(s2)),
          Err(es) => Err(es),
        },
        None    => Err(e.single(path, e.code_type(),
          str.concat("expected string or null, got ", type_name(v)))),
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
    JNull     => "null",
    JBool(b)  => if b { "true" } else { "false" },
    JInt(n)   => int.to_str(n),
    JFloat(x) => float.to_str(x),
    JStr(s)   => str.concat("\"", str.concat(escape_str(s), "\"")),
    JList(xs) => {
      let parts := list.map(xs, fn (item :: Json) -> Str { stringify(item) })
      str.concat("[", str.concat(str.join(parts, ","), "]"))
    },
    JObj(es)  => {
      let parts := list.map(es, fn (pair :: (Str, Json)) -> Str {
        match pair { (k, v) => str.concat(
          str.concat("\"", str.concat(escape_str(k), "\":")),
          stringify(v))
        }
      })
      str.concat("{", str.concat(str.join(parts, ","), "}"))
    },
  }
}

# Two-space indented variant. Top-level value gets no leading
# whitespace; nested objects/arrays are indented.
fn stringify_pretty(j :: Json) -> Str { stringify_at(j, 0) }

fn stringify_at(j :: Json, depth :: Int) -> Str {
  match j {
    JNull     => "null",
    JBool(b)  => if b { "true" } else { "false" },
    JInt(n)   => int.to_str(n),
    JFloat(x) => float.to_str(x),
    JStr(s)   => str.concat("\"", str.concat(escape_str(s), "\"")),
    JList(xs) => if list.is_empty(xs) {
      "[]"
    } else {
      let inner_indent := indent_str(depth + 1)
      let close_indent := indent_str(depth)
      let parts := list.map(xs, fn (item :: Json) -> Str {
        str.concat(inner_indent, stringify_at(item, depth + 1))
      })
      str.concat("[\n", str.concat(str.join(parts, ",\n"),
        str.concat("\n", str.concat(close_indent, "]"))))
    },
    JObj(es) => if list.is_empty(es) {
      "{}"
    } else {
      let inner_indent := indent_str(depth + 1)
      let close_indent := indent_str(depth)
      let parts := list.map(es, fn (pair :: (Str, Json)) -> Str {
        match pair { (k, v) =>
          str.concat(inner_indent,
            str.concat("\"",
              str.concat(escape_str(k),
                str.concat("\": ", stringify_at(v, depth + 1)))))
        }
      })
      str.concat("{\n", str.concat(str.join(parts, ",\n"),
        str.concat("\n", str.concat(close_indent, "}"))))
    },
  }
}

# Escape a Str for embedding inside JSON quotes. We escape the
# characters that the parser also knows how to round-trip: `"`,
# `\`, `\n`, `\r`, `\t`. The pair is exact: any output of
# `stringify` parses back via `parse`.
fn escape_str(s :: Str) -> Str {
  let chars := str.split(s, "")
  list.fold(chars, "", fn (acc :: Str, c :: Str) -> Str {
    str.concat(acc, escape_char(c))
  })
}

fn escape_char(c :: Str) -> Str {
  match c {
    "\""  => "\\\"",
    "\\"  => "\\\\",
    "\n"  => "\\n",
    "\r"  => "\\r",
    "\t"  => "\\t",
    _     => c,
  }
}

fn indent_str(depth :: Int) -> Str {
  if depth <= 0 { "" }
  else { str.concat("  ", indent_str(depth - 1)) }
}
