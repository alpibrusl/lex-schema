# Tests for `sdk.to_sql_ddl` — Postgres + SQLite DDL codegen.

import "std.list" as list

import "std.str" as str

import "../src/schema" as s

import "../src/sdk" as sdk

fn user_schema() -> s.ModelSchema {
  { title: "User", description: "Application user", fields: [s.required_str("id", [StrUuid]), s.required_str("name", [StrMinLen(1), StrMaxLen(80)]), s.required_str("email", [StrEmail]), s.required_int("age", [IntInRange(13, 130)]), s.optional(s.required_str("nickname", [StrMaxLen(40)]))] }
}

fn nested_schema() -> s.ModelSchema {
  { title: "Order", description: "", fields: [s.required_str("id", []), s.required_str("status", [StrOneOf(["pending", "shipped", "delivered"])]), s.required_object("buyer", { title: "Buyer", description: "", fields: [s.required_str("id", []), s.required_str("email", [StrEmail])] })] }
}

# ---- Postgres ----------------------------------------------------
fn pg(s :: s.ModelSchema) -> Str {
  sdk.to_sql_ddl(s, DialectPostgres)
}

fn pg_create_table() -> Result[Unit, Str] {
  let out := pg(user_schema())
  if str.contains(out, "CREATE TABLE \"user\"") {
    Ok(())
  } else {
    Err(str.concat("no CREATE TABLE: ", out))
  }
}

fn pg_id_primary_key() -> Result[Unit, Str] {
  let out := pg(user_schema())
  if str.contains(out, "id ") and str.contains(out, "PRIMARY KEY") {
    Ok(())
  } else {
    Err("no PK")
  }
}

fn pg_varchar_with_maxlen() -> Result[Unit, Str] {
  let out := pg(user_schema())
  if str.contains(out, "VARCHAR(80)") {
    Ok(())
  } else {
    Err(str.concat("no VARCHAR(80): ", out))
  }
}

fn pg_text_without_maxlen() -> Result[Unit, Str] {
  let schema := { title: "X", description: "", fields: [s.required_str("note", [])] }
  let out := pg(schema)
  if str.contains(out, "TEXT") {
    Ok(())
  } else {
    Err("no TEXT")
  }
}

fn pg_bigint() -> Result[Unit, Str] {
  let out := pg(user_schema())
  if str.contains(out, "BIGINT") {
    Ok(())
  } else {
    Err("no BIGINT")
  }
}

fn pg_not_null_when_required() -> Result[Unit, Str] {
  let out := pg(user_schema())
  if str.contains(out, "name VARCHAR(80) NOT NULL") or str.contains(out, "name VARCHAR(80)  NOT NULL") {
    Ok(())
  } else {
    Err(str.concat("no NOT NULL: ", out))
  }
}

fn pg_nullable_when_optional() -> Result[Unit, Str] {
  let out := pg(user_schema())
  let lines := str.split(out, "\n")
  let nick := list.fold(lines, "", fn (acc :: Str, line :: Str) -> Str {
    if str.contains(line, "nickname") {
      line
    } else {
      acc
    }
  })
  if str.is_empty(nick) {
    Err("no nickname line")
  } else {
    if str.contains(nick, "NOT NULL") {
      Err(str.concat("had NOT NULL: ", nick))
    } else {
      Ok(())
    }
  }
}

fn pg_range_check() -> Result[Unit, Str] {
  let out := pg(user_schema())
  if str.contains(out, "age BETWEEN 13 AND 130") {
    Ok(())
  } else {
    Err(str.concat("no BETWEEN: ", out))
  }
}

fn pg_min_len_check() -> Result[Unit, Str] {
  let out := pg(user_schema())
  if str.contains(out, "length(name) >= 1") {
    Ok(())
  } else {
    Err(str.concat("no min len check: ", out))
  }
}

fn pg_email_regex() -> Result[Unit, Str] {
  let out := pg(user_schema())
  if str.contains(out, "email ~ '") {
    Ok(())
  } else {
    Err(str.concat("no email regex: ", out))
  }
}

fn pg_uuid_regex() -> Result[Unit, Str] {
  let out := pg(user_schema())
  if str.contains(out, "id ~ '") {
    Ok(())
  } else {
    Err("no uuid regex")
  }
}

fn pg_one_of_in() -> Result[Unit, Str] {
  let out := pg(nested_schema())
  if str.contains(out, "status IN ('pending', 'shipped', 'delivered')") {
    Ok(())
  } else {
    Err(str.concat("no IN: ", out))
  }
}

fn pg_nested_emits_buyer_first() -> Result[Unit, Str] {
  let out := pg(nested_schema())
  let buyer_pos := substr_pos(out, "CREATE TABLE \"buyer\"")
  let order_pos := substr_pos(out, "CREATE TABLE \"order\"")
  match buyer_pos {
    None => Err("no buyer table"),
    Some(b) => match order_pos {
      None => Err("no order table"),
      Some(o) => if b < o {
        Ok(())
      } else {
        Err("buyer must precede order")
      },
    },
  }
}

