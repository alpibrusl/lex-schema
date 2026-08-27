# Tests for `src/schema.lex` — schema-driven validation +
# JSON Schema / OpenAPI export.

import "std.list" as list

import "std.str" as str

import "../src/error" as e

import "../src/json_value" as jv

import "../src/schema" as s

# A small schema reused across the suite.
fn user_schema() -> s.ModelSchema {
  { title: "User", description: "", fields: [s.required_str("name", [StrMinLen(1), StrMaxLen(80)]), s.required_int("age", [IntInRange(13, 130)]), s.optional(s.required_str("nickname", [StrMaxLen(40)]))] }
}

# ---- validate -----------------------------------------------------
fn validate_happy() -> Result[Unit, Str] {
  match jv.parse("{\"name\":\"Alice\",\"age\":30}") {
    Err(_) => Err("parse"),
    Ok(j) => match s.validate(user_schema(), j) {
      Ok(_) => Ok(()),
      Err(_) => Err("expected Ok"),
    },
  }
}

fn validate_missing_required() -> Result[Unit, Str] {
  match jv.parse("{\"name\":\"Alice\"}") {
    Err(_) => Err("parse"),
    Ok(j) => match s.validate(user_schema(), j) {
      Ok(_) => Err("expected Err"),
      Err(es) => match list.head(es) {
        None => Err("empty"),
        Some(er) => if er.code == "missing" and er.path == "age" {
          Ok(())
        } else {
          Err(str.concat("got: ", er.path))
        },
      },
    },
  }
}

fn validate_type_mismatch() -> Result[Unit, Str] {
  match jv.parse("{\"name\":\"Alice\",\"age\":\"thirty\"}") {
    Err(_) => Err("parse"),
    Ok(j) => match s.validate(user_schema(), j) {
      Ok(_) => Err("expected Err"),
      Err(es) => match list.head(es) {
        None => Err("empty"),
        Some(er) => if er.code == "type" and er.path == "age" {
          Ok(())
        } else {
          Err(str.concat("got code/path: ", er.code))
        },
      },
    },
  }
}

fn validate_optional_absent_ok() -> Result[Unit, Str] {
  match jv.parse("{\"name\":\"Alice\",\"age\":30}") {
    Err(_) => Err("parse"),
    Ok(j) => match s.validate(user_schema(), j) {
      Ok(_) => Ok(()),
      Err(_) => Err("expected Ok"),
    },
  }
}

fn validate_constraint_failure() -> Result[Unit, Str] {
  match jv.parse("{\"name\":\"A\",\"age\":7}") {
    Err(_) => Err("parse"),
    Ok(j) => match s.validate(user_schema(), j) {
      Ok(_) => Err("expected Err"),
      Err(es) => if list.len(es) == 1 {
        Ok(())
      } else {
        Err(str.concat("expected 1 error, got len ", str.concat("count", "")))
      },
    },
  }
}

# ---- nested validation -------------------------------------------
fn nested_schema() -> s.ModelSchema {
  { title: "Container", description: "", fields: [s.required_object("inner", { title: "Inner", description: "", fields: [s.required_int("n", [IntPositive])] })] }
}

fn nested_path_in_error() -> Result[Unit, Str] {
  match jv.parse("{\"inner\":{\"n\":-1}}") {
    Err(_) => Err("parse"),
    Ok(j) => match s.validate(nested_schema(), j) {
      Ok(_) => Err("expected Err"),
      Err(es) => match list.head(es) {
        None => Err("empty"),
        Some(er) => if er.path == "inner.n" {
          Ok(())
        } else {
          Err(str.concat("wrong path: ", er.path))
        },
      },
    },
  }
}

# ---- array validation --------------------------------------------
fn array_schema() -> s.ModelSchema {
  { title: "Box", description: "", fields: [s.required_array("items", KStr([StrMinLen(1)]), [ListMinLen(1)])] }
}

fn array_element_error_indexed() -> Result[Unit, Str] {
  match jv.parse("{\"items\":[\"ok\",\"\",\"also\"]}") {
    Err(_) => Err("parse"),
    Ok(j) => match s.validate(array_schema(), j) {
      Ok(_) => Err("expected Err"),
      Err(es) => match list.head(es) {
        None => Err("empty"),
        Some(er) => if er.path == "items[1]" {
          Ok(())
        } else {
          Err(str.concat("wrong path: ", er.path))
        },
      },
    },
  }
}

fn array_shape_error() -> Result[Unit, Str] {
  match jv.parse("{\"items\":[]}") {
    Err(_) => Err("parse"),
    Ok(j) => match s.validate(array_schema(), j) {
      Ok(_) => Err("expected Err"),
      Err(_) => Ok(()),
    },
  }
}

# ---- to_json_schema ----------------------------------------------
fn json_schema_top_level() -> Result[Unit, Str] {
  let sch := jv.stringify(s.to_json_schema(user_schema()))
  if str.contains(sch, "$schema") and str.contains(sch, "\"type\":\"object\"") and str.contains(sch, "\"name\":") and str.contains(sch, "\"age\":") and str.contains(sch, "\"required\":") {
    Ok(())
  } else {
    Err("missing expected json-schema fields")
  }
}

fn json_schema_required_field_listed() -> Result[Unit, Str] {
  let sch := jv.stringify(s.to_json_schema(user_schema()))
  if str.contains(sch, "\"required\":[\"name\",\"age\"]") {
    Ok(())
  } else {
    Err(str.concat("required wrong: ", sch))
  }
}

fn json_schema_constraint_emitted() -> Result[Unit, Str] {
  let sch := jv.stringify(s.to_json_schema(user_schema()))
  if str.contains(sch, "\"minLength\":1") and str.contains(sch, "\"maxLength\":80") {
    Ok(())
  } else {
    Err("constraint missing")
  }
}

fn json_schema_email_format() -> Result[Unit, Str] {
  let sch_obj := s.to_json_schema({ title: "X", description: "", fields: [s.required_str("email", [StrEmail])] })
  let sch := jv.stringify(sch_obj)
  if str.contains(sch, "\"format\":\"email\"") {
    Ok(())
  } else {
    Err(str.concat("missing email format: ", sch))
  }
}

# ---- to_openapi_schema -------------------------------------------
fn openapi_no_dollar_schema() -> Result[Unit, Str] {
  let sch := jv.stringify(s.to_openapi_schema(user_schema()))
  if not str.contains(sch, "$schema") {
    Ok(())
  } else {
    Err("openapi shouldn't include $schema")
  }
}

# ---- Suite --------------------------------------------------------
fn suite() -> List[Result[Unit, Str]] {
  [validate_happy(), validate_missing_required(), validate_type_mismatch(), validate_optional_absent_ok(), validate_constraint_failure(), nested_path_in_error(), array_element_error_indexed(), array_shape_error(), json_schema_top_level(), json_schema_required_field_listed(), json_schema_constraint_emitted(), json_schema_email_format(), openapi_no_dollar_schema()]
}

fn run_all_count() -> Int {
  list.fold(suite(), 0, fn (acc :: Int, v :: Result[Unit, Str]) -> Int {
    match v {
      Ok(_) => acc,
      Err(_) => acc + 1,
    }
  })
}

# `lex test` calls `run_all` and DISCARDS what it returns (lex-lang#757), so a
# returned failure count reports `ok` however many assertions failed. Only a
# raise fails a file — the same idiom lex-ems, lex-web and lex-guard use.
# Run `run_all_count` directly to see which assertions failed.
fn run_all() -> Unit {
  if run_all_count() == 0 {
    ()
  } else {
    let __boom := 1 / 0
    ()
  }
}

