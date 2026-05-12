# lex-pydantic — type coercion
#
# Pydantic v1-style "lax" parsing for fields that arrive as a string
# but should be a richer type downstream. Most useful at trust
# boundaries where every value is text (query strings, form posts,
# CSV columns, environment variables, CLI args).
#
# Each `coerce_xxx` is paired with a `check_str_as_xxx` that runs
# the coercion *and* a typed-constraint list in one call —
# preserving lex-pydantic's "every check returns Result[T, Errors]"
# regularity so callers can drop them straight into `combineN`.
#
# Coercion failures use `code = "type"`; downstream constraint
# failures use the regular per-constraint codes (`min`, `pattern`,
# ...) — so error consumers can distinguish "the input was the
# wrong shape" from "the input was a number but out of range."

import "std.str"   as str
import "std.int"   as int
import "std.float" as float
import "std.list"  as list

import "./constraints" as c
import "./error"       as e
import "./field"       as f

# ---- str → int ----------------------------------------------------

fn coerce_str_to_int(path :: Str, s :: Str) -> Result[Int, e.Errors] {
  match str.to_int(str.trim(s)) {
    Some(n) => Ok(n),
    None    => Err(e.single(path, e.code_type(),
      str.concat("expected integer, got ", quote(s)))),
  }
}

fn check_str_as_int(
  path :: Str,
  s :: Str,
  checks :: List[c.IntCheck]
) -> Result[Int, e.Errors] {
  match coerce_str_to_int(path, s) {
    Err(es) => Err(es),
    Ok(n)   => f.check_int(path, n, checks),
  }
}

# ---- str → float --------------------------------------------------

fn coerce_str_to_float(path :: Str, s :: Str) -> Result[Float, e.Errors] {
  match str.to_float(str.trim(s)) {
    Some(x) => Ok(x),
    None    => Err(e.single(path, e.code_type(),
      str.concat("expected number, got ", quote(s)))),
  }
}

fn check_str_as_float(
  path :: Str,
  s :: Str,
  checks :: List[c.FloatCheck]
) -> Result[Float, e.Errors] {
  match coerce_str_to_float(path, s) {
    Err(es) => Err(es),
    Ok(x)   => f.check_float(path, x, checks),
  }
}

# ---- str → bool ---------------------------------------------------
#
# Accepts the same surface as pydantic v1 / urllib.parse: `true`,
# `false`, `1`, `0`, `yes`, `no`, `on`, `off`. Case-insensitive.
# Anything else is a coercion failure.

fn coerce_str_to_bool(path :: Str, s :: Str) -> Result[Bool, e.Errors] {
  let normalized := str.to_lower(str.trim(s))
  if is_truthy_word(normalized) {
    Ok(true)
  } else {
    if is_falsy_word(normalized) {
      Ok(false)
    } else {
      Err(e.single(path, e.code_type(),
        str.concat("expected boolean, got ", quote(s))))
    }
  }
}

fn is_truthy_word(s :: Str) -> Bool {
  match s {
    "true" => true,
    "1"    => true,
    "yes"  => true,
    "on"   => true,
    "y"    => true,
    "t"    => true,
    _      => false,
  }
}

fn is_falsy_word(s :: Str) -> Bool {
  match s {
    "false" => true,
    "0"     => true,
    "no"    => true,
    "off"   => true,
    "n"     => true,
    "f"     => true,
    _       => false,
  }
}

# ---- map.get → Option, coerced -----------------------------------
#
# Pulls a value out of a `Map[Str, Str]` (the natural shape of a
# query string or form body), then runs the typed validator. Absent
# keys are reported as `code = "missing"`; bad coercion as
# `code = "type"`; constraint failures with their per-rule codes.

import "std.map" as map

fn require_int_from_map(
  src :: Map[Str, Str],
  key :: Str,
  checks :: List[c.IntCheck]
) -> Result[Int, e.Errors] {
  match map.get(src, key) {
    None    => Err(e.single(key, e.code_missing(), "field is required")),
    Some(s) => check_str_as_int(key, s, checks),
  }
}

fn require_float_from_map(
  src :: Map[Str, Str],
  key :: Str,
  checks :: List[c.FloatCheck]
) -> Result[Float, e.Errors] {
  match map.get(src, key) {
    None    => Err(e.single(key, e.code_missing(), "field is required")),
    Some(s) => check_str_as_float(key, s, checks),
  }
}

fn require_bool_from_map(
  src :: Map[Str, Str],
  key :: Str
) -> Result[Bool, e.Errors] {
  match map.get(src, key) {
    None    => Err(e.single(key, e.code_missing(), "field is required")),
    Some(s) => coerce_str_to_bool(key, s),
  }
}

fn require_str_from_map(
  src :: Map[Str, Str],
  key :: Str,
  checks :: List[c.StrCheck]
) -> Result[Str, e.Errors] {
  match map.get(src, key) {
    None    => Err(e.single(key, e.code_missing(), "field is required")),
    Some(s) => f.check_str(key, s, checks),
  }
}

# Optional variants — `None` is Ok, present + bad-shape is Err.

fn optional_int_from_map(
  src :: Map[Str, Str],
  key :: Str,
  checks :: List[c.IntCheck]
) -> Result[Option[Int], e.Errors] {
  match map.get(src, key) {
    None    => Ok(None),
    Some(s) => match check_str_as_int(key, s, checks) {
      Ok(n)   => Ok(Some(n)),
      Err(es) => Err(es),
    },
  }
}

fn optional_str_from_map(
  src :: Map[Str, Str],
  key :: Str,
  checks :: List[c.StrCheck]
) -> Result[Option[Str], e.Errors] {
  match map.get(src, key) {
    None    => Ok(None),
    Some(s) => match f.check_str(key, s, checks) {
      Ok(v)   => Ok(Some(v)),
      Err(es) => Err(es),
    },
  }
}

# ---- Internal helpers --------------------------------------------

fn quote(s :: Str) -> Str {
  str.concat("\"", str.concat(s, "\""))
}
