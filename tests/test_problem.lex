# Tests for `src/problem.lex` — RFC 7807 problem+json renderer.

import "std.list" as list
import "std.str"  as str

import "../src/error"   as e
import "../src/problem" as pr

# ---- Basic shape ---------------------------------------------------

fn validation_problem_carries_errors() -> Result[Unit, Str] {
  let p := pr.validation_problem("https://example.com/p", "/v1/x", [
    e.error("email", "email", "not valid"),
    e.error("age",   "min",   "too low"),
  ])
  if p.status == 422 and list.len(p.errors) == 2 { Ok(()) }
  else { Err("wrong fields") }
}

fn detail_singular() -> Result[Unit, Str] {
  let p := pr.validation_problem("u", "/", [e.error("x", "c", "m")])
  if p.detail == "1 field failed validation" { Ok(()) }
  else { Err(str.concat("got: ", p.detail)) }
}

fn detail_plural() -> Result[Unit, Str] {
  let p := pr.validation_problem("u", "/", [
    e.error("a", "c", "m"),
    e.error("b", "c", "m"),
  ])
  if p.detail == "2 fields failed validation" { Ok(()) }
  else { Err(str.concat("got: ", p.detail)) }
}

# ---- Other status presets -----------------------------------------

fn not_found_status() -> Result[Unit, Str] {
  let p := pr.not_found("u", "/x", "no such resource")
  if p.status == 404 and p.title == "Not Found" { Ok(()) }
  else { Err("wrong shape") }
}

fn method_not_allowed_allows() -> Result[Unit, Str] {
  let p := pr.method_not_allowed("u", "/x", "GET, POST")
  if p.status == 405 and str.contains(p.detail, "GET, POST") { Ok(()) }
  else { Err("wrong allow") }
}

fn unauthorized_status() -> Result[Unit, Str] {
  let p := pr.unauthorized("u", "/x", "no token")
  if p.status == 401 { Ok(()) } else { Err("wrong status") }
}

# ---- Serialization -------------------------------------------------

fn to_str_carries_all_fields() -> Result[Unit, Str] {
  let p := pr.validation_problem("https://example.com/p", "/v1/x", [
    e.error("email", "email", "not valid"),
  ])
  let s := pr.to_str(p)
  if str.contains(s, "\"type\"")
    and str.contains(s, "\"title\"")
    and str.contains(s, "\"status\":422")
    and str.contains(s, "\"detail\"")
    and str.contains(s, "\"instance\":\"/v1/x\"")
    and str.contains(s, "\"errors\":[")
    and str.contains(s, "\"email\"")
  { Ok(()) }
  else { Err(str.concat("missing fields: ", s)) }
}

fn content_type_is_problem_json() -> Result[Unit, Str] {
  if pr.content_type() == "application/problem+json" { Ok(()) }
  else { Err("wrong content-type") }
}

fn to_response_returns_pair() -> Result[Unit, Str] {
  let p := pr.bad_request("u", "/x", "bad input")
  match pr.to_response(p) {
    (400, body) => if str.contains(body, "\"status\":400") { Ok(()) }
                   else { Err("body missing status") },
    _ => Err("wrong pair"),
  }
}

# ---- Suite ---------------------------------------------------------

fn suite() -> List[Result[Unit, Str]] {
  [
    validation_problem_carries_errors(),
    detail_singular(),
    detail_plural(),
    not_found_status(),
    method_not_allowed_allows(),
    unauthorized_status(),
    to_str_carries_all_fields(),
    content_type_is_problem_json(),
    to_response_returns_pair(),
  ]
}

fn run_all() -> Int {
  list.fold(suite(), 0, fn (acc :: Int, v :: Result[Unit, Str]) -> Int {
    match v { Ok(_) => acc, Err(_) => acc + 1 }
  })
}
