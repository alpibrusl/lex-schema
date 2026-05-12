# lex-pydantic — composable Validator value
#
# Bundles a `ModelSchema` with the pre-computed downstream
# artifacts so a caller passing the Validator around carries
# everything needed for both *runtime* validation and *build-time*
# codegen in one value. Replaces the "thread schema everywhere"
# style that's natural in pure-FP but verbose at large scale.
#
# Construction is eager — `make(schema)` runs every emitter once.
# Re-emitting on each call would be wasteful at the typical
# request-rate; if a caller mutates a schema and wants fresh
# artifacts they call `make` again.
#
# Effects: none.

import "std.list" as list

import "./error"      as e
import "./json_value" as jv
import "./schema"     as s
import "./sdk"        as sdk

type Validator = {
  schema      :: s.ModelSchema,
  json_schema :: jv.Json,
  openapi     :: jv.Json,
  typescript  :: Str,
  python      :: Str,
}

# Construct a Validator from a schema. All emitters run once;
# subsequent calls to `export_*` are O(1) record reads.
fn make(schema :: s.ModelSchema) -> Validator {
  {
    schema:      schema,
    json_schema: s.to_json_schema(schema),
    openapi:     s.to_openapi_schema(schema),
    typescript:  sdk.to_typescript(schema),
    python:      sdk.to_python(schema),
  }
}

# Validate a `Json` payload against the bundled schema.
fn validate(v :: Validator, payload :: jv.Json) -> Result[jv.Json, e.Errors] {
  s.validate(v.schema, payload)
}

# Validate a serialized JSON Str — parses + validates in one
# call. Outer parse errors carry `code = "parse"`; inner ones
# the regular per-field codes.
fn validate_str(v :: Validator, body :: Str) -> Result[jv.Json, e.Errors] {
  match jv.parse_into_errors(body) {
    Err(es) => Err(es),
    Ok(j)   => validate(v, j),
  }
}

# Export accessors. These exist so callers can pass a Validator
# around without importing `schema.lex` or `sdk.lex` themselves —
# the bundle is the only surface.
fn export_json_schema_str(v :: Validator) -> Str { jv.stringify_pretty(v.json_schema) }
fn export_openapi_str(v :: Validator)    -> Str { jv.stringify_pretty(v.openapi) }
fn export_typescript(v :: Validator)     -> Str { v.typescript }
fn export_python(v :: Validator)         -> Str { v.python }

# A compact "what's in this Validator" descriptor — useful for
# `/v1/schemas` directory listings and for asserting in tests.
fn summary(v :: Validator) -> Str {
  let title := v.schema.title
  let n := list.len(v.schema.fields)
  let head := str_concat("Validator{title=\"", str_concat(title, "\""))
  str_concat(head, str_concat(", fields=", str_concat(int_to_str(n), "}")))
}

# Small local helpers — we don't want this module to depend on
# every `std.*` import its consumers do.
import "std.str" as str
import "std.int" as int

fn str_concat(a :: Str, b :: Str) -> Str { str.concat(a, b) }
fn int_to_str(n :: Int) -> Str { int.to_str(n) }
