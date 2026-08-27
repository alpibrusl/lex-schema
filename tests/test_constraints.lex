# Tests for the constraint evaluators. Each test exercises both the
# pass and fail branch of a `StrCheck` / `IntCheck` / `FloatCheck` /
# `ListCheck` so the message format stays pinned.
#
# A test is a `() -> Result[Unit, Str]`. The runner at the bottom
# collects every verdict and reports the first failure (or a pass
# count).

import "std.test" as test

import "std.list" as list

import "std.str" as str

import "../src/constraints" as c

import "../src/error" as e

# ---- StrCheck -----------------------------------------------------
fn str_nonempty_passes() -> Result[Unit, Str] {
  match c.eval_str(StrNonEmpty, "x") {
    None => Ok(()),
    Some(m) => Err(str.concat("expected None, got Some(", str.concat(m, ")"))),
  }
}

fn str_nonempty_fails() -> Result[Unit, Str] {
  match c.eval_str(StrNonEmpty, "") {
    None => Err("expected Some(...), got None"),
    Some(_) => Ok(()),
  }
}

fn str_minlen_passes() -> Result[Unit, Str] {
  match c.eval_str(StrMinLen(3), "abc") {
    None => Ok(()),
    Some(_) => Err("3-char string should pass min_len(3)"),
  }
}

fn str_minlen_fails() -> Result[Unit, Str] {
  match c.eval_str(StrMinLen(3), "ab") {
    None => Err("2-char string should fail min_len(3)"),
    Some(_) => Ok(()),
  }
}

fn str_maxlen_fails() -> Result[Unit, Str] {
  match c.eval_str(StrMaxLen(2), "abc") {
    None => Err("3-char string should fail max_len(2)"),
    Some(_) => Ok(()),
  }
}

fn str_pattern_email_ok() -> Result[Unit, Str] {
  match c.eval_str(StrEmail, "a@b.co") {
    None => Ok(()),
    Some(_) => Err("a@b.co should be a valid email"),
  }
}

fn str_pattern_email_bad() -> Result[Unit, Str] {
  match c.eval_str(StrEmail, "not-an-email") {
    None => Err("not-an-email should fail email check"),
    Some(_) => Ok(()),
  }
}

fn str_pattern_url_ok() -> Result[Unit, Str] {
  match c.eval_str(StrUrl, "https://example.com/path") {
    None => Ok(()),
    Some(_) => Err("https://example.com/path should be a valid URL"),
  }
}

fn str_one_of_passes() -> Result[Unit, Str] {
  match c.eval_str(StrOneOf(["a", "b", "c"]), "b") {
    None => Ok(()),
    Some(_) => Err("b should be in {a,b,c}"),
  }
}

fn str_one_of_fails() -> Result[Unit, Str] {
  match c.eval_str(StrOneOf(["a", "b", "c"]), "d") {
    None => Err("d should not be in {a,b,c}"),
    Some(_) => Ok(()),
  }
}

# ---- IntCheck -----------------------------------------------------
fn int_min_passes() -> Result[Unit, Str] {
  match c.eval_int(IntMin(0), 0) {
    None => Ok(()),
    Some(_) => Err("0 should pass IntMin(0)"),
  }
}

fn int_min_fails() -> Result[Unit, Str] {
  match c.eval_int(IntMin(1), 0) {
    None => Err("0 should fail IntMin(1)"),
    Some(_) => Ok(()),
  }
}

fn int_positive_zero_fails() -> Result[Unit, Str] {
  match c.eval_int(IntPositive, 0) {
    None => Err("0 should fail IntPositive"),
    Some(_) => Ok(()),
  }
}

fn int_in_range_below() -> Result[Unit, Str] {
  match c.eval_int(IntInRange(10, 20), 5) {
    None => Err("5 should fail IntInRange(10,20)"),
    Some(_) => Ok(()),
  }
}

fn int_in_range_above() -> Result[Unit, Str] {
  match c.eval_int(IntInRange(10, 20), 25) {
    None => Err("25 should fail IntInRange(10,20)"),
    Some(_) => Ok(()),
  }
}

fn int_in_range_inside() -> Result[Unit, Str] {
  match c.eval_int(IntInRange(10, 20), 15) {
    None => Ok(()),
    Some(_) => Err("15 should pass IntInRange(10,20)"),
  }
}

# ---- FloatCheck ---------------------------------------------------
fn float_min_passes() -> Result[Unit, Str] {
  match c.eval_float(FloatMin(0.0), 0.5) {
    None => Ok(()),
    Some(_) => Err("0.5 should pass FloatMin(0.0)"),
  }
}

fn float_non_negative_negative_fails() -> Result[Unit, Str] {
  match c.eval_float(FloatNonNegative, -0.001) {
    None => Err("-0.001 should fail FloatNonNegative"),
    Some(_) => Ok(()),
  }
}

# ---- ListCheck ----------------------------------------------------
fn list_nonempty_pass() -> Result[Unit, Str] {
  match c.eval_list(ListNonEmpty, 1) {
    None => Ok(()),
    Some(_) => Err("len 1 should pass ListNonEmpty"),
  }
}

fn list_nonempty_fail() -> Result[Unit, Str] {
  match c.eval_list(ListNonEmpty, 0) {
    None => Err("len 0 should fail ListNonEmpty"),
    Some(_) => Ok(()),
  }
}

fn list_max_fail() -> Result[Unit, Str] {
  match c.eval_list(ListMaxLen(2), 5) {
    None => Err("len 5 should fail ListMaxLen(2)"),
    Some(_) => Ok(()),
  }
}

# ---- Test suite ---------------------------------------------------
fn suite() -> List[Result[Unit, Str]] {
  [str_nonempty_passes(), str_nonempty_fails(), str_minlen_passes(), str_minlen_fails(), str_maxlen_fails(), str_pattern_email_ok(), str_pattern_email_bad(), str_pattern_url_ok(), str_one_of_passes(), str_one_of_fails(), int_min_passes(), int_min_fails(), int_positive_zero_fails(), int_in_range_below(), int_in_range_above(), int_in_range_inside(), float_min_passes(), float_non_negative_negative_fails(), list_nonempty_pass(), list_nonempty_fail(), list_max_fail()]
}

# Returns the number of failures across the suite. `0` means clean.
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

