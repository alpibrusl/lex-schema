# Tests for `src/validator.lex` — the bundle value.

import "std.list" as list

import "std.str" as str

import "../src/error" as e

import "../src/json_value" as jv

import "../src/schema" as s

import "../src/validator" as v

fn schema() -> s.ModelSchema {
  { title: "User", description: "", fields: [s.required_str("name", [StrMinLen(1), StrMaxLen(40)]), s.required_int("age", [IntInRange(0, 130)])] }
}

# ---- make + summary ----------------------------------------------
fn make_carries_title() -> Result[Unit, Str] {
  let val := v.make(schema())
  if val.schema.title == "User" {
    Ok(())
  } else {
    Err("title wrong")
  }
}

fn summary_format() -> Result[Unit, Str] {
  let val := v.make(schema())
  if v.summary(val) == "Validator{title=\"User\", fields=2}" {
    Ok(())
  } else {
    Err(str.concat("got: ", v.summary(val)))
  }
}

# ---- validate / validate_str -------------------------------------
fn validate_str_good() -> Result[Unit, Str] {
  let val := v.make(schema())
  match v.validate_str(val, "{\"name\":\"alice\",\"age\":30}") {
    Ok(_) => Ok(()),
    Err(_) => Err("expected Ok"),
  }
}

fn validate_str_bad() -> Result[Unit, Str] {
  let val := v.make(schema())
  match v.validate_str(val, "{\"name\":\"\",\"age\":200}") {
    Ok(_) => Err("expected Err"),
    Err(es) => if list.len(es) == 2 {
      Ok(())
    } else {
      Err("wrong count")
    },
  }
}

fn validate_str_parse_failure() -> Result[Unit, Str] {
  let val := v.make(schema())
  match v.validate_str(val, "not json") {
    Ok(_) => Err("expected Err"),
    Err(es) => match list.head(es) {
      None => Err("empty"),
      Some(er) => if er.code == "parse" {
        Ok(())
      } else {
        Err(str.concat("wrong code: ", er.code))
      },
    },
  }
}

# ---- exports -----------------------------------------------------
fn typescript_export_has_interface() -> Result[Unit, Str] {
  let val := v.make(schema())
  if str.contains(v.export_typescript(val), "export interface User") {
    Ok(())
  } else {
    Err("no interface")
  }
}

fn python_export_has_basemodel() -> Result[Unit, Str] {
  let val := v.make(schema())
  if str.contains(v.export_python(val), "class User(BaseModel)") {
    Ok(())
  } else {
    Err("no BaseModel")
  }
}

fn json_schema_export_has_schema_url() -> Result[Unit, Str] {
  let val := v.make(schema())
  if str.contains(v.export_json_schema_str(val), "$schema") {
    Ok(())
  } else {
    Err("no $schema")
  }
}

fn openapi_export_no_schema_url() -> Result[Unit, Str] {
  let val := v.make(schema())
  if not str.contains(v.export_openapi_str(val), "$schema") {
    Ok(())
  } else {
    Err("openapi should not include $schema")
  }
}

# ---- serialize ---------------------------------------------------
fn serialize_valid_input() -> Result[Unit, Str] {
  let val := v.make(schema())
  let input := JObj([("name", JStr("bob")), ("age", JInt(25))])
  match v.serialize(val, input) {
    Ok(s) => if str.contains(s, "bob") {
      Ok(())
    } else {
      Err(str.concat("unexpected output: ", s))
    },
    Err(_) => Err("expected Ok"),
  }
}

fn serialize_strips_extra_fields() -> Result[Unit, Str] {
  let val := v.make(schema())
  let input := JObj([("name", JStr("bob")), ("age", JInt(25)), ("secret", JStr("x"))])
  match v.serialize(val, input) {
    Ok(s) => if not str.contains(s, "secret") {
      Ok(())
    } else {
      Err("extra field leaked into output")
    },
    Err(_) => Err("expected Ok"),
  }
}

fn serialize_invalid_input_returns_err() -> Result[Unit, Str] {
  let val := v.make(schema())
  let input := JObj([("name", JStr("")), ("age", JInt(25))])
  match v.serialize(val, input) {
    Ok(_) => Err("expected Err"),
    Err(es) => if list.len(es) >= 1 {
      Ok(())
    } else {
      Err("no errors")
    },
  }
}

