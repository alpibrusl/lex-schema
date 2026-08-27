# Tests for `src/coerce.lex`.

import "std.list" as list

import "std.str" as str

import "std.map" as map

import "../src/error" as e

import "../src/constraints" as c

import "../src/coerce" as coerce

# ---- coerce_str_to_int --------------------------------------------
fn coerce_int_ok() -> Result[Unit, Str] {
  match coerce.coerce_str_to_int("p", "42") {
    Ok(42) => Ok(()),
    Ok(_) => Err("wrong int"),
    Err(_) => Err("expected Ok"),
  }
}

fn coerce_int_trims() -> Result[Unit, Str] {
  match coerce.coerce_str_to_int("p", "  42  ") {
    Ok(42) => Ok(()),
    Ok(_) => Err("wrong int"),
    Err(_) => Err("expected Ok after trim"),
  }
}

fn coerce_int_fails() -> Result[Unit, Str] {
  match coerce.coerce_str_to_int("p", "thirty") {
    Ok(_) => Err("expected Err"),
    Err(es) => match list.head(es) {
      None => Err("empty"),
      Some(er) => if er.code == "type" {
        Ok(())
      } else {
        Err(str.concat("wrong code: ", er.code))
      },
    },
  }
}

# ---- coerce_str_to_bool -------------------------------------------
fn coerce_bool_true_words() -> Result[Unit, Str] {
  let words := ["true", "1", "yes", "on", "y", "t", "TRUE", "Yes"]
  let fails := list.fold(words, 0, fn (acc :: Int, w :: Str) -> Int {
    match coerce.coerce_str_to_bool("p", w) {
      Ok(true) => acc,
      Ok(false) => acc + 1,
      Err(_) => acc + 1,
    }
  })
  if fails == 0 {
    Ok(())
  } else {
    Err("at least one truthy word failed")
  }
}

fn coerce_bool_false_words() -> Result[Unit, Str] {
  let words := ["false", "0", "no", "off", "n", "f"]
  let fails := list.fold(words, 0, fn (acc :: Int, w :: Str) -> Int {
    match coerce.coerce_str_to_bool("p", w) {
      Ok(false) => acc,
      Ok(true) => acc + 1,
      Err(_) => acc + 1,
    }
  })
  if fails == 0 {
    Ok(())
  } else {
    Err("at least one falsy word failed")
  }
}

fn coerce_bool_bad() -> Result[Unit, Str] {
  match coerce.coerce_str_to_bool("p", "maybe") {
    Ok(_) => Err("expected Err"),
    Err(es) => if list.len(es) == 1 {
      Ok(())
    } else {
      Err("wrong count")
    },
  }
}

# ---- check_str_as_int (coerce + validate together) ---------------
fn check_str_as_int_combines_errors() -> Result[Unit, Str] {
  match coerce.check_str_as_int("p", "42", [IntMin(100)]) {
    Ok(_) => Err("expected Err"),
    Err(es) => match list.head(es) {
      None => Err("empty"),
      Some(er) => if er.code == "min" {
        Ok(())
      } else {
        Err(str.concat("wrong code: ", er.code))
      },
    },
  }
}

fn check_str_as_int_coerce_fails_first() -> Result[Unit, Str] {
  match coerce.check_str_as_int("p", "xx", [IntMin(100)]) {
    Ok(_) => Err("expected Err"),
    Err(es) => match list.head(es) {
      None => Err("empty"),
      Some(er) => if er.code == "type" {
        Ok(())
      } else {
        Err(str.concat("wrong code: ", er.code))
      },
    },
  }
}

# ---- require/optional from Map -----------------------------------
fn require_int_present() -> Result[Unit, Str] {
  let m := map.from_list([("k", "42")])
  match coerce.require_int_from_map(m, "k", [IntPositive]) {
    Ok(42) => Ok(()),
    Ok(_) => Err("wrong int"),
    Err(_) => Err("expected Ok"),
  }
}

fn require_int_missing() -> Result[Unit, Str] {
  let m :: Map[Str, Str] := map.new()
  match coerce.require_int_from_map(m, "k", []) {
    Ok(_) => Err("expected Err"),
    Err(es) => match list.head(es) {
      None => Err("empty"),
      Some(er) => if er.code == "missing" {
        Ok(())
      } else {
        Err(str.concat("wrong code: ", er.code))
      },
    },
  }
}

fn optional_int_absent_ok() -> Result[Unit, Str] {
  let m :: Map[Str, Str] := map.new()
  match coerce.optional_int_from_map(m, "k", []) {
    Ok(None) => Ok(()),
    Ok(Some(_)) => Err("expected None"),
    Err(_) => Err("expected Ok(None)"),
  }
}

fn optional_int_present_ok() -> Result[Unit, Str] {
  let m := map.from_list([("k", "7")])
  match coerce.optional_int_from_map(m, "k", [IntPositive]) {
    Ok(Some(7)) => Ok(()),
    Ok(Some(_)) => Err("wrong int"),
    Ok(None) => Err("expected Some"),
    Err(_) => Err("expected Ok"),
  }
}

# ---- Suite --------------------------------------------------------
fn suite() -> List[Result[Unit, Str]] {
  [coerce_int_ok(), coerce_int_trims(), coerce_int_fails(), coerce_bool_true_words(), coerce_bool_false_words(), coerce_bool_bad(), check_str_as_int_combines_errors(), check_str_as_int_coerce_fails_first(), require_int_present(), require_int_missing(), optional_int_absent_ok(), optional_int_present_ok()]
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

