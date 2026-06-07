# lex-schema — fuzz driver
#
# Complements `property.lex` from the other end. Where `property`
# generates *valid* inputs and asserts they pass validation, this
# module generates *intentionally-malformed* inputs and asserts
# they surface as `Result[_, Errors]` — never as a VM-level panic.
#
# The invariant is bigger than it sounds: a single panic in the
# validation pipeline brings down the whole `lex run` (or worse,
# the production `lex serve`). The fuzz driver catalogs the
# expected ways inputs are wrong — bad JSON syntax, type-shape
# mismatches, missing fields, extra fields, oversized strings,
# pathological nesting — and walks them through the validator,
# tallying outcomes by category. The pass condition is:
#
#   *every* malformed input produces an Err(...) outcome,
#   and zero inputs produce a runtime panic.
#
# Since lex's runtime panics are uncatchable from user code, the
# absence-of-panic is enforced *by the run completing*: if a panic
# happened, `lex run` would have exited non-zero before printing
# the final summary.
#
# Effects: none. The seed list is hard-coded; randomized
# generation lives in `property.lex`.

import "std.str" as str

import "std.int" as int

import "std.list" as list

import "./error" as e

import "./json_value" as jv

import "./schema" as s

# ---- Seed catalogues ---------------------------------------------
#
# Each category covers a different reason a payload can be wrong.
# Adding a case is one line; the driver tallies by category so a
# regression points at which class of input started passing.
fn parse_failures() -> List[Str] {
  ["", "not even json", "{", "{\"a\":1", "[1,2,", "\"abc", "[1 2]", "{\"a\" 1}", "{a:1}", "{\"a\":1,}", "[null null]", "{\"a\":\\u0001}"]
}

fn type_mismatches() -> List[Str] {
  ["{\"name\":42,\"age\":30}", "{\"name\":\"alice\",\"age\":\"x\"}", "{\"name\":\"alice\",\"age\":null}", "{\"name\":true,\"age\":1}", "{\"name\":\"a\",\"age\":[1,2]}", "[1,2,3]", "42", "null", "\"just a string\""]
}

fn missing_required() -> List[Str] {
  ["{}", "{\"name\":\"alice\"}", "{\"age\":30}"]
}

fn constraint_failures() -> List[Str] {
  ["{\"name\":\"\",\"age\":30}", "{\"name\":\"a\",\"age\":7}", "{\"name\":\"a\",\"age\":300}", "{\"name\":\"a\",\"age\":-1}"]
}

# Deeply-nested payloads — common DoS surface. The Lex parser
# has a recursion gate (MAX_DEPTH = 96) so very-deep inputs
# fail-safe.
fn deep_nesting() -> List[Str] {
  [cat(repeat_str("[", 64), repeat_str("]", 64)), cat(repeat_str("{\"a\":", 64), cat("1", repeat_str("}", 64)))]
}

fn cat(a :: Str, b :: Str) -> Str {
  str.concat(a, b)
}

fn repeat_str(s :: Str, n :: Int) -> Str {
  if n <= 0 {
    ""
  } else {
    str.concat(s, repeat_str(s, n - 1))
  }
}

# ---- Driver -------------------------------------------------------
type Tally = { category :: Str, total :: Int, errored :: Int }

fn run_category(name :: Str, inputs :: List[Str], schema :: s.ModelSchema) -> Tally {
  let total := list.len(inputs)
  let errored := list.fold(inputs, 0, fn (acc :: Int, body :: Str) -> Int {
    match outcome(body, schema) {
      Ok(_) => acc,
      Err(_) => acc + 1,
    }
  })
  { category: name, total: total, errored: errored }
}

fn outcome(body :: Str, schema :: s.ModelSchema) -> Result[jv.Json, e.Errors] {
  match jv.parse_into_errors(body) {
    Err(es) => Err(es),
    Ok(j) => s.validate(schema, j),
  }
}

# Run every catalogue against the supplied schema; return a list
# of tallies, one per category. The caller asserts that
# `errored == total` for every category.
fn run_all(schema :: s.ModelSchema) -> List[Tally] {
  [run_category("parse_failures", parse_failures(), schema), run_category("type_mismatches", type_mismatches(), schema), run_category("missing_required", missing_required(), schema), run_category("constraint_failures", constraint_failures(), schema), run_category("deep_nesting", deep_nesting(), schema)]
}

# Returns 0 if every fuzz input produced an Err, otherwise the
# total number of inputs that escaped (i.e., were Ok when we
# expected Err). Pairs with `run_all` for a one-line assertion in
# tests: "did the driver fail to provoke any failure?"
fn count_escapes(schema :: s.ModelSchema) -> Int {
  list.fold(run_all(schema), 0, accumulate_escapes)
}

# Top-level so the fold reducer doesn't carry the closure across
# the recursive `run_category` chain. Per-fold helpers stay simple
# (one field add); compound expressions involving multiple field
# reads inside the closure body interact badly with lex-lang#337
# (pattern-fail-leak).
fn accumulate_escapes(acc :: Int, t :: Tally) -> Int {
  acc + t.total - t.errored
}

# Render the tally as a human-readable summary. Stable enough
# that tests can assert against substrings.
fn format_tallies(tallies :: List[Tally]) -> Str {
  let lines := list.map(tallies, fn (t :: Tally) -> Str {
    str.concat(t.category, str.concat(": ", str.concat(int_to_str(t.errored), str.concat("/", int_to_str(t.total)))))
  })
  str.join(lines, "\n")
}

fn int_to_str(n :: Int) -> Str {
  int.to_str(n)
}

