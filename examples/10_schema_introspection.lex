# lex-pydantic — schema-driven validation + OpenAPI export
#
# A `ModelSchema` is a value: a list of `Field` records, each
# carrying its constraints inline. From one schema you get three
# things at no extra cost:
#
#   1. Run-time validation: `s.validate(schema, j)` returns the
#      validated `Json` or a typed error list.
#   2. JSON Schema export for browser-side / contract testing.
#   3. OpenAPI 3.1 component-schema export for API docs / SDK
#      generation.
#
# Run:
#   lex run examples/10_schema_introspection.lex demo_validate
#   lex run examples/10_schema_introspection.lex demo_validate_bad
#   lex run examples/10_schema_introspection.lex demo_jsonschema
#   lex run examples/10_schema_introspection.lex demo_openapi

import "std.str"  as str
import "std.list" as list

import "../src/error"       as e
import "../src/constraints" as c
import "../src/combine"     as cm
import "../src/json_value"  as jv
import "../src/schema"      as s

# ---- Sub-schema: Address ------------------------------------------

fn address_schema() -> s.ModelSchema {
  {
    title:       "Address",
    description: "Postal address",
    fields: [
      s.required_str("street",  [StrMinLen(1), StrMaxLen(120)]),
      s.required_str("city",    [StrMinLen(1), StrMaxLen(80)]),
      s.required_str("zip",     [StrPattern("^[0-9]{5}$")]),
      s.required_str("country", [StrPattern("^[A-Z]{2}$")]),
    ],
  }
}

# ---- Top-level schema ---------------------------------------------

fn user_schema() -> s.ModelSchema {
  {
    title:       "User",
    description: "A registered user with billing address",
    fields: [
      s.required_str("name",     [StrMinLen(1), StrMaxLen(80)]),
      s.required_str("email",    [StrEmail]),
      s.required_int("age",      [IntInRange(13, 130)]),
      s.optional(s.required_str("nickname", [StrMaxLen(40)])),
      s.required_object("address", address_schema()),
      s.required_array("tags",
        KStr([StrMinLen(1), StrMaxLen(20)]),
        [ListMaxLen(10)]),
    ],
  }
}

# ---- Demos: validate ----------------------------------------------

fn parse_and_validate(body :: Str) -> Result[jv.Json, e.Errors] {
  cm.and_then(jv.parse_into_errors(body),
    fn (j :: jv.Json) -> Result[jv.Json, e.Errors] {
      s.validate(user_schema(), j)
    })
}

fn demo_validate() -> Result[jv.Json, e.Errors] {
  parse_and_validate(
    "{\"name\":\"Alice\",\"email\":\"alice@example.com\",\"age\":29,\"address\":{\"street\":\"1 Market St\",\"city\":\"SF\",\"zip\":\"94103\",\"country\":\"US\"},\"tags\":[\"vip\",\"beta\"]}"
  )
}

fn demo_validate_bad() -> Result[jv.Json, e.Errors] {
  # email bad, age 7, address.country lowercase, tags has an empty entry
  parse_and_validate(
    "{\"name\":\"Bob\",\"email\":\"nope\",\"age\":7,\"address\":{\"street\":\"x\",\"city\":\"SF\",\"zip\":\"94103\",\"country\":\"us\"},\"tags\":[\"vip\",\"\"]}"
  )
}

fn format_bad() -> Str {
  match demo_validate_bad() {
    Ok(_)   => "no errors",
    Err(es) => e.format(es),
  }
}

# ---- Demos: export ------------------------------------------------

fn demo_jsonschema() -> Str {
  jv.stringify_pretty(s.to_json_schema(user_schema()))
}

fn demo_openapi() -> Str {
  jv.stringify_pretty(s.to_openapi_schema(user_schema()))
}
