# Tests for `src/fuzz.lex` — the malformed-input fuzz driver.
#
# The pass condition is the same one the example demonstrates:
# every catalogue, every input, surfaces as `Err` rather than
# escaping as `Ok` or panicking. We verify it from three angles:
# total escapes, per-category 100% coverage, and that the
# format renders the expected shape.

import "std.list" as list

import "std.str" as str

import "std.int" as int

import "../src/error" as e

import "../src/schema" as s

import "../src/fuzz" as fz

fn fixture_schema() -> s.ModelSchema {
  { title: "User", description: "", fields: [s.required_str("name", [StrMinLen(1), StrMaxLen(80)]), s.required_int("age", [IntInRange(13, 130)])] }
}

fn int_to_str(n :: Int) -> Str {
  int.to_str(n)
}

fn zero_escapes() -> Result[Unit, Str] {
  match fz.count_escapes(fixture_schema()) {
    0 => Ok(()),
    n => Err(str.concat("escapes: ", int_to_str(n))),
  }
}

fn every_category_100pct() -> Result[Unit, Str] {
  let tallies := fz.run_all(fixture_schema())
  let bad := list.fold(tallies, 0, accumulate_escapes)
  if bad == 0 {
    Ok(())
  } else {
    Err("a category had escapes")
  }
}

# Lifted out of the fold closure: lex-lang#337's stack-leak hits
# when a record-field access happens inside a list.fold reducer
# closure whose RHS reads more than one field of the same value.
fn accumulate_escapes(acc :: Int, t :: fz.Tally) -> Int {
  acc + t.total - t.errored
}

fn format_includes_every_category() -> Result[Unit, Str] {
  let s := fz.format_tallies(fz.run_all(fixture_schema()))
  if str.contains(s, "parse_failures:") and str.contains(s, "type_mismatches:") and str.contains(s, "missing_required:") and str.contains(s, "constraint_failures:") and str.contains(s, "deep_nesting:") {
    Ok(())
  } else {
    Err("missing categories in format")
  }
}

# Property: corpus is non-empty. Easy to regress by accidentally
# clearing a category; the test pins the seed surface.
fn corpus_non_empty() -> Result[Unit, Str] {
  let tallies := fz.run_all(fixture_schema())
  let total := list.fold(tallies, 0, sum_total)
  if total >= 20 {
    Ok(())
  } else {
    Err(str.concat("fuzz corpus too small: ", int_to_str(total)))
  }
}

fn sum_total(acc :: Int, t :: fz.Tally) -> Int {
  acc + t.total
}

# ---- Suite --------------------------------------------------------
fn suite() -> List[Result[Unit, Str]] {
  [zero_escapes(), every_category_100pct(), format_includes_every_category(), corpus_non_empty()]
}

fn run_all() -> Int {
  list.fold(suite(), 0, fn (acc :: Int, v :: Result[Unit, Str]) -> Int {
    match v {
      Ok(_) => acc,
      Err(_) => acc + 1,
    }
  })
}

