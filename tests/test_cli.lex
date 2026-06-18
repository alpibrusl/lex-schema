# Tests for `src/cli.lex` — std.cli ↔ ModelSchema bridge.

import "std.cli" as cli

import "std.list" as list

import "std.str" as str

import "../src/error" as e

import "../src/json_value" as jv

import "../src/schema" as s

import "../src/cli" as cl

# ---- Shared CLI fixture -------------------------------------------
fn fixture_spec() -> Json {
  cli.spec("t", "test cli", [cli.flag("debug", Some("d"), ""), cli.option("output", Some("o"), "", Some("default.txt")), cli.positional("input", "", true)], [])
}

fn fixture_schema() -> s.ModelSchema {
  { title: "Args", description: "", fields: [s.required_str("input", [StrMinLen(1)]), s.required_str("output", [StrEndsWith(".txt")]), s.required_bool("debug")] }
}

# ---- Happy path ---------------------------------------------------
fn happy_path() -> Result[Unit, Str] {
  match cl.parse_and_validate_argv(fixture_spec(), ["./x", "--debug"], fixture_schema()) {
    Ok(_) => Ok(()),
    Err(_) => Err("expected Ok"),
  }
}

fn option_default_flows_through() -> Result[Unit, Str] {
  match cl.parse_and_validate_argv(fixture_spec(), ["./x"], fixture_schema()) {
    Err(_) => Err("expected Ok"),
    Ok(j) => match jv.j_str("", j, "output", []) {
      Ok(s) => if s == "default.txt" {
        Ok(())
      } else {
        Err(str.concat("wrong default: ", s))
      },
      Err(_) => Err("output missing"),
    },
  }
}

# ---- Failure modes ------------------------------------------------
fn cli_parse_error_tagged() -> Result[Unit, Str] {
  match cl.parse_and_validate_argv(fixture_spec(), [], fixture_schema()) {
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

fn schema_constraint_runs() -> Result[Unit, Str] {
  match cl.parse_and_validate_argv(fixture_spec(), ["./x", "--output", "report.pdf"], fixture_schema()) {
    Ok(_) => Err("expected Err"),
    Err(es) => match list.head(es) {
      None => Err("empty"),
      Some(er) => if er.path == "output" {
        Ok(())
      } else {
        Err(str.concat("wrong path: ", er.path))
      },
    },
  }
}

# ---- Flatten reconciliation ---------------------------------------
fn flatten_merges_buckets() -> Result[Unit, Str] {
  let parsed := JObj([("positionals", JObj([("input", JStr("p"))])), ("flags", JObj([("debug", JBool(true))])), ("options", JObj([("output", JStr("o.txt"))])), ("command", JList([JStr("t")]))])
  let flat := cl.flatten_cli_result(parsed)
  match jv.j_str("", flat, "input", []) {
    Ok("p") => match jv.j_bool("", flat, "debug") {
      Ok(true) => match jv.j_str("", flat, "output", []) {
        Ok("o.txt") => Ok(()),
        _ => Err("output wrong"),
      },
      _ => Err("debug wrong"),
    },
    _ => Err("input wrong"),
  }
}

# ---- Help passthrough --------------------------------------------
fn help_passthrough() -> Result[Unit, Str] {
  let h := cl.help(fixture_spec())
  if str.contains(h, "test cli") {
    Ok(())
  } else {
    Err("help missing spec description")
  }
}

# ---- Suite --------------------------------------------------------
fn suite() -> List[Result[Unit, Str]] {
  [happy_path(), option_default_flows_through(), cli_parse_error_tagged(), schema_constraint_runs(), flatten_merges_buckets(), help_passthrough()]
}

fn run_all() -> Int {
  list.fold(suite(), 0, fn (acc :: Int, v :: Result[Unit, Str]) -> Int {
    match v {
      Ok(_) => acc,
      Err(_) => acc + 1,
    }
  })
}

