# lex-pydantic — basic signup validation
#
# Mirrors the canonical pydantic example: validate a signup form
# carried as a JSON body, return either a typed `User` record or
# the full set of field-level errors.
#
# Run:
#   lex run examples/01_user_signup.lex validate_good
#   lex run examples/01_user_signup.lex validate_bad
#
# The bad case demonstrates per-field error accumulation: all four
# failures come back in one list, not one-at-a-time.

import "../src/error"       as e
import "../src/constraints" as c
import "../src/field"       as f
import "../src/combine"     as cm
import "../src/parse"       as p

# ---- Target type --------------------------------------------------
# The shape your code wants to *consume* downstream. lex-pydantic
# never invents this for you; you write the Lex type and it stays
# the single source of truth.

type User = {
  email :: Str,
  username :: Str,
  age :: Int,
  password :: Str,
}

# Pure constructor — useful as the final builder in combine4.
fn build_user(em :: Str, un :: Str, ag :: Int, pw :: Str) -> User {
  { email: em, username: un, age: ag, password: pw }
}

# ---- The validator ------------------------------------------------
# `raw` is the shape exactly as the JSON arrived. The library's job
# is to turn `raw` into a `User`, accumulating every constraint
# failure along the way.

type RawUser = {
  email :: Str,
  username :: Str,
  age :: Int,
  password :: Str,
}

fn validate(raw :: RawUser) -> Result[User, List[e.Error]] {
  cm.combine4(
    f.check_str("email",    raw.email,    [StrEmail]),
    f.check_str("username", raw.username, [StrMinLen(3), StrMaxLen(32),
                                           StrPattern("^[a-zA-Z0-9_]+$")]),
    f.check_int("age",      raw.age,      [IntInRange(13, 130)]),
    f.check_str("password", raw.password, [StrMinLen(8), StrMaxLen(128),
                                           StrPattern(".*[0-9].*")]),
    build_user
  )
}

# ---- End-to-end: parse JSON, then validate ------------------------

fn parse_and_validate(input :: Str) -> Result[User, List[e.Error]] {
  cm.and_then(
    p.from_json(input, ["email", "username", "age", "password"]),
    fn (raw :: RawUser) -> Result[User, List[e.Error]] { validate(raw) }
  )
}

# ---- Demo entrypoints (callable from `lex run`) -------------------

fn validate_good() -> Result[User, List[e.Error]] {
  parse_and_validate(
    "{\"email\":\"alice@example.com\",\"username\":\"alice_42\",\"age\":29,\"password\":\"correcthorse9\"}"
  )
}

fn validate_bad() -> Result[User, List[e.Error]] {
  # All four fields are wrong: invalid email, username too short and
  # has a `!`, age below minimum, password too short and no digit.
  parse_and_validate(
    "{\"email\":\"not-an-email\",\"username\":\"a!\",\"age\":7,\"password\":\"weak\"}"
  )
}

fn format_demo() -> Str {
  match validate_bad() {
    Ok(_)    => "no errors",
    Err(es)  => e.format(es),
  }
}
