# Tests for the typed field validators in src/field.lex.

import "std.list" as list

import "std.str" as str

import "std.int" as int

import "../src/constraints" as c

import "../src/error" as e

import "../src/field" as f

# ---- check_str ----------------------------------------------------
fn check_str_ok() -> Result[Unit, Str] {
  match f.check_str("name", "abc", [StrMinLen(1)]) {
    Ok(s) => if s == "abc" {
      Ok(())
    } else {
      Err("value not returned unchanged")
    },
    Err(_) => Err("expected Ok"),
  }
}

# A single field with multiple failing constraints reports ALL of
# them, not just the first.
fn check_str_accumulates_failures() -> Result[Unit, Str] {
  let r := f.check_str("name", "", [StrNonEmpty, StrMinLen(3), StrMaxLen(2)])
  match r {
    Ok(_) => Err("expected Err"),
    Err(es) => if list.len(es) == 2 {
      Ok(())
    } else {
      Err(str.concat("expected 2 errors, got len=", int_to_str_helper(list.len(es))))
    },
  }
}

fn check_str_path_propagates() -> Result[Unit, Str] {
  let r := f.check_str("user.email", "", [StrNonEmpty])
  match r {
    Ok(_) => Err("expected Err"),
    Err(es) => match list.head(es) {
      None => Err("empty error list"),
      Some(err) => if err.path == "user.email" {
        Ok(())
      } else {
        Err(str.concat("wrong path: ", err.path))
      },
    },
  }
}

# ---- check_int ----------------------------------------------------
fn check_int_ok() -> Result[Unit, Str] {
  match f.check_int("age", 25, [IntInRange(0, 130)]) {
    Ok(n) => if n == 25 {
      Ok(())
    } else {
      Err("value changed")
    },
    Err(_) => Err("expected Ok"),
  }
}

fn check_int_below_min() -> Result[Unit, Str] {
  match f.check_int("age", -1, [IntNonNegative]) {
    Ok(_) => Err("expected Err"),
    Err(es) => match list.head(es) {
      None => Err("empty error list"),
      Some(er) => if er.code == "min" {
        Ok(())
      } else {
        Err(str.concat("wrong code: ", er.code))
      },
    },
  }
}

# ---- check_float --------------------------------------------------
fn check_float_finite_passes() -> Result[Unit, Str] {
  match f.check_float("p", 0.5, [FloatFinite, FloatInRange(0.0, 1.0)]) {
    Ok(_) => Ok(()),
    Err(_) => Err("expected Ok"),
  }
}

# ---- validate (custom predicate) ----------------------------------
fn is_lowercase(s :: Str) -> Option[Str] {
  if str.to_lower(s) == s {
    None
  } else {
    Some("must be all lowercase")
  }
}

fn validate_custom_pass() -> Result[Unit, Str] {
  match f.validate("tag", "abc", "lowercase", is_lowercase) {
    Ok(s) => if s == "abc" {
      Ok(())
    } else {
      Err("changed value")
    },
    Err(_) => Err("expected Ok"),
  }
}

fn validate_custom_fail() -> Result[Unit, Str] {
  match f.validate("tag", "ABC", "lowercase", is_lowercase) {
    Ok(_) => Err("expected Err"),
    Err(es) => match list.head(es) {
      None => Err("empty"),
      Some(er) => if er.code == "lowercase" {
        Ok(())
      } else {
        Err(str.concat("wrong code: ", er.code))
      },
    },
  }
}

# ---- Suite runner -------------------------------------------------
fn suite() -> List[Result[Unit, Str]] {
  [check_str_ok(), check_str_accumulates_failures(), check_str_path_propagates(), check_int_ok(), check_int_below_min(), check_float_finite_passes(), validate_custom_pass(), validate_custom_fail()]
}

fn run_all_count() -> Int {
  list.fold(suite(), 0, fn (acc :: Int, v :: Result[Unit, Str]) -> Int {
    match v {
      Ok(_) => acc,
      Err(_) => acc + 1,
    }
  })
}

fn int_to_str_helper(n :: Int) -> Str {
  int.to_str(n)
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