fn pg_nested_fk_reference() -> Result[Unit, Str] {
  let out := pg(nested_schema())
  if str.contains(out, "buyer_id BIGINT") and str.contains(out, "REFERENCES \"buyer\"(id)") {
    Ok(())
  } else {
    Err(str.concat("no FK: ", out))
  }
}

fn pg_array_jsonb() -> Result[Unit, Str] {
  let schema := { title: "Cart", description: "", fields: [s.required_str("id", []), s.required_array("items", KStr([]), [])] }
  let out := pg(schema)
  if str.contains(out, "items JSONB") {
    Ok(())
  } else {
    Err(str.concat("no JSONB: ", out))
  }
}

fn pg_float_double_precision() -> Result[Unit, Str] {
  let schema := { title: "X", description: "", fields: [s.required_float("price", [FloatPositive])] }
  let out := pg(schema)
  if str.contains(out, "DOUBLE PRECISION") and str.contains(out, "price > 0") {
    Ok(())
  } else {
    Err(str.concat("missing float bits: ", out))
  }
}

fn pg_bool_boolean() -> Result[Unit, Str] {
  let schema := { title: "X", description: "", fields: [s.required_bool("active")] }
  let out := pg(schema)
  if str.contains(out, "active BOOLEAN") {
    Ok(())
  } else {
    Err(str.concat("no BOOLEAN: ", out))
  }
}

fn pg_pascalcase_title_to_snake() -> Result[Unit, Str] {
  let schema := { title: "UserAccount", description: "", fields: [s.required_str("id", [])] }
  let out := pg(schema)
  if str.contains(out, "CREATE TABLE \"user_account\"") {
    Ok(())
  } else {
    Err(str.concat("no snake table name: ", out))
  }
}

# ---- SQLite ------------------------------------------------------
fn sqlite(s :: s.ModelSchema) -> Str {
  sdk.to_sql_ddl(s, DialectSqlite)
}

fn sqlite_integer_for_int() -> Result[Unit, Str] {
  let out := sqlite(user_schema())
  if str.contains(out, "age INTEGER") {
    Ok(())
  } else {
    Err(str.concat("no INTEGER: ", out))
  }
}

fn sqlite_text_for_str() -> Result[Unit, Str] {
  let out := sqlite(user_schema())
  if str.contains(out, "name TEXT") and not str.contains(out, "VARCHAR") {
    Ok(())
  } else {
    Err(str.concat("VARCHAR leaked: ", out))
  }
}

fn sqlite_bool_as_integer() -> Result[Unit, Str] {
  let schema := { title: "X", description: "", fields: [s.required_bool("active")] }
  let out := sqlite(schema)
  if str.contains(out, "active INTEGER") {
    Ok(())
  } else {
    Err(str.concat("no INTEGER bool: ", out))
  }
}

fn sqlite_no_regex_check() -> Result[Unit, Str] {
  let out := sqlite(user_schema())
  if not str.contains(out, " ~ ") {
    Ok(())
  } else {
    Err("regex leaked into sqlite")
  }
}

fn sqlite_in_list_still_works() -> Result[Unit, Str] {
  let out := sqlite(nested_schema())
  if str.contains(out, "status IN ('pending', 'shipped', 'delivered')") {
    Ok(())
  } else {
    Err(str.concat("no IN: ", out))
  }
}

# ---- Helpers -----------------------------------------------------
fn substr_pos(haystack :: Str, needle :: Str) -> Option[Int] {
  substr_pos_at(haystack, needle, 0, str.len(haystack) - str.len(needle))
}

fn substr_pos_at(h :: Str, n :: Str, i :: Int, last :: Int) -> Option[Int] {
  if i > last {
    None
  } else {
    if str.slice(h, i, i + str.len(n)) == n {
      Some(i)
    } else {
      substr_pos_at(h, n, i + 1, last)
    }
  }
}

# ---- Suite -------------------------------------------------------
fn suite() -> List[Result[Unit, Str]] {
  [pg_create_table(), pg_id_primary_key(), pg_varchar_with_maxlen(), pg_text_without_maxlen(), pg_bigint(), pg_not_null_when_required(), pg_nullable_when_optional(), pg_range_check(), pg_min_len_check(), pg_email_regex(), pg_uuid_regex(), pg_one_of_in(), pg_nested_emits_buyer_first(), pg_nested_fk_reference(), pg_array_jsonb(), pg_float_double_precision(), pg_bool_boolean(), pg_pascalcase_title_to_snake(), sqlite_integer_for_int(), sqlite_text_for_str(), sqlite_bool_as_integer(), sqlite_no_regex_check(), sqlite_in_list_still_works()]
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

