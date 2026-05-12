# lex-schema — SDK code generation
#
# A `User` schema generates three artifacts off one source of
# truth:
#   1. JSON Schema (Draft 2020-12) for browser-side validation
#   2. TypeScript interfaces for frontend type-checking
#   3. Pydantic v2 BaseModel for Python services
#
# Run any of:
#   lex run examples/15_sdk_export.lex demo_typescript
#   lex run examples/15_sdk_export.lex demo_python
#   lex run examples/15_sdk_export.lex demo_json_schema

import "../src/constraints" as c
import "../src/json_value"  as jv
import "../src/schema"      as s
import "../src/sdk"         as sdk

# ---- The single source of truth ----------------------------------

fn address_schema() -> s.ModelSchema {
  {
    title: "Address",
    description: "Postal address",
    fields: [
      s.required_str("street",  [StrMinLen(1), StrMaxLen(120)]),
      s.required_str("city",    [StrMinLen(1), StrMaxLen(80)]),
      s.required_str("zip",     [StrPattern("^[0-9]{5}$")]),
      s.required_str("country", [StrPattern("^[A-Z]{2}$")]),
    ],
  }
}

fn user_schema() -> s.ModelSchema {
  {
    title:       "User",
    description: "A registered user",
    fields: [
      s.required_str("name",  [StrMinLen(1), StrMaxLen(80)]),
      s.required_str("email", [StrEmail]),
      s.required_int("age",   [IntInRange(13, 130)]),
      s.required_str("plan",  [StrOneOf(["free", "pro", "enterprise"])]),
      s.optional(s.required_str("nickname", [StrMaxLen(40)])),
      s.required_object("address", address_schema()),
    ],
  }
}

# ---- Demos --------------------------------------------------------

fn demo_typescript() -> Str { sdk.to_typescript(user_schema()) }

fn demo_python() -> Str { sdk.to_python(user_schema()) }

fn demo_json_schema() -> Str {
  jv.stringify_pretty(s.to_json_schema(user_schema()))
}
