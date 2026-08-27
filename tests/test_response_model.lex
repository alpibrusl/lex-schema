# Tests for `src/validator.lex`'s response-model surface
# (serialize / serialize_strict / serialize_lossy / openapi_response).
# Filed as a spike for https://github.com/alpibrusl/lex-schema/issues/1.

import "std.list" as list

import "std.str" as str

import "../src/error" as e

import "../src/json_value" as jv

import "../src/schema" as s

import "../src/validator" as v

# Reusable schema for every test below.
fn schema() -> s.ModelSchema {
  { title: "User", description: "", fields: [s.required_str("name", [StrMinLen(1), StrMaxLen(40)]), s.required_int("age", [IntInRange(0, 130)])] }
}

fn good_json() -> jv.Json {
  JObj([("name", JStr("alice")), ("age", JInt(30))])
}

fn json_with_extra() -> jv.Json {
  JObj([("name", JStr("alice")), ("age", JInt(30)), ("password_hash", JStr("INTERNAL"))])
}

fn json_with_two_extras() -> jv.Json {
  JObj([("name", JStr("alice")), ("age", JInt(30)), ("hash", JStr("INTERNAL")), ("debug_log", JStr("INTERNAL"))])
}

fn bad_age_json() -> jv.Json {
  JObj([("name", JStr("alice")), ("age", JInt(999))])
}

# ---- serialize_lossy ---------------------------------------------
# serialize_lossy returns Str directly. Extras are dropped and on a
# validation failure the output is "{}" — see src/validator.lex docs.
fn lossy_strips_extras() -> Result[Unit, Str] {
  let val := v.make(schema())
  let out := v.serialize_lossy(val, json_with_extra())
  if str.contains(out, "alice") and str.contains(out, "30") and not str.contains(out, "password_hash") and not str.contains(out, "INTERNAL") {
    Ok(())
  } else {
    Err(str.concat("extras leaked: ", out))
  }
}

fn lossy_passes_clean_input() -> Result[Unit, Str] {
  let val := v.make(schema())
  let out := v.serialize_lossy(val, good_json())
  if str.contains(out, "alice") and str.contains(out, "30") {
    Ok(())
  } else {
    Err(str.concat("payload mangled: ", out))
  }
}

fn lossy_returns_empty_on_failure() -> Result[Unit, Str] {
  let val := v.make(schema())
  let out := v.serialize_lossy(val, bad_age_json())
  if out == "{}" {
    Ok(())
  } else {
    Err(str.concat("expected '{}' on failure, got: ", out))
  }
}

# ---- serialize_strict --------------------------------------------
fn strict_rejects_one_extra() -> Result[Unit, Str] {
  let val := v.make(schema())
  match v.serialize_strict(val, json_with_extra()) {
    Ok(_) => Err("strict should not pass with extras"),
    Err(es) => {
      let has := list.fold(es, false, fn (acc :: Bool, err :: e.Error) -> Bool {
        acc or err.code == e.code_extra() and err.path == "password_hash"
      })
      if has {
        Ok(())
      } else {
        Err("unexpected error not surfaced")
      }
    },
  }
}

fn strict_reports_every_extra() -> Result[Unit, Str] {
  let val := v.make(schema())
  match v.serialize_strict(val, json_with_two_extras()) {
    Ok(_) => Err("strict should not pass with extras"),
    Err(es) => {
      let unexpected := list.fold(es, 0, fn (acc :: Int, err :: e.Error) -> Int {
        if err.code == e.code_extra() {
          acc + 1
        } else {
          acc
        }
      })
      if unexpected == 2 {
        Ok(())
      } else {
        Err("expected 2 unexpected errors")
      }
    },
  }
}

fn strict_passes_clean_input() -> Result[Unit, Str] {
  let val := v.make(schema())
  match v.serialize_strict(val, good_json()) {
    Ok(out) => if str.contains(out, "alice") and str.contains(out, "30") {
      Ok(())
    } else {
      Err(str.concat("payload mangled: ", out))
    },
    Err(_) => Err("expected Ok"),
  }
}

fn strict_rejects_non_object() -> Result[Unit, Str] {
  let val := v.make(schema())
  match v.serialize_strict(val, JStr("not an object")) {
    Ok(_) => Err("strict should not pass a non-object"),
    Err(es) => if list.len(es) >= 1 {
      Ok(())
    } else {
      Err("non-object surfaced no errors")
    },
  }
}

# ---- serialize (default = lossy) ----------------------------------
fn serialize_defaults_to_lossy() -> Result[Unit, Str] {
  let val := v.make(schema())
  match v.serialize(val, json_with_extra()) {
    Ok(out) => if not str.contains(out, "password_hash") {
      Ok(())
    } else {
      Err("default should drop extras")
    },
    Err(_) => Err("expected Ok on clean payload"),
  }
}

# ---- openapi_response --------------------------------------------
fn openapi_response_shape() -> Result[Unit, Str] {
  let val := v.make(schema())
  let resp := v.openapi_response(val)
  let s := jv.stringify(resp)
  if str.contains(s, "description") and str.contains(s, "content") and str.contains(s, "application/json") and str.contains(s, "schema") {
    Ok(())
  } else {
    Err(str.concat("openapi_response missing keys: ", s))
  }
}

fn openapi_response_uses_title() -> Result[Unit, Str] {
  let val := v.make(schema())
  let s := jv.stringify(v.openapi_response(val))
  if str.contains(s, "User") {
    Ok(())
  } else {
    Err("title not in description")
  }
}

# ---- Suite --------------------------------------------------------
fn suite() -> List[Result[Unit, Str]] {
  [lossy_strips_extras(), lossy_passes_clean_input(), lossy_returns_empty_on_failure(), strict_rejects_one_extra(), strict_reports_every_extra(), strict_passes_clean_input(), strict_rejects_non_object(), serialize_defaults_to_lossy(), openapi_response_shape(), openapi_response_uses_title()]
}

fn run_all_count() -> Int {
  list.fold(suite(), 0, fn (acc :: Int, r :: Result[Unit, Str]) -> Int {
    match r {
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

