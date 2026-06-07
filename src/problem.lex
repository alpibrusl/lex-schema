# lex-schema — RFC 7807 problem+json renderer
#
# Renders an `Errors` list as a `application/problem+json` body
# per RFC 7807, the IETF-standard error envelope for HTTP APIs.
# Drop-in replacement for the hand-rolled `render_errors` shape
# that examples 04 / 16 ship today.
#
# Output shape:
#
#   {
#     "type":    "https://example.com/problems/validation",
#     "title":   "Validation failed",
#     "status":  422,
#     "detail":  "3 fields failed validation",
#     "instance": "/v1/signup",
#     "errors": [
#       {"path": "email",  "code": "email",   "message": "..."},
#       {"path": "age",    "code": "min",     "message": "..."}
#     ]
#   }
#
# `errors[]` is the standard pydantic-style extension (also used
# by FastAPI, Spring, .NET Problem Details, etc.) — RFC 7807
# explicitly allows extension members.
#
# Effects: none.

import "std.str" as str

import "std.int" as int

import "std.list" as list

import "./error" as e

import "./json_value" as jv

# ---- Problem-details record ---------------------------------------
type Problem = { type_uri :: Str, title :: Str, status :: Int, detail :: Str, instance :: Str, errors :: e.Errors }

# ---- Canonical preset ---------------------------------------------
#
# Most validation endpoints want the same shape: status 422,
# title "Validation failed", a default `type_uri` per project,
# and a `detail` synthesized from the error count.
fn validation_problem(type_uri :: Str, instance :: Str, errs :: e.Errors) -> Problem {
  { type_uri: type_uri, title: "Validation failed", status: 422, detail: detail_from_errors(errs), instance: instance, errors: errs }
}

fn detail_from_errors(errs :: e.Errors) -> Str {
  let n := list.len(errs)
  if n == 1 {
    "1 field failed validation"
  } else {
    str.concat(int.to_str(n), " fields failed validation")
  }
}

# ---- Other status codes -------------------------------------------
#
# RFC 7807 covers any HTTP error, not just validation. Helpers for
# the common ones make the call site read like the standard.
fn not_found(type_uri :: Str, instance :: Str, detail :: Str) -> Problem {
  { type_uri: type_uri, title: "Not Found", status: 404, detail: detail, instance: instance, errors: [] }
}

fn method_not_allowed(type_uri :: Str, instance :: Str, allowed :: Str) -> Problem {
  { type_uri: type_uri, title: "Method Not Allowed", status: 405, detail: str.concat("Allowed methods: ", allowed), instance: instance, errors: [] }
}

fn unauthorized(type_uri :: Str, instance :: Str, detail :: Str) -> Problem {
  { type_uri: type_uri, title: "Unauthorized", status: 401, detail: detail, instance: instance, errors: [] }
}

fn forbidden(type_uri :: Str, instance :: Str, detail :: Str) -> Problem {
  { type_uri: type_uri, title: "Forbidden", status: 403, detail: detail, instance: instance, errors: [] }
}

fn bad_request(type_uri :: Str, instance :: Str, detail :: Str) -> Problem {
  { type_uri: type_uri, title: "Bad Request", status: 400, detail: detail, instance: instance, errors: [] }
}

fn internal_server_error(type_uri :: Str, instance :: Str, detail :: Str) -> Problem {
  { type_uri: type_uri, title: "Internal Server Error", status: 500, detail: detail, instance: instance, errors: [] }
}

# ---- Serialization ------------------------------------------------
# Render as a `Json` value — the canonical form. Callers walking
# the value, embedding it in a larger response, or piping it through
# `jv.stringify_pretty` get full control.
fn to_json(p :: Problem) -> jv.Json {
  let errs_arr := list.map(p.errors, fn (er :: e.Error) -> jv.Json {
    JObj([("path", JStr(er.path)), ("code", JStr(er.code)), ("message", JStr(er.message))])
  })
  JObj([("type", JStr(p.type_uri)), ("title", JStr(p.title)), ("status", JInt(p.status)), ("detail", JStr(p.detail)), ("instance", JStr(p.instance)), ("errors", JList(errs_arr))])
}

# Render as a compact JSON string. The byte string an HTTP handler
# writes as the response body.
fn to_str(p :: Problem) -> Str {
  jv.stringify(to_json(p))
}

# Pretty-printed JSON. Useful for logging; not what you'd send on
# the wire.
fn to_pretty(p :: Problem) -> Str {
  jv.stringify_pretty(to_json(p))
}

# Convenience for HTTP handlers: returns a (status, body) tuple
# ready to drop into a Response record.
fn to_response(p :: Problem) -> (Int, Str) {
  (p.status, to_str(p))
}

# Content-Type the body should be served with.
fn content_type() -> Str {
  "application/problem+json"
}

