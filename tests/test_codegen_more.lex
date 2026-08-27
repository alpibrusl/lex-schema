# Tests for the v0.8.1 additions to `src/sdk.lex` and
# `src/schema.lex`: Go-struct codegen and Mermaid ER export.

import "std.list" as list

import "std.str" as str

import "../src/error" as e

import "../src/schema" as s

import "../src/sdk" as sdk

fn user_schema() -> s.ModelSchema {
  { title: "User", description: "", fields: [s.required_str("name", [StrMinLen(1), StrMaxLen(80)]), s.required_str("email", [StrEmail]), s.required_int("age", [IntInRange(13, 130)]), s.optional(s.required_str("nickname", [StrMaxLen(40)]))] }
}

fn nested_schema() -> s.ModelSchema {
  { title: "Order", description: "", fields: [s.required_str("id", []), s.required_object("buyer", { title: "Buyer", description: "", fields: [s.required_str("email", [StrEmail])] })] }
}

# ---- Go codegen --------------------------------------------------
fn go_package_decl() -> Result[Unit, Str] {
  let out := sdk.to_go_struct(user_schema())
  if str.contains(out, "package models") {
    Ok(())
  } else {
    Err("no package decl")
  }
}

fn go_struct_def() -> Result[Unit, Str] {
  let out := sdk.to_go_struct(user_schema())
  if str.contains(out, "type User struct {") {
    Ok(())
  } else {
    Err("no struct")
  }
}

fn go_json_tag() -> Result[Unit, Str] {
  let out := sdk.to_go_struct(user_schema())
  if str.contains(out, "`json:\"name\"`") {
    Ok(())
  } else {
    Err("no json tag")
  }
}

fn go_optional_omitempty() -> Result[Unit, Str] {
  let out := sdk.to_go_struct(user_schema())
  if str.contains(out, "*string") and str.contains(out, "omitempty") {
    Ok(())
  } else {
    Err("optional shape wrong")
  }
}

fn go_pascalcase_field() -> Result[Unit, Str] {
  let schema := { title: "X", description: "", fields: [s.required_str("user_name", [])] }
  let out := sdk.to_go_struct(schema)
  if str.contains(out, "UserName") {
    Ok(())
  } else {
    Err(str.concat("expected UserName: ", out))
  }
}

fn go_nested_emitted() -> Result[Unit, Str] {
  let out := sdk.to_go_struct(nested_schema())
  if str.contains(out, "type Order struct {") and str.contains(out, "type Buyer struct {") and str.contains(out, "Buyer Buyer") {
    Ok(())
  } else {
    Err("nested missing")
  }
}

fn go_int_type() -> Result[Unit, Str] {
  let out := sdk.to_go_struct(user_schema())
  if str.contains(out, "int64") {
    Ok(())
  } else {
    Err("int type wrong")
  }
}

# ---- Mermaid ER --------------------------------------------------
fn mermaid_has_header() -> Result[Unit, Str] {
  let out := s.to_mermaid_er(user_schema())
  if str.starts_with(out, "erDiagram") {
    Ok(())
  } else {
    Err("missing erDiagram header")
  }
}

fn mermaid_columns() -> Result[Unit, Str] {
  let out := s.to_mermaid_er(user_schema())
  if str.contains(out, "string name") and str.contains(out, "string email") and str.contains(out, "int age") {
    Ok(())
  } else {
    Err("columns missing")
  }
}

fn mermaid_optional_marked() -> Result[Unit, Str] {
  let out := s.to_mermaid_er(user_schema())
  if str.contains(out, "\"optional\"") {
    Ok(())
  } else {
    Err("no optional marker")
  }
}

fn mermaid_nested_relationship() -> Result[Unit, Str] {
  let out := s.to_mermaid_er(nested_schema())
  if str.contains(out, "Order ||--|| Buyer : buyer") {
    Ok(())
  } else {
    Err(str.concat("missing rel: ", out))
  }
}

fn mermaid_array_relationship() -> Result[Unit, Str] {
  let sch := { title: "Box", description: "", fields: [s.required_array("items", KObject({ title: "Item", description: "", fields: [s.required_str("name", [])] }), [])] }
  let out := s.to_mermaid_er(sch)
  if str.contains(out, "Box ||--o{ Item : items") {
    Ok(())
  } else {
    Err(str.concat("missing array rel: ", out))
  }
}

# ---- Suite -------------------------------------------------------
fn suite() -> List[Result[Unit, Str]] {
  [go_package_decl(), go_struct_def(), go_json_tag(), go_optional_omitempty(), go_pascalcase_field(), go_nested_emitted(), go_int_type(), mermaid_has_header(), mermaid_columns(), mermaid_optional_marked(), mermaid_nested_relationship(), mermaid_array_relationship()]
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

