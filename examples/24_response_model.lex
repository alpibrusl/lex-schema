# lex-schema — response model (FastAPI's response_model parity)
#
# Two schemas, one source of truth per direction:
#
#   - UserIn  (input) — name + age, what the client posts
#   - UserOut (output) — id + name (no internal fields)
#
# The store keeps internal-only attributes — a password_hash and an
# audit_log entry — that must NEVER leak into responses. We use
# v.serialize_strict on the way out so any drift between the
# internal record shape and the declared response contract is a
# 500 (server-side contract bug), not a silent leak.
#
# Demonstrates:
#
#   - v.serialize_lossy  — drop extras silently (FastAPI's default)
#   - v.serialize_strict — surface every extra field as a typed Error
#   - v.openapi_response — emit the OpenAPI 3.1 responses[200] body
#                          envelope wrapping the schema
#
# Run the demo:
#
#   lex run examples/24_response_model.lex demo_lossy
#   lex run examples/24_response_model.lex demo_strict
#   lex run examples/24_response_model.lex demo_strict_clean
#   lex run examples/24_response_model.lex demo_openapi
#
# Filed alongside the spike for
# https://github.com/alpibrusl/lex-schema/issues/1.

import "std.str" as str

import "std.list" as list

import "std.io" as io

import "../src/error" as e

import "../src/constraints" as c

import "../src/schema" as s

import "../src/validator" as v

import "../src/json_value" as jv

# ---- Schemas ------------------------------------------------------
# What clients are allowed to POST.
fn user_in_schema() -> s.ModelSchema {
  { title: "UserIn", description: "User signup request", fields: [s.required_str("name", [StrMinLen(1), StrMaxLen(40)]), s.required_int("age", [IntInRange(13, 130)])] }
}

# What clients are allowed to see back. Notice: no password_hash,
# no audit_log, no created_at — the store may keep them, the API
# contract says they don't exist.
fn user_out_schema() -> s.ModelSchema {
  { title: "UserOut", description: "User as returned to clients", fields: [s.required_int("id", []), s.required_str("name", [StrMinLen(1), StrMaxLen(40)])] }
}

fn user_in() -> v.Validator {
  v.make(user_in_schema())
}

fn user_out() -> v.Validator {
  v.make(user_out_schema())
}

# ---- Simulated store record ---------------------------------------
# What we'd actually pull out of the database — note the four
# fields the schema-driven response does NOT declare.
fn store_record() -> jv.Json {
  JObj([("id", JInt(42)), ("name", JStr("alice")), ("password_hash", JStr("$2b$12$INTERNAL_DO_NOT_LEAK")), ("audit_log", JStr("created via /signup at 2026-05-13T05:00Z")), ("internal_uid", JStr("u-internal-9387")), ("created_at", JStr("2026-05-13T05:00Z"))])
}

# ---- Demos --------------------------------------------------------
# Lossy — internal fields silently disappear, the response goes out
# clean. This is what FastAPI does by default with response_model=.
fn demo_lossy() -> [io] Nil {
  match v.serialize_lossy(user_out(), store_record()) {
    Err(es) => io.print(str.concat("err: ", e.format(es))),
    Ok(out) => {
      let __lex_discard_1 := io.print("== serialize_lossy ==")
      let __lex_discard_2 := io.print(out)
      ()
    },
  }
}

# Strict — the same input now surfaces every internal field as an
# `unexpected` error. Use this in tests to catch contract drift; in
# production you'd map the Err to a 500 with a server-side log.
fn demo_strict() -> [io] Nil {
  match v.serialize_strict(user_out(), store_record()) {
    Ok(_) => io.print("(no errors — bug!)"),
    Err(es) => {
      let __lex_discard_3 := io.print("== serialize_strict — surfaces internal-field leaks ==")
      let __lex_discard_4 := io.print(e.format(es))
      ()
    },
  }
}

# Strict on a clean payload: same surface, but passes. The payload
# would normally come from a service that projected the store
# record into the response shape before serialisation.
fn demo_strict_clean() -> [io] Nil {
  let clean := JObj([("id", JInt(42)), ("name", JStr("alice"))])
  match v.serialize_strict(user_out(), clean) {
    Err(es) => io.print(str.concat("err: ", e.format(es))),
    Ok(out) => {
      let __lex_discard_5 := io.print("== serialize_strict (clean payload) ==")
      let __lex_discard_6 := io.print(out)
      ()
    },
  }
}

# OpenAPI fragment — what you'd stash under responses[200] in an
# OpenAPI 3.1 document. lex-web's openapi.export_openapi can read
# this directly off the Validator bundle.
fn demo_openapi() -> [io] Nil {
  let frag := v.openapi_response(user_out())
  let __lex_discard_7 := io.print("== openapi_response (responses[200] body) ==")
  let __lex_discard_8 := io.print(jv.stringify_pretty(frag))
  ()
}

# ---- A composed "handler" stitching it all together --------------
# Production shape: validate the request, do the work, validate the
# response. Three places `Result` chains together; one declarative
# return-shape contract on each end.
type HandlerErr = BadRequest(e.Errors) | InternalContract(e.Errors)

fn signup(body :: jv.Json, db_record :: jv.Json) -> Result[Str, HandlerErr] {
  match v.validate(user_in(), body) {
    Err(es) => Err(BadRequest(es)),
    Ok(_in) => match v.serialize_strict(user_out(), db_record) {
      Err(es) => Err(InternalContract(es)),
      Ok(json) => Ok(json),
    },
  }
}

fn demo_handler_leak() -> [io] Nil {
  let req := JObj([("name", JStr("alice")), ("age", JInt(30))])
  match signup(req, store_record()) {
    Ok(_) => io.print("(no errors — bug!)"),
    Err(InternalContract(es)) => {
      let __lex_discard_9 := io.print("== handler caught a response-contract drift ==")
      let __lex_discard_10 := io.print(e.format(es))
      ()
    },
    Err(BadRequest(es)) => io.print(str.concat("bad request: ", e.format(es))),
  }
}

fn demo_handler_clean() -> [io] Nil {
  let req := JObj([("name", JStr("alice")), ("age", JInt(30))])
  let clean := JObj([("id", JInt(42)), ("name", JStr("alice"))])
  match signup(req, clean) {
    Ok(json) => {
      let __lex_discard_11 := io.print("== handler (clean store record) ==")
      let __lex_discard_12 := io.print(json)
      ()
    },
    Err(_) => io.print("(unexpected error)"),
  }
}

# ---- Top-level main runs the full reel ---------------------------
fn main() -> [io] Nil {
  let __lex_discard_13 := demo_lossy()
  let __lex_discard_14 := io.print("")
  let __lex_discard_15 := demo_strict()
  let __lex_discard_16 := io.print("")
  let __lex_discard_17 := demo_strict_clean()
  let __lex_discard_18 := io.print("")
  let __lex_discard_19 := demo_openapi()
  let __lex_discard_20 := io.print("")
  let __lex_discard_21 := demo_handler_leak()
  let __lex_discard_22 := io.print("")
  let __lex_discard_23 := demo_handler_clean()
  ()
}

