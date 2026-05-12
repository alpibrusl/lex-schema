# lex-schema — nested records
#
# A user with a nested address. The library composes naturally:
# write a validator for the inner record, then call it from the
# outer one with `with_path("address", ...)` so leaf errors come
# back as `address.zip`, `address.country`, etc.
#
# Run:
#   lex run examples/02_nested.lex validate_good
#   lex run examples/02_nested.lex validate_bad

import "../src/error"       as e
import "../src/constraints" as c
import "../src/field"       as f
import "../src/combine"     as cm
import "../src/parse"       as p

# ---- Types --------------------------------------------------------

type Address = {
  street :: Str,
  city :: Str,
  zip :: Str,
  country :: Str,
}

type User = {
  name :: Str,
  email :: Str,
  address :: Address,
}

type RawAddress = {
  street :: Str,
  city :: Str,
  zip :: Str,
  country :: Str,
}

type RawUser = {
  name :: Str,
  email :: Str,
  address :: RawAddress,
}

# ---- Builders -----------------------------------------------------

fn mk_address(st :: Str, ci :: Str, zp :: Str, co :: Str) -> Address {
  { street: st, city: ci, zip: zp, country: co }
}

fn mk_user(nm :: Str, em :: Str, ad :: Address) -> User {
  { name: nm, email: em, address: ad }
}

# ---- Inner-record validator ---------------------------------------

# 2-letter ISO 3166-1 alpha-2 country code, uppercase.
fn country_pattern() -> Str { "^[A-Z]{2}$" }

# US-style 5-digit zip; loosen for international addresses by
# swapping the constraint at the call site.
fn zip_pattern() -> Str { "^[0-9]{5}$" }

fn validate_address(raw :: RawAddress) -> Result[Address, e.Errors] {
  cm.combine4(
    f.check_str("street",  raw.street,  [StrMinLen(1), StrMaxLen(120)]),
    f.check_str("city",    raw.city,    [StrMinLen(1), StrMaxLen(80)]),
    f.check_str("zip",     raw.zip,     [StrPattern(zip_pattern())]),
    f.check_str("country", raw.country, [StrPattern(country_pattern())]),
    mk_address
  )
}

# ---- Outer validator ----------------------------------------------

fn validate_user(raw :: RawUser) -> Result[User, e.Errors] {
  cm.combine3(
    f.check_str("name",  raw.name,  [StrMinLen(1), StrMaxLen(80)]),
    f.check_str("email", raw.email, [StrEmail]),
    cm.with_path("address", validate_address(raw.address)),
    mk_user
  )
}

# ---- End-to-end ---------------------------------------------------

fn parse_user(input :: Str) -> Result[User, e.Errors] {
  cm.and_then(
    p.from_json(input, ["name", "email", "address"]),
    fn (raw :: RawUser) -> Result[User, e.Errors] { validate_user(raw) }
  )
}

# ---- Demo entrypoints ---------------------------------------------

fn validate_good() -> Result[User, e.Errors] {
  parse_user(
    "{\"name\":\"Alice\",\"email\":\"alice@example.com\",\"address\":{\"street\":\"1 Market St\",\"city\":\"SF\",\"zip\":\"94103\",\"country\":\"US\"}}"
  )
}

fn validate_bad() -> Result[User, e.Errors] {
  # Bad email + bad zip + bad country code.
  parse_user(
    "{\"name\":\"Bob\",\"email\":\"nope\",\"address\":{\"street\":\"\",\"city\":\"\",\"zip\":\"abc\",\"country\":\"USA\"}}"
  )
}

fn format_demo() -> Str {
  match validate_bad() {
    Ok(_)    => "no errors",
    Err(es)  => e.format(es),
  }
}
