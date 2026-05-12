# Tests for the v0.7.x additions to `src/sdk.lex`: Zod + Rust.

import "std.list" as list
import "std.str"  as str

import "../src/error"  as e
import "../src/schema" as s
import "../src/sdk"    as sdk

fn user_schema() -> s.ModelSchema {
  {
    title: "User", description: "",
    fields: [
      s.required_str("name",  [StrMinLen(1), StrMaxLen(80)]),
      s.required_str("email", [StrEmail]),
      s.required_int("age",   [IntInRange(13, 130)]),
      s.optional(s.required_str("nickname", [StrMaxLen(40)])),
    ],
  }
}

# ---- Zod ----------------------------------------------------------

fn zod_has_import() -> Result[Unit, Str] {
  let out := sdk.to_zod(user_schema())
  if str.contains(out, "import { z } from \"zod\";") { Ok(()) }
  else { Err("no zod import") }
}

fn zod_object_call() -> Result[Unit, Str] {
  let out := sdk.to_zod(user_schema())
  if str.contains(out, "export const User = z.object({") { Ok(()) }
  else { Err("no z.object") }
}

fn zod_email_chain() -> Result[Unit, Str] {
  let out := sdk.to_zod(user_schema())
  if str.contains(out, ".email()") { Ok(()) }
  else { Err("no .email() chain") }
}

fn zod_int_range() -> Result[Unit, Str] {
  let out := sdk.to_zod(user_schema())
  if str.contains(out, "z.number().int()") and str.contains(out, ".min(13).max(130)") {
    Ok(())
  } else { Err(str.concat("missing int chain: ", out)) }
}

fn zod_optional_field() -> Result[Unit, Str] {
  let out := sdk.to_zod(user_schema())
  if str.contains(out, ".optional()") { Ok(()) }
  else { Err("no .optional()") }
}

# ---- Rust ---------------------------------------------------------

fn rust_has_serde_import() -> Result[Unit, Str] {
  let out := sdk.to_rust_struct(user_schema())
  if str.contains(out, "use serde::{Deserialize, Serialize};") { Ok(()) }
  else { Err("no serde import") }
}

fn rust_struct_def() -> Result[Unit, Str] {
  let out := sdk.to_rust_struct(user_schema())
  if str.contains(out, "pub struct User {") { Ok(()) }
  else { Err("no struct def") }
}

fn rust_derives() -> Result[Unit, Str] {
  let out := sdk.to_rust_struct(user_schema())
  if str.contains(out, "#[derive(Debug, Clone, Serialize, Deserialize)]") { Ok(()) }
  else { Err("no derives") }
}

fn rust_optional_uses_Option() -> Result[Unit, Str] {
  let out := sdk.to_rust_struct(user_schema())
  if str.contains(out, "Option<String>") and str.contains(out, "#[serde(default)]") {
    Ok(())
  } else { Err("optional not wrapped") }
}

fn rust_types_correct() -> Result[Unit, Str] {
  let out := sdk.to_rust_struct(user_schema())
  if str.contains(out, "pub name: String,")
    and str.contains(out, "pub age: i64,")
  { Ok(()) }
  else { Err("wrong field types") }
}

# ---- Suite --------------------------------------------------------

fn suite() -> List[Result[Unit, Str]] {
  [
    zod_has_import(),
    zod_object_call(),
    zod_email_chain(),
    zod_int_range(),
    zod_optional_field(),
    rust_has_serde_import(),
    rust_struct_def(),
    rust_derives(),
    rust_optional_uses_Option(),
    rust_types_correct(),
  ]
}

fn run_all() -> Int {
  list.fold(suite(), 0, fn (acc :: Int, v :: Result[Unit, Str]) -> Int {
    match v { Ok(_) => acc, Err(_) => acc + 1 }
  })
}
