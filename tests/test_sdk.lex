# Tests for `src/sdk.lex` — TypeScript + Python codegen.

import "std.list" as list

import "std.str" as str

import "../src/error" as e

import "../src/json_value" as jv

import "../src/schema" as s

import "../src/sdk" as sdk

# Two schemas used across the suite.
fn simple_schema() -> s.ModelSchema {
  { title: "User", description: "", fields: [s.required_str("name", [StrMinLen(1), StrMaxLen(80)]), s.required_int("age", [IntInRange(13, 130)]), s.optional(s.required_str("nickname", [StrMaxLen(40)]))] }
}

fn enum_schema() -> s.ModelSchema {
  { title: "Subscription", description: "", fields: [s.required_str("plan", [StrOneOf(["free", "pro", "enterprise"])])] }
}

fn nested_schema() -> s.ModelSchema {
  { title: "Order", description: "", fields: [s.required_str("id", [StrMinLen(1)]), s.required_object("buyer", { title: "Buyer", description: "", fields: [s.required_str("email", [StrEmail])] })] }
}

# ---- TypeScript --------------------------------------------------
fn ts_has_interface_keyword() -> Result[Unit, Str] {
  let out := sdk.to_typescript(simple_schema())
  if str.contains(out, "export interface User") {
    Ok(())
  } else {
    Err("no export interface")
  }
}

fn ts_optional_field_marked() -> Result[Unit, Str] {
  let out := sdk.to_typescript(simple_schema())
  if str.contains(out, "nickname?:") {
    Ok(())
  } else {
    Err(str.concat("no optional marker: ", out))
  }
}

fn ts_required_field_not_marked() -> Result[Unit, Str] {
  let out := sdk.to_typescript(simple_schema())
  if str.contains(out, "name: string") {
    Ok(())
  } else {
    Err("required field missing or marked optional")
  }
}

fn ts_constraint_hint_in_comment() -> Result[Unit, Str] {
  let out := sdk.to_typescript(simple_schema())
  if str.contains(out, "minLength: 1") {
    Ok(())
  } else {
    Err("no constraint hint")
  }
}

fn ts_enum_becomes_union() -> Result[Unit, Str] {
  let out := sdk.to_typescript(enum_schema())
  if str.contains(out, "\"free\" | \"pro\" | \"enterprise\"") {
    Ok(())
  } else {
    Err(str.concat("no union: ", out))
  }
}

fn ts_nested_emitted() -> Result[Unit, Str] {
  let out := sdk.to_typescript(nested_schema())
  if str.contains(out, "interface Order") and str.contains(out, "interface Buyer") and str.contains(out, "buyer: Buyer") {
    Ok(())
  } else {
    Err(str.concat("nested missing: ", out))
  }
}

# ---- Python ------------------------------------------------------
fn py_has_basemodel() -> Result[Unit, Str] {
  let out := sdk.to_python(simple_schema())
  if str.contains(out, "class User(BaseModel)") {
    Ok(())
  } else {
    Err("no class User")
  }
}

fn py_imports_present() -> Result[Unit, Str] {
  let out := sdk.to_python(simple_schema())
  if str.contains(out, "from pydantic import BaseModel, Field") {
    Ok(())
  } else {
    Err("no pydantic import")
  }
}

fn py_optional_uses_Optional() -> Result[Unit, Str] {
  let out := sdk.to_python(simple_schema())
  if str.contains(out, "nickname: Optional[str]") {
    Ok(())
  } else {
    Err(str.concat("optional wrong: ", out))
  }
}

fn py_constraint_args() -> Result[Unit, Str] {
  let out := sdk.to_python(simple_schema())
  if str.contains(out, "ge=13") and str.contains(out, "le=130") {
    Ok(())
  } else {
    Err("missing ge/le")
  }
}

fn py_enum_uses_Literal() -> Result[Unit, Str] {
  let out := sdk.to_python(enum_schema())
  if str.contains(out, "Literal[\"free\", \"pro\", \"enterprise\"]") {
    Ok(())
  } else {
    Err(str.concat("no Literal: ", out))
  }
}

fn py_nested_class_above() -> Result[Unit, Str] {
  let out := sdk.to_python(nested_schema())
  match find_pos(out, "class Buyer") {
    None => Err("no Buyer class"),
    Some(buyer) => match find_pos(out, "class Order") {
      None => Err("no Order class"),
      Some(order) => if buyer < order {
        Ok(())
      } else {
        Err("Buyer must come before Order")
      },
    },
  }
}

# Tiny `indexOf` since std.str doesn't expose one. Walks via
# str.slice + compare; O(n*m) but the test inputs are small.
fn find_pos(haystack :: Str, needle :: Str) -> Option[Int] {
  find_at(haystack, needle, 0)
}

fn find_at(haystack :: Str, needle :: Str, i :: Int) -> Option[Int] {
  let hl := str.len(haystack)
  let nl := str.len(needle)
  if i + nl > hl {
    None
  } else {
    if str.slice(haystack, i, i + nl) == needle {
      Some(i)
    } else {
      find_at(haystack, needle, i + 1)
    }
  }
}

# ---- Suite --------------------------------------------------------
fn suite() -> List[Result[Unit, Str]] {
  [ts_has_interface_keyword(), ts_optional_field_marked(), ts_required_field_not_marked(), ts_constraint_hint_in_comment(), ts_enum_becomes_union(), ts_nested_emitted(), py_has_basemodel(), py_imports_present(), py_optional_uses_Optional(), py_constraint_args(), py_enum_uses_Literal(), py_nested_class_above()]
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

