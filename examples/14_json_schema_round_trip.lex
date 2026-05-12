# lex-pydantic — JSON Schema round-trip
#
# Start with a ModelSchema, emit JSON Schema, parse the JSON
# back into a ModelSchema, and validate the same payload against
# both. The round-trip is the acceptance test for `schema_import`:
# the constraint catalog we emit must be the constraint catalog
# we read.
#
# Run:
#   lex run examples/14_json_schema_round_trip.lex demo_roundtrip
#   lex run examples/14_json_schema_round_trip.lex demo_external_schema

import "../src/error"         as e
import "../src/constraints"   as c
import "../src/json_value"    as jv
import "../src/schema"        as s
import "../src/schema_import" as si

# ---- Local schema --------------------------------------------------

fn original() -> s.ModelSchema {
  {
    title: "User", description: "",
    fields: [
      s.required_str("name",  [StrMinLen(1), StrMaxLen(80)]),
      s.required_str("email", [StrEmail]),
      s.required_int("age",   [IntInRange(13, 130)]),
    ],
  }
}

# Round-trip: original → JSON Schema → text → JSON Schema (parsed) →
# imported ModelSchema. Compare validation outcomes on the same
# payload from each side.
fn demo_roundtrip() -> Result[Str, List[e.Error]] {
  let s_text := jv.stringify(s.to_json_schema(original()))
  match si.from_str(s_text) {
    Err(es)       => Err(es),
    Ok(imported)  => match jv.parse_into_errors(
      "{\"name\":\"Alice\",\"email\":\"alice@example.com\",\"age\":29}"
    ) {
      Err(es) => Err(es),
      Ok(payload) => match s.validate(imported, payload) {
        Err(es) => Err(es),
        Ok(_)   => Ok("imported schema validates the original payload"),
      },
    },
  }
}

# Take an externally-authored JSON Schema document and validate
# data against it. Demonstrates the "use schemas you didn't write"
# path.
fn demo_external_schema() -> Result[Str, List[e.Error]] {
  let external_schema_text := "
    {
      \"$schema\": \"https://json-schema.org/draft/2020-12/schema\",
      \"title\": \"Product\",
      \"type\": \"object\",
      \"properties\": {
        \"sku\":   { \"type\": \"string\", \"pattern\": \"^[A-Z]{3}-[0-9]{4}$\" },
        \"price\": { \"type\": \"integer\", \"minimum\": 0, \"maximum\": 1000000 }
      },
      \"required\": [\"sku\", \"price\"]
    }
  "
  match si.from_str(external_schema_text) {
    Err(es)     => Err(es),
    Ok(schema)  => match jv.parse_into_errors(
      "{\"sku\":\"ABC-1234\",\"price\":2500}"
    ) {
      Err(es) => Err(es),
      Ok(payload) => match s.validate(schema, payload) {
        Err(es) => Err(es),
        Ok(_)   => Ok("external schema accepts our payload"),
      },
    },
  }
}
