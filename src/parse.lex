# lex-schema — JSON / TOML / YAML entry points
#
# Thin wrappers around `std.json.parse_strict` (and TOML/YAML
# variants) that surface the outer-shell parse failure as a
# `pydantic.Errors` list instead of a raw `Str`. Pairing them with
# the field-level validators in `field.lex` and the combinators in
# `combine.lex` gives a single Result-shaped pipeline from "untrusted
# input string" to "validated record".
#
# The generic argument T is the user's target record type. The
# returned `raw` value is structurally that type; the library can't
# itself validate constraints on it — that's what the field
# validators are for.
#
# Effects: none (the underlying parse builtins are pure).

import "std.json" as json
import "std.toml" as toml
import "std.yaml" as yaml

import "./error" as e

# Parse a JSON string and check that the listed top-level fields are
# present. Returns the parsed record (typed `T` by the caller) or an
# Errors list with a single entry under code "parse" at the root path.
#
# Pass `required = []` to skip the field-presence check entirely —
# behaves like plain `json.parse`.
fn from_json[T](source :: Str, required :: List[Str]) -> Result[T, e.Errors] {
  match json.parse_strict(source, required) {
    Ok(v)  => Ok(v),
    Err(m) => Err(e.single("", e.code_parse(), m)),
  }
}

# TOML mirror. The same caveats apply: typed `T` is whatever Lex
# infers from the call site; field-level validation belongs in
# downstream combinators.
fn from_toml[T](source :: Str, required :: List[Str]) -> Result[T, e.Errors] {
  match toml.parse_strict(source, required) {
    Ok(v)  => Ok(v),
    Err(m) => Err(e.single("", e.code_parse(), m)),
  }
}

# YAML mirror.
fn from_yaml[T](source :: Str, required :: List[Str]) -> Result[T, e.Errors] {
  match yaml.parse_strict(source, required) {
    Ok(v)  => Ok(v),
    Err(m) => Err(e.single("", e.code_parse(), m)),
  }
}
