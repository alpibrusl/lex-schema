# lex-pydantic — fuzz driver
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

import "std.str"  as str
import "std.list" as list

import "./error"      as e
import "./json_value" as jv
import "./schema"     as s

# ---- Seed catalogues ---------------------------------------------
#
# Each category covers a different reason a payload can be wrong.
# Adding a case is one line; the driver tallies by category so a
# regression points at which class of input started passing.

fn parse_failures() -> List[Str] {
  [
    "",                          # empty
    "not even json",             # leading garbage
    "{",                         # truncated object
    "{\"a\":1",                  # unterminated object
    "[1,2,",                     # unterminated array
    "\"abc",                     # unterminated string
    "[1 2]",                     # missing comma in array
    "{\"a\" 1}",                 # missing colon in object
    "{a:1}",                     # unquoted key
    "{\"a\":1,}",                # trailing comma (RFC 8259 forbids)
    "[null null]",               # missing separator
    "{\"a\":\\u0001}",           # unsupported \uXXXX escape
  ]
}

fn type_mismatches() -> List[Str] {
  # JSON parses cleanly but the value doesn't match what the schema
  # expects.
  [
    "{\"name\":42,\"age\":30}",          # name should be Str
    "{\"name\":\"alice\",\"age\":\"x\"}", # age should be Int
    "{\"name\":\"alice\",\"age\":null}",  # age null
    "{\"name\":true,\"age\":1}",          # name Bool
    "{\"name\":\"a\",\"age\":[1,2]}",     # age List
    "[1,2,3]",                            # array at root
    "42",                                 # int at root
    "null",                               # null at root
    "\"just a string\"",                  # string at root
  ]
}

fn missing_required() -> List[Str] {
  [
    "{}",
    "{\"name\":\"alice\"}",   # no age
    "{\"age\":30}",            # no name
  ]
}

fn constraint_failures() -> List[Str] {
  [
    "{\"name\":\"\",\"age\":30}",                     # name too short
    "{\"name\":\"a\",\"age\":7}",                     # age below min
    "{\"name\":\"a\",\"age\":300}",                   # age above max
    "{\"name\":\"a\",\"age\":-1}",                    # negative age
  ]
}

# Deeply-nested payloads — common DoS surface. The Lex parser
# has a recursion gate (MAX_DEPTH = 96) so very-deep inputs
# fail-safe.
fn deep_nesting() -> List[Str] {
  [
    cat(repeat_str("[", 64), repeat_str("]", 64)),
    cat(repeat_str("{\"a\":", 64), cat("1", repeat_str("}", 64))),
  ]
}

fn cat(a :: Str, b :: Str) -> Str { str.concat(a, b) }

fn repeat_str(s :: Str, n :: Int) -> Str {
  if n <= 0 { "" } else { str.concat(s, repeat_str(s, n - 1)) }
}

# ---- Driver -------------------------------------------------------

type Tally = {
  category :: Str,
  total :: Int,
  errored :: Int,
}

fn run_category(
  name :: Str,
  inputs :: List[Str],
  schema :: s.ModelSchema
) -> Tally {
  let total := list.len(inputs)
  let errored := list.fold(inputs, 0, fn (acc :: Int, body :: Str) -> Int {
    match outcome(body, schema) {
      Ok(_)  => acc,
      Err(_) => acc + 1,
    }
  })
  { category: name, total: total, errored: errored }
}

fn outcome(body :: Str, schema :: s.ModelSchema) -> Result[jv.Json, e.Errors] {
  match jv.parse_into_errors(body) {
    Err(es) => Err(es),
    Ok(j)   => s.validate(schema, j),
  }
}

# Run every catalogue against the supplied schema; return a list
# of tallies, one per category. The caller asserts that
# `errored == total` for every category.
fn run_all(schema :: s.ModelSchema) -> List[Tally] {
  [
    run_category("parse_failures",      parse_failures(),     schema),
    run_category("type_mismatches",     type_mismatches(),    schema),
    run_category("missing_required",    missing_required(),   schema),
    run_category("constraint_failures", constraint_failures(),schema),
    run_category("deep_nesting",        deep_nesting(),       schema),
  ]
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
    str.concat(t.category, str.concat(": ",
      str.concat(int_to_str(t.errored),
        str.concat("/", int_to_str(t.total)))))
  })
  str.join(lines, "\n")
}

import "std.int" as int
fn int_to_str(n :: Int) -> Str { int.to_str(n) }
