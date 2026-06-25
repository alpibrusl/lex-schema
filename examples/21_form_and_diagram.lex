# lex-schema — HTML-form login + ER diagram + Go codegen tour
#
# Demonstrates the three v0.8.1 additions:
#
#   1. `form.decode_urlencoded` parsing an
#      `application/x-www-form-urlencoded` body.
#   2. `s.to_mermaid_er` emitting a Markdown-renderable ER
#      diagram off the same `ModelSchema` we validate against.
#   3. `sdk.to_go_struct` rounding out the codegen quartet
#      (now: TS, Python, Zod, Rust, Go).
#
# The login form is the canonical HTML-form-encoded case.
# Real-world: legacy auth flows, OAuth callbacks, simple POST
# endpoints that don't want a JSON body.
#
# Run:
#   lex run examples/21_form_and_diagram.lex demo_login_good
#   lex run examples/21_form_and_diagram.lex format_login_bad
#   lex run examples/21_form_and_diagram.lex demo_mermaid
#   lex run examples/21_form_and_diagram.lex demo_go_struct

import "../src/error" as e

import "../src/constraints" as c

import "../src/coerce" as coerce

import "../src/combine" as cm

import "../src/form" as form

import "../src/schema" as s

import "../src/sdk" as sdk

# ---- Login schema -------------------------------------------------
type LoginFields = { username :: Str, password :: Str, remember :: Bool }

fn login_schema() -> s.ModelSchema {
  { title: "Login", description: "Form-encoded login submission", fields: [s.required_str("username", [StrMinLen(3), StrMaxLen(32), StrPattern("^[a-zA-Z0-9_]+$")]), s.required_str("password", [StrMinLen(8), StrMaxLen(128)]), s.required_bool("remember")] }
}

# ---- Validation pipeline ------------------------------------------
fn build_login(un :: Str, pw :: Str, r :: Bool) -> LoginFields {
  { username: un, password: pw, remember: r }
}

fn parse_login(body :: Str) -> Result[LoginFields, e.Errors] {
  let m := form.decode_urlencoded(body)
  cm.combine3(coerce.require_str_from_map(m, "username", [StrMinLen(3), StrMaxLen(32), StrPattern("^[a-zA-Z0-9_]+$")]), coerce.require_str_from_map(m, "password", [StrMinLen(8), StrMaxLen(128)]), coerce.require_bool_from_map(m, "remember"), build_login)
}

# ---- Demos --------------------------------------------------------
fn demo_login_good() -> Result[LoginFields, e.Errors] {
  parse_login("username=alice_42&password=correcthorse9&remember=true")
}

fn demo_login_bad() -> Result[LoginFields, e.Errors] {
  parse_login("username=a!&password=weak&remember=maybe")
}

fn format_login_bad() -> Str {
  match demo_login_bad() {
    Ok(_) => "(no errors)",
    Err(es) => e.format(es),
  }
}

# Form with URL-encoded special characters — pluses, spaces, accents.
fn demo_login_encoded() -> Result[LoginFields, e.Errors] {
  parse_login("username=alice_42&password=correct+horse+battery+9&remember=1")
}

# ---- Mermaid ER diagram ------------------------------------------
fn demo_mermaid() -> Str {
  s.to_mermaid_er(login_schema())
}

# ---- Go codegen --------------------------------------------------
fn demo_go_struct() -> Str {
  sdk.to_go_struct(login_schema())
}

