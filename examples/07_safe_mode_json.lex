# lex-schema — safe-mode JSON validation
#
# Same shape as `01_user_signup.lex`, but built on the `json_value`
# module's `Json` ADT rather than `std.json.parse_strict`. The
# resulting validator is **totally safe**: a payload like
# `{"age": "thirty"}` produces a clean `type` error at
# `age`, not a VM crash, because the parser tags every value
# with its actual JSON type up front.
#
# Trade-off: the parser is O(input length²) in the worst case
# (slice-based, no buffer reuse). For HTTP request bodies of a
# few hundred kilobytes that's fine; for multi-megabyte payloads,
# use the regular `from_json` path until upstream lex-lang#322
# adds deep type validation to `json.parse_strict`.
#
# Run:
#   lex run examples/07_safe_mode_json.lex validate_good
#   lex run examples/07_safe_mode_json.lex validate_type_wrong
#   lex run examples/07_safe_mode_json.lex validate_missing
#   lex run examples/07_safe_mode_json.lex validate_garbage

import "../src/error" as e

import "../src/constraints" as c

import "../src/combine" as cm

import "../src/json_value" as jv

type User = { email :: Str, username :: Str, age :: Int }

fn mk_user(em :: Str, un :: Str, ag :: Int) -> User {
  { email: em, username: un, age: ag }
}

# Validate against the Json ADT — every step is total.
fn validate_user(j :: jv.Json) -> Result[User, e.Errors] {
  cm.combine3(jv.j_str("", j, "email", [StrEmail]), jv.j_str("", j, "username", [StrMinLen(3), StrMaxLen(32), StrPattern("^[a-zA-Z0-9_]+$")]), jv.j_int("", j, "age", [IntInRange(13, 130)]), mk_user)
}

fn parse_user(body :: Str) -> Result[User, e.Errors] {
  cm.and_then(jv.parse_into_errors(body), fn (j :: jv.Json) -> Result[User, e.Errors] {
    validate_user(j)
  })
}

# ---- Demos ---------------------------------------------------------
fn validate_good() -> Result[User, e.Errors] {
  parse_user("{\"email\":\"alice@example.com\",\"username\":\"alice_42\",\"age\":29}")
}

# The trust-model demo: `age` arrives as a string. With the regular
# `parse_strict` path this produces a runtime crash the first time
# downstream code does `user.age + 1`. With the Json ADT path it
# surfaces as a precise typed error.
fn validate_type_wrong() -> Result[User, e.Errors] {
  parse_user("{\"email\":\"alice@example.com\",\"username\":\"alice_42\",\"age\":\"thirty\"}")
}

fn validate_missing() -> Result[User, e.Errors] {
  parse_user("{\"email\":\"alice@example.com\",\"username\":\"alice_42\"}")
}

fn validate_garbage() -> Result[User, e.Errors] {
  parse_user("not valid json at all")
}

fn format_type_wrong() -> Str {
  match validate_type_wrong() {
    Ok(_) => "no errors",
    Err(es) => e.format(es),
  }
}

fn format_missing() -> Str {
  match validate_missing() {
    Ok(_) => "no errors",
    Err(es) => e.format(es),
  }
}

fn format_garbage() -> Str {
  match validate_garbage() {
    Ok(_) => "no errors",
    Err(es) => e.format(es),
  }
}

