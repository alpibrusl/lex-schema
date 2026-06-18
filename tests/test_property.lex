# Tests for `src/property.lex` — schema-driven sample generation.

import "std.list" as list

import "std.str" as str

import "std.random" as random

import "../src/error" as e

import "../src/json_value" as jv

import "../src/schema" as s

import "../src/property" as p

# ---- generate primitives -----------------------------------------
fn gen_str_respects_bounds() -> Result[Unit, Str] {
  let schema := { title: "T", description: "", fields: [s.required_str("x", [StrMinLen(5), StrMaxLen(10)])] }
  let g := p.generate(schema, random.seed(1))
  let v := match g {
    (v1, _) => v1,
  }
  match jv.get_field(v, "x") {
    Some(JStr(s)) => {
      let len := str.len(s)
      if len >= 5 and len <= 10 {
        Ok(())
      } else {
        Err("out of range")
      }
    },
    _ => Err("no x field"),
  }
}

fn gen_int_respects_bounds() -> Result[Unit, Str] {
  let schema := { title: "T", description: "", fields: [s.required_int("n", [IntInRange(10, 20)])] }
  let g := p.generate(schema, random.seed(2))
  let v := match g {
    (v1, _) => v1,
  }
  match jv.get_field(v, "n") {
    Some(JInt(n)) => if n >= 10 and n <= 20 {
      Ok(())
    } else {
      Err("out of range")
    },
    _ => Err("no n field"),
  }
}

fn gen_email_format() -> Result[Unit, Str] {
  let schema := { title: "T", description: "", fields: [s.required_str("email", [StrEmail])] }
  let g := p.generate(schema, random.seed(3))
  let v := match g {
    (v1, _) => v1,
  }
  match jv.get_field(v, "email") {
    Some(JStr(s)) => if str.contains(s, "@") {
      Ok(())
    } else {
      Err(str.concat("no @ in: ", s))
    },
    _ => Err("no email"),
  }
}

fn gen_uuid_format() -> Result[Unit, Str] {
  let schema := { title: "T", description: "", fields: [s.required_str("id", [StrUuid])] }
  let g := p.generate(schema, random.seed(4))
  let v := match g {
    (v1, _) => v1,
  }
  match jv.get_field(v, "id") {
    Some(JStr(s)) => if str.len(s) == 36 {
      Ok(())
    } else {
      Err(str.concat("not 36 chars: ", s))
    },
    _ => Err("no id"),
  }
}

fn gen_one_of_picks_from_set() -> Result[Unit, Str] {
  let schema := { title: "T", description: "", fields: [s.required_str("color", [StrOneOf(["red", "green", "blue"])])] }
  let g := p.generate(schema, random.seed(5))
  let v := match g {
    (v1, _) => v1,
  }
  match jv.get_field(v, "color") {
    Some(JStr("red")) => Ok(()),
    Some(JStr("green")) => Ok(()),
    Some(JStr("blue")) => Ok(()),
    Some(JStr(other)) => Err(str.concat("not in set: ", other)),
    _ => Err("no color"),
  }
}

# ---- determinism --------------------------------------------------
fn deterministic_per_seed() -> Result[Unit, Str] {
  let schema := { title: "T", description: "", fields: [s.required_str("a", [StrMinLen(3), StrMaxLen(5)]), s.required_int("n", [IntInRange(0, 100)])] }
  let g1 := p.generate(schema, random.seed(42))
  let g2 := p.generate(schema, random.seed(42))
  let v1 := match g1 {
    (v, _) => v,
  }
  let v2 := match g2 {
    (v, _) => v,
  }
  if jv.stringify(v1) == jv.stringify(v2) {
    Ok(())
  } else {
    Err("same seed produced different samples")
  }
}

# ---- round-trip property -----------------------------------------
fn round_trip_small_schema() -> Result[Unit, Str] {
  let schema := { title: "User", description: "", fields: [s.required_str("name", [StrMinLen(1), StrMaxLen(20)]), s.required_int("age", [IntInRange(0, 120)]), s.required_bool("ok")] }
  match p.round_trip(schema, 50, 100) {
    Ok(50) => Ok(()),
    Ok(n) => Err(str.concat("only passed ", "")),
    Err(_) => Err("a sample failed validation"),
  }
}

fn round_trip_with_array() -> Result[Unit, Str] {
  let schema := { title: "Box", description: "", fields: [s.required_array("items", KStr([StrMinLen(1), StrMaxLen(5)]), [ListMinLen(1), ListMaxLen(4)])] }
  match p.round_trip(schema, 30, 7) {
    Ok(30) => Ok(()),
    _ => Err("array round-trip failed"),
  }
}

# ---- Suite --------------------------------------------------------
fn suite() -> List[Result[Unit, Str]] {
  [gen_str_respects_bounds(), gen_int_respects_bounds(), gen_email_format(), gen_uuid_format(), gen_one_of_picks_from_set(), deterministic_per_seed(), round_trip_small_schema(), round_trip_with_array()]
}

fn run_all() -> Int {
  list.fold(suite(), 0, fn (acc :: Int, v :: Result[Unit, Str]) -> Int {
    match v {
      Ok(_) => acc,
      Err(_) => acc + 1,
    }
  })
}

