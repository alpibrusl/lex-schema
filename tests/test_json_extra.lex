# Tests for the v0.3.0 additions to `src/json_value.lex`:
# dotted-path extraction (`get_path`, `j_str_at`, ...) and
# `stringify` round-trip.

import "std.list" as list

import "std.str" as str

import "../src/error" as e

import "../src/json_value" as jv

# ---- get_path -----------------------------------------------------
fn get_path_one_segment() -> Result[Unit, Str] {
  match jv.parse("{\"a\":1}") {
    Err(_) => Err("parse"),
    Ok(j) => match jv.get_path(j, "a") {
      Some(JInt(1)) => Ok(()),
      _ => Err("not JInt(1)"),
    },
  }
}

fn get_path_nested() -> Result[Unit, Str] {
  match jv.parse("{\"a\":{\"b\":{\"c\":42}}}") {
    Err(_) => Err("parse"),
    Ok(j) => match jv.get_path(j, "a.b.c") {
      Some(JInt(42)) => Ok(()),
      _ => Err("not JInt(42) at a.b.c"),
    },
  }
}

fn get_path_missing_intermediate() -> Result[Unit, Str] {
  match jv.parse("{\"a\":{\"b\":1}}") {
    Err(_) => Err("parse"),
    Ok(j) => match jv.get_path(j, "a.b.c.d") {
      None => Ok(()),
      Some(_) => Err("should be None"),
    },
  }
}

fn get_path_non_object_intermediate() -> Result[Unit, Str] {
  match jv.parse("{\"a\":42}") {
    Err(_) => Err("parse"),
    Ok(j) => match jv.get_path(j, "a.b") {
      None => Ok(()),
      Some(_) => Err("should be None"),
    },
  }
}

# ---- j_str_at / j_int_at -----------------------------------------
fn j_str_at_finds_nested() -> Result[Unit, Str] {
  match jv.parse("{\"user\":{\"email\":\"x@y.com\"}}") {
    Err(_) => Err("parse"),
    Ok(j) => match jv.j_str_at(j, "user.email", []) {
      Ok("x@y.com") => Ok(()),
      _ => Err("expected x@y.com"),
    },
  }
}

fn j_str_at_path_in_error() -> Result[Unit, Str] {
  match jv.parse("{\"user\":{}}") {
    Err(_) => Err("parse"),
    Ok(j) => match jv.j_str_at(j, "user.email", []) {
      Ok(_) => Err("should be Err"),
      Err(es) => match list.head(es) {
        None => Err("empty"),
        Some(er) => if er.path == "user.email" {
          Ok(())
        } else {
          Err(str.concat("wrong path: ", er.path))
        },
      },
    },
  }
}

fn j_optional_str_at_absent() -> Result[Unit, Str] {
  match jv.parse("{\"user\":{}}") {
    Err(_) => Err("parse"),
    Ok(j) => match jv.j_optional_str_at(j, "user.email", []) {
      Ok(None) => Ok(()),
      _ => Err("expected Ok(None)"),
    },
  }
}

# ---- stringify ---------------------------------------------------
fn stringify_primitives() -> Result[Unit, Str] {
  if jv.stringify(JNull) == "null" and jv.stringify(JBool(true)) == "true" and jv.stringify(JBool(false)) == "false" and jv.stringify(JInt(42)) == "42" and jv.stringify(JStr("ok")) == "\"ok\"" {
    Ok(())
  } else {
    Err("primitive stringify wrong")
  }
}

fn stringify_round_trip() -> Result[Unit, Str] {
  let original := "{\"a\":1,\"b\":[1,2,3],\"c\":\"hello\"}"
  match jv.parse(original) {
    Err(_) => Err("parse"),
    Ok(j) => {
      let serialized := jv.stringify(j)
      match jv.parse(serialized) {
        Err(_) => Err("re-parse failed"),
        Ok(j2) => if jv.stringify(j2) == serialized {
          Ok(())
        } else {
          Err(str.concat("not stable: ", serialized))
        },
      }
    },
  }
}

fn stringify_escapes() -> Result[Unit, Str] {
  let s := jv.stringify(JStr("hi\n\"world"))
  if s == "\"hi\\n\\\"world\"" {
    Ok(())
  } else {
    Err(str.concat("got: ", s))
  }
}

fn stringify_pretty_empty() -> Result[Unit, Str] {
  if jv.stringify_pretty(JList([])) == "[]" and jv.stringify_pretty(JObj([])) == "{}" {
    Ok(())
  } else {
    Err("empty container pretty form wrong")
  }
}

fn stringify_pretty_indents() -> Result[Unit, Str] {
  match jv.parse("{\"a\":1}") {
    Err(_) => Err("parse"),
    Ok(j) => {
      let pretty := jv.stringify_pretty(j)
      if str.contains(pretty, "\n  ") {
        Ok(())
      } else {
        Err(str.concat("no indent: ", pretty))
      }
    },
  }
}

# ---- Suite --------------------------------------------------------
fn suite() -> List[Result[Unit, Str]] {
  [get_path_one_segment(), get_path_nested(), get_path_missing_intermediate(), get_path_non_object_intermediate(), j_str_at_finds_nested(), j_str_at_path_in_error(), j_optional_str_at_absent(), stringify_primitives(), stringify_round_trip(), stringify_escapes(), stringify_pretty_empty(), stringify_pretty_indents()]
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

