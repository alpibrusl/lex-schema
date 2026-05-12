# Tests for `src/validator.lex` — the bundle value.

import "std.list" as list
import "std.str"  as str

import "../src/error"      as e
import "../src/json_value" as jv
import "../src/schema"     as s
import "../src/validator"  as v

fn schema() -> s.ModelSchema {
  {
    title: "User", description: "",
    fields: [
      s.required_str("name",  [StrMinLen(1), StrMaxLen(40)]),
      s.required_int("age",   [IntInRange(0, 130)]),
    ],
  }
}

# ---- make + summary ----------------------------------------------

fn make_carries_title() -> Result[Unit, Str] {
  let val := v.make(schema())
  if val.schema.title == "User" { Ok(()) } else { Err("title wrong") }
}

fn summary_format() -> Result[Unit, Str] {
  let val := v.make(schema())
  if v.summary(val) == "Validator{title=\"User\", fields=2}" { Ok(()) }
  else { Err(str.concat("got: ", v.summary(val))) }
}

# ---- validate / validate_str -------------------------------------

fn validate_str_good() -> Result[Unit, Str] {
  let val := v.make(schema())
  match v.validate_str(val, "{\"name\":\"alice\",\"age\":30}") {
    Ok(_)  => Ok(()),
    Err(_) => Err("expected Ok"),
  }
}

fn validate_str_bad() -> Result[Unit, Str] {
  let val := v.make(schema())
  match v.validate_str(val, "{\"name\":\"\",\"age\":200}") {
    Ok(_)   => Err("expected Err"),
    Err(es) => if list.len(es) == 2 { Ok(()) } else { Err("wrong count") },
  }
}

fn validate_str_parse_failure() -> Result[Unit, Str] {
  let val := v.make(schema())
  match v.validate_str(val, "not json") {
    Ok(_)   => Err("expected Err"),
    Err(es) => match list.head(es) {
      None      => Err("empty"),
      Some(er)  => if er.code == "parse" { Ok(()) } else {
        Err(str.concat("wrong code: ", er.code))
      },
    },
  }
}

# ---- exports -----------------------------------------------------

fn typescript_export_has_interface() -> Result[Unit, Str] {
  let val := v.make(schema())
  if str.contains(v.export_typescript(val), "export interface User") { Ok(()) }
  else { Err("no interface") }
}

fn python_export_has_basemodel() -> Result[Unit, Str] {
  let val := v.make(schema())
  if str.contains(v.export_python(val), "class User(BaseModel)") { Ok(()) }
  else { Err("no BaseModel") }
}

fn json_schema_export_has_schema_url() -> Result[Unit, Str] {
  let val := v.make(schema())
  if str.contains(v.export_json_schema_str(val), "$schema") { Ok(()) }
  else { Err("no $schema") }
}

fn openapi_export_no_schema_url() -> Result[Unit, Str] {
  let val := v.make(schema())
  if not (str.contains(v.export_openapi_str(val), "$schema")) { Ok(()) }
  else { Err("openapi should not include $schema") }
}

# ---- Suite --------------------------------------------------------

fn suite() -> List[Result[Unit, Str]] {
  [
    make_carries_title(),
    summary_format(),
    validate_str_good(),
    validate_str_bad(),
    validate_str_parse_failure(),
    typescript_export_has_interface(),
    python_export_has_basemodel(),
    json_schema_export_has_schema_url(),
    openapi_export_no_schema_url(),
  ]
}

fn run_all() -> Int {
  list.fold(suite(), 0, fn (acc :: Int, v :: Result[Unit, Str]) -> Int {
    match v {
      Ok(_)  => acc,
      Err(_) => acc + 1,
    }
  })
}
