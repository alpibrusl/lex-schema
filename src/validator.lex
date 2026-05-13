# lex-schema — composable Validator value
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
  schema           :: s.ModelSchema,
  json_schema      :: jv.Json,
  openapi          :: jv.Json,
  openapi_response :: jv.Json,
  typescript       :: Str,
  python           :: Str,
}

# Construct a Validator from a schema. All emitters run once;
# subsequent calls to `export_*` are O(1) record reads.
fn make(schema :: s.ModelSchema) -> Validator {
  let openapi := s.to_openapi_schema(schema)
  {
    schema:           schema,
    json_schema:      s.to_json_schema(schema),
    openapi:          openapi,
    openapi_response: build_openapi_response(openapi),
    typescript:       sdk.to_typescript(schema),
    python:           sdk.to_python(schema),
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

# Validate `value` against the schema, then serialize to a compact
# JSON string. Extra fields are silently dropped — the schema acts
# as an allowlist. Returns `Err` if validation fails.
fn serialize(v :: Validator, value :: jv.Json) -> Result[Str, e.Errors] {
  match s.validate(v.schema, value) {
    Ok(j)   => Ok(jv.stringify(j)),
    Err(es) => Err(es),
  }
}

# Like `serialize` but also rejects any key in `value` that is not
# declared in the schema. Extra fields produce `Err` entries with
# `code = "extra_field"` before schema validation runs.
fn serialize_strict(v :: Validator, value :: jv.Json) -> Result[Str, e.Errors] {
  let field_names := list.map(v.schema.fields,
    fn (field :: s.Field) -> Str { field.name })
  let extra_errs := match jv.as_obj(value) {
    None          => [],
    Some(entries) => list.fold(entries, [],
      fn (acc :: e.Errors, pair :: (Str, jv.Json)) -> e.Errors {
        match pair {
          (key, _) => if is_known_field(field_names, key) { acc }
            else {
              list.concat(acc,
                e.single(key, e.code_extra(),
                  str_concat("unexpected extra field: ", key)))
            },
        }
      }),
  }
  if e.is_ok(extra_errs) {
    serialize(v, value)
  } else {
    Err(extra_errs)
  }
}

# Validate and serialize, silently dropping any extra fields.
# On a validation failure returns `"{}"` — use `serialize` when
# you need to surface errors.
fn serialize_lossy(v :: Validator, value :: jv.Json) -> Str {
  match s.validate(v.schema, value) {
    Ok(j)  => jv.stringify(j),
    Err(_) => "{}",
  }
}

# Export accessors. These exist so callers can pass a Validator
# around without importing `schema.lex` or `sdk.lex` themselves —
# the bundle is the only surface.
fn export_json_schema_str(v :: Validator) -> Str { jv.stringify_pretty(v.json_schema) }
fn export_openapi_str(v :: Validator)     -> Str { jv.stringify_pretty(v.openapi) }
fn export_typescript(v :: Validator)      -> Str { v.typescript }
fn export_python(v :: Validator)          -> Str { v.python }

# The `responses["200"]` OpenAPI fragment for this validator's schema.
# Drop it directly into a route's `responses` object — equivalent to
# FastAPI's `response_model=` driving the OpenAPI output.
fn openapi_response(v :: Validator) -> jv.Json { v.openapi_response }

# A compact "what's in this Validator" descriptor — useful for
# `/v1/schemas` directory listings and for asserting in tests.
fn summary(v :: Validator) -> Str {
  let title := v.schema.title
  let n := list.len(v.schema.fields)
  let head := str_concat("Validator{title=\"", str_concat(title, "\""))
  str_concat(head, str_concat(", fields=", str_concat(int_to_str(n), "}")))
}

# ---- Internal helpers ---------------------------------------------

# Wrap a `components/schemas` OpenAPI fragment in the standard
# `responses["200"]` envelope so lex-web can emit a complete
# `responses` block from a single Validator.
fn build_openapi_response(openapi_schema :: jv.Json) -> jv.Json {
  JObj([
    ("200", JObj([
      ("description", JStr("Successful response")),
      ("content", JObj([
        ("application/json", JObj([
          ("schema", openapi_schema)
        ]))
      ]))
    ]))
  ])
}

fn is_known_field(names :: List[Str], key :: Str) -> Bool
  examples {
    is_known_field(["name", "age"], "name") => true,
    is_known_field(["name", "age"], "role") => false,
    is_known_field([], "x") => false,
  }
{
  list.fold(names, false,
    fn (acc :: Bool, name :: Str) -> Bool { acc or (name == key) })
}

# Small local helpers — we don't want this module to depend on
# every `std.*` import its consumers do.
import "std.str" as str
import "std.int" as int

fn str_concat(a :: Str, b :: Str) -> Str
  examples {
    str_concat("foo", "bar") => "foobar",
    str_concat("", "x") => "x",
  }
{ str.concat(a, b) }

fn int_to_str(n :: Int) -> Str
  examples {
    int_to_str(0) => "0",
    int_to_str(42) => "42",
  }
{ int.to_str(n) }