# ---- serialize_strict --------------------------------------------
fn serialize_strict_clean_input_passes() -> Result[Unit, Str] {
  let val := v.make(schema())
  let input := JObj([("name", JStr("alice")), ("age", JInt(30))])
  match v.serialize_strict(val, input) {
    Ok(_) => Ok(()),
    Err(_) => Err("expected Ok"),
  }
}

fn serialize_strict_extra_field_rejected() -> Result[Unit, Str] {
  let val := v.make(schema())
  let input := JObj([("name", JStr("alice")), ("age", JInt(30)), ("role", JStr("admin"))])
  match v.serialize_strict(val, input) {
    Ok(_) => Err("expected Err"),
    Err(es) => match list.head(es) {
      None => Err("empty errors"),
      Some(er) => if er.code == "extra_field" {
        Ok(())
      } else {
        Err(str.concat("wrong code: ", er.code))
      },
    },
  }
}

fn serialize_strict_extra_field_path_is_key_name() -> Result[Unit, Str] {
  let val := v.make(schema())
  let input := JObj([("name", JStr("alice")), ("age", JInt(30)), ("role", JStr("admin"))])
  match v.serialize_strict(val, input) {
    Ok(_) => Err("expected Err"),
    Err(es) => match list.head(es) {
      None => Err("empty"),
      Some(er) => if er.path == "role" {
        Ok(())
      } else {
        Err(str.concat("wrong path: ", er.path))
      },
    },
  }
}

# ---- serialize_lossy ---------------------------------------------
fn serialize_lossy_drops_extras() -> Result[Unit, Str] {
  let val := v.make(schema())
  let input := JObj([("name", JStr("carol")), ("age", JInt(20)), ("extra", JBool(true))])
  let out := v.serialize_lossy(val, input)
  if not str.contains(out, "extra") {
    Ok(())
  } else {
    Err("extra field leaked")
  }
}

fn serialize_lossy_invalid_returns_empty_obj() -> Result[Unit, Str] {
  let val := v.make(schema())
  let input := JObj([("name", JStr("")), ("age", JInt(20))])
  let out := v.serialize_lossy(val, input)
  if out == "{}" {
    Ok(())
  } else {
    Err(str.concat("expected {}, got: ", out))
  }
}

# ---- openapi_response --------------------------------------------
fn openapi_response_has_200_key() -> Result[Unit, Str] {
  let val := v.make(schema())
  let resp := v.openapi_response(val)
  match jv.get_field(resp, "200") {
    Some(_) => Ok(()),
    None => Err("missing \"200\" key"),
  }
}

fn openapi_response_has_content_schema() -> Result[Unit, Str] {
  let val := v.make(schema())
  let resp := v.openapi_response(val)
  match jv.get_path(resp, "200.content.application/json.schema") {
    Some(_) => Ok(()),
    None => Err("missing schema at 200.content.application/json.schema"),
  }
}

fn openapi_response_schema_has_title() -> Result[Unit, Str] {
  let val := v.make(schema())
  let resp := v.openapi_response(val)
  match jv.get_path(resp, "200.content.application/json.schema") {
    None => Err("missing schema"),
    Some(schema) => match jv.get_field(schema, "title") {
      None => Err("missing title"),
      Some(t) => match jv.as_str(t) {
        Some(s) => if s == "User" {
          Ok(())
        } else {
          Err(str.concat("wrong title: ", s))
        },
        None => Err("title not a string"),
      },
    },
  }
}

# ---- Suite --------------------------------------------------------
fn suite() -> List[Result[Unit, Str]] {
  [make_carries_title(), summary_format(), validate_str_good(), validate_str_bad(), validate_str_parse_failure(), typescript_export_has_interface(), python_export_has_basemodel(), json_schema_export_has_schema_url(), openapi_export_no_schema_url(), serialize_valid_input(), serialize_strips_extra_fields(), serialize_invalid_input_returns_err(), serialize_strict_clean_input_passes(), serialize_strict_extra_field_rejected(), serialize_strict_extra_field_path_is_key_name(), serialize_lossy_drops_extras(), serialize_lossy_invalid_returns_empty_obj(), openapi_response_has_200_key(), openapi_response_has_content_schema(), openapi_response_schema_has_title()]
}

fn run_all() -> Int {
  list.fold(suite(), 0, fn (acc :: Int, v :: Result[Unit, Str]) -> Int {
    match v {
      Ok(_) => acc,
      Err(_) => acc + 1,
    }
  })
}

