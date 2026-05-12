# Tests for `src/migrate.lex` — schema migrations + compat check.

import "std.list" as list
import "std.str"  as str

import "../src/error"      as e
import "../src/json_value" as jv
import "../src/schema"     as s
import "../src/migrate"    as m

# Tiny helper to load test payloads.
fn parse(text :: Str) -> jv.Json {
  match jv.parse(text) { Ok(j) => j, Err(_) => JNull }
}

# ---- Rename --------------------------------------------------------

fn rename_works() -> Result[Unit, Str] {
  let p := parse("{\"firstName\":\"alice\"}")
  let out := m.apply(p, [Rename({ from: "firstName", to: "first_name" })])
  match jv.get_field(out, "first_name") {
    Some(JStr("alice")) => Ok(()),
    _ => Err("rename failed"),
  }
}

# ---- DropField -----------------------------------------------------

fn drop_removes() -> Result[Unit, Str] {
  let p := parse("{\"a\":1,\"b\":2}")
  let out := m.apply(p, [DropField("a")])
  match jv.get_field(out, "a") {
    None    => Ok(()),
    Some(_) => Err("not dropped"),
  }
}

# ---- AddField ------------------------------------------------------

fn add_when_absent() -> Result[Unit, Str] {
  let p := parse("{\"a\":1}")
  let out := m.apply(p, [AddField({ name: "b", default: JStr("hello") })])
  match jv.get_field(out, "b") {
    Some(JStr("hello")) => Ok(()),
    _ => Err("add failed"),
  }
}

fn add_skips_when_present() -> Result[Unit, Str] {
  let p := parse("{\"a\":1,\"b\":\"original\"}")
  let out := m.apply(p, [AddField({ name: "b", default: JStr("new") })])
  match jv.get_field(out, "b") {
    Some(JStr("original")) => Ok(()),
    _ => Err("overwrote existing value"),
  }
}

# ---- Coerce --------------------------------------------------------

fn coerce_int() -> Result[Unit, Str] {
  let p := parse("{\"age\":\"42\"}")
  let out := m.apply(p, [CoerceStrToInt("age")])
  match jv.get_field(out, "age") {
    Some(JInt(42)) => Ok(()),
    _ => Err("not coerced"),
  }
}

fn coerce_bad_drops() -> Result[Unit, Str] {
  let p := parse("{\"age\":\"x\"}")
  let out := m.apply(p, [CoerceStrToInt("age")])
  match jv.get_field(out, "age") {
    None    => Ok(()),
    Some(_) => Err("should be dropped"),
  }
}

# ---- Chained transforms -------------------------------------------

fn chained() -> Result[Unit, Str] {
  let p := parse("{\"firstName\":\"alice\",\"lastName\":\"smith\",\"age\":\"29\"}")
  let out := m.apply(p, [
    Rename({ from: "firstName", to: "first_name" }),
    Rename({ from: "lastName",  to: "last_name" }),
    CoerceStrToInt("age"),
    NestInto({ name: "name", fields: ["first_name", "last_name"] }),
  ])
  # Should end up: {"age": 29, "name": {"first_name": ..., "last_name": ...}}
  match jv.get_field(out, "age") {
    Some(JInt(29)) => match jv.get_field(out, "name") {
      Some(name) => match jv.get_field(name, "first_name") {
        Some(JStr("alice")) => Ok(()),
        _ => Err("first_name not nested"),
      },
      _ => Err("name absent"),
    },
    _ => Err("age not coerced"),
  }
}

# ---- Compat check --------------------------------------------------

fn compat_identical_schemas() -> Result[Unit, Str] {
  let sch := { title: "X", description: "",
    fields: [s.required_str("a", [])] }
  match m.is_backward_compatible(sch, sch) {
    Ok(_)  => Ok(()),
    Err(_) => Err("identical should be compatible"),
  }
}

fn compat_added_required_breaks() -> Result[Unit, Str] {
  let old := { title: "X", description: "",
    fields: [s.required_str("a", [])] }
  let new := { title: "X", description: "",
    fields: [
      s.required_str("a", []),
      s.required_str("b", []),
    ] }
  match m.is_backward_compatible(old, new) {
    Ok(_)   => Err("should be incompatible"),
    Err(is) => if list.len(is) == 1 { Ok(()) }
               else { Err("expected 1 issue") },
  }
}

fn compat_added_optional_ok() -> Result[Unit, Str] {
  let old := { title: "X", description: "",
    fields: [s.required_str("a", [])] }
  let new := { title: "X", description: "",
    fields: [
      s.required_str("a", []),
      s.optional(s.required_str("b", [])),
    ] }
  match m.is_backward_compatible(old, new) {
    Ok(_)  => Ok(()),
    Err(_) => Err("adding optional should be ok"),
  }
}

fn compat_type_changed_breaks() -> Result[Unit, Str] {
  let old := { title: "X", description: "",
    fields: [s.required_str("a", [])] }
  let new := { title: "X", description: "",
    fields: [s.required_int("a", [])] }
  match m.is_backward_compatible(old, new) {
    Ok(_)   => Err("should be incompatible"),
    Err(_)  => Ok(()),
  }
}

fn compat_field_became_required_breaks() -> Result[Unit, Str] {
  let old := { title: "X", description: "",
    fields: [s.optional(s.required_str("a", []))] }
  let new := { title: "X", description: "",
    fields: [s.required_str("a", [])] }
  match m.is_backward_compatible(old, new) {
    Ok(_)  => Err("optional → required should break"),
    Err(_) => Ok(()),
  }
}

# ---- Suite ---------------------------------------------------------

fn suite() -> List[Result[Unit, Str]] {
  [
    rename_works(),
    drop_removes(),
    add_when_absent(),
    add_skips_when_present(),
    coerce_int(),
    coerce_bad_drops(),
    chained(),
    compat_identical_schemas(),
    compat_added_required_breaks(),
    compat_added_optional_ok(),
    compat_type_changed_breaks(),
    compat_field_became_required_breaks(),
  ]
}

fn run_all() -> Int {
  list.fold(suite(), 0, fn (acc :: Int, v :: Result[Unit, Str]) -> Int {
    match v { Ok(_) => acc, Err(_) => acc + 1 }
  })
}
