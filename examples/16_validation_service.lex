# lex-schema — `/v1/validate` HTTP service
#
# A small REST endpoint that takes a JSON Schema + a JSON payload
# over the wire and runs the payload through the schema. Returns
# 200 + the validated normalized payload on success, 422 + a
# structured `Errors` list on failure (mirroring pydantic's HTTP
# response shape).
#
# This is the universal validation primitive: any service that
# already speaks HTTP can outsource its schema validation here,
# carrying its own constraints in the request rather than having
# them baked into the validator.
#
# Run:
#   lex run --allow-effects net examples/16_validation_service.lex main
#
# Test:
#   curl -sX POST http://127.0.0.1:8200/v1/validate \
#     -H 'content-type: application/json' \
#     -d '{
#       "schema": {
#         "title": "User",
#         "type": "object",
#         "properties": {
#           "name":  {"type":"string","minLength":1,"maxLength":80},
#           "email": {"type":"string","format":"email"},
#           "age":   {"type":"integer","minimum":13,"maximum":130}
#         },
#         "required": ["name","email","age"]
#       },
#       "payload": {"name":"Alice","email":"alice@example.com","age":29}
#     }'
#   # → 200 {"ok":true,"value":{...}}
#
#   curl -sX POST http://127.0.0.1:8200/v1/validate \
#     -H 'content-type: application/json' \
#     -d '{"schema":<as above>,"payload":{"name":"","email":"nope","age":7}}'
#   # → 422 {"ok":false,"errors":[{path,code,message}, ...]}
#
# Effects: [net] only.

import "std.net" as net

import "std.str" as str

import "std.list" as list

import "../src/error" as e

import "../src/json_value" as jv

import "../src/schema" as s

import "../src/schema_import" as si

type Request = { body :: Str, method :: Str, path :: Str, query :: Str }

type Response = { body :: Str, status :: Int }

# ---- Validation pipeline ------------------------------------------
# Parse the request envelope `{schema: ..., payload: ...}`, decode
# the schema into a ModelSchema, run the payload through it,
# return a (status, body) pair.
fn validate_request(body :: Str) -> (Int, Str) {
  match jv.parse(body) {
    Err(p) => (400, error_body_many(e.single("", e.code_parse(), str.concat(p.message, str.concat(" at byte ", int_to_str(p.pos)))))),
    Ok(envelope) => match jv.get_field(envelope, "schema") {
      None => (400, error_body_many(e.single("schema", e.code_missing(), "request must carry a `schema` field"))),
      Some(schema_json) => match si.from_json_schema(schema_json) {
        Err(es) => (400, error_body_many(es)),
        Ok(schema) => match jv.get_field(envelope, "payload") {
          None => (400, error_body_many(e.single("payload", e.code_missing(), "request must carry a `payload` field"))),
          Some(payload) => match s.validate(schema, payload) {
            Ok(v) => (200, success_body(v)),
            Err(es) => (422, error_body_many(es)),
          },
        },
      },
    },
  }
}

# ---- Response shapes ----------------------------------------------
fn success_body(value :: jv.Json) -> Str {
  str.concat("{\"ok\":true,\"value\":", str.concat(jv.stringify(value), "}"))
}

fn error_body_many(errs :: e.Errors) -> Str {
  let items := list.map(errs, fn (er :: e.Error) -> Str {
    error_to_json(er)
  })
  str.concat("{\"ok\":false,\"errors\":[", str.concat(str.join(items, ","), "]}"))
}

fn error_to_json(err :: e.Error) -> Str {
  let obj := JObj([("path", JStr(err.path)), ("code", JStr(err.code)), ("message", JStr(err.message))])
  jv.stringify(obj)
}

# ---- HTTP handler -------------------------------------------------
fn handle(req :: Request) -> Response {
  match req.method {
    "POST" => match req.path {
      "/v1/validate" => {
        let result := validate_request(req.body)
        let status := match result {
          (s, _) => s,
        }
        let body := match result {
          (_, b) => b,
        }
        { status: status, body: body }
      },
      _ => { status: 404, body: "{\"ok\":false,\"errors\":[{\"path\":\"\",\"code\":\"not_found\",\"message\":\"route not found\"}]}" },
    },
    "GET" => match req.path {
      "/health" => { status: 200, body: "{\"ok\":true}" },
      _ => { status: 404, body: "{\"ok\":false,\"errors\":[{\"path\":\"\",\"code\":\"not_found\",\"message\":\"route not found\"}]}" },
    },
    _ => { status: 405, body: "{\"ok\":false,\"errors\":[{\"path\":\"\",\"code\":\"method_not_allowed\",\"message\":\"only POST is supported\"}]}" },
  }
}

fn main() -> [net] Nil {
  net.serve(8200, "handle")
}

# ---- Smoke-test entrypoints (callable from `lex run`) --------------
# Useful for asserting the pipeline without spinning up the server.
fn smoke_good() -> (Int, Str) {
  validate_request("{\"schema\":{\"type\":\"object\",\"properties\":{\"name\":{\"type\":\"string\",\"minLength\":1}},\"required\":[\"name\"]},\"payload\":{\"name\":\"alice\"}}")
}

fn smoke_bad() -> (Int, Str) {
  validate_request("{\"schema\":{\"type\":\"object\",\"properties\":{\"age\":{\"type\":\"integer\",\"minimum\":0}},\"required\":[\"age\"]},\"payload\":{\"age\":-5}}")
}

# Tiny inline helper because we import str/list but not int. Keeps
# the module-import surface tight.
import "std.int" as int

fn int_to_str(n :: Int) -> Str {
  int.to_str(n)
}

