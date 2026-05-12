# lex-pydantic — property-based testing
#
# Generate random values from a `ModelSchema`, run them through
# `s.validate`, and assert the round-trip property: every
# generated sample must validate cleanly. If it doesn't, either
# the generator is buggy or the schema is internally inconsistent.
#
# This is the same idea as Python's Hypothesis or Haskell's
# QuickCheck, scoped specifically to schema-driven validation
# where the generator and the spec come from the same value.
#
# Run:
#   lex run examples/13_property_test.lex demo_round_trip
#   lex run examples/13_property_test.lex demo_one_sample

import "../src/error"       as e
import "../src/constraints" as c
import "../src/json_value"  as jv
import "../src/schema"      as s
import "../src/property"    as p

import "std.random" as random

# ---- The schema under test ----------------------------------------

fn user_schema() -> s.ModelSchema {
  {
    title: "User", description: "",
    fields: [
      s.required_str("name",  [StrMinLen(1), StrMaxLen(40)]),
      s.required_str("email", [StrEmail]),
      s.required_int("age",   [IntInRange(13, 130)]),
      s.required_str("id",    [StrUuid]),
      s.optional(s.required_str("nickname", [StrMaxLen(20)])),
      s.required_array("tags",
        KStr([StrMinLen(1), StrMaxLen(10)]),
        [ListMaxLen(5)]),
    ],
  }
}

# ---- 200 generate-then-validate rounds --------------------------
# Returns `Ok(count)` on a clean sweep; `Err([...])` if any
# iteration produced a sample that failed validation.

fn demo_round_trip() -> Result[Int, e.Errors] {
  p.round_trip(user_schema(), 200, 42)
}

# A single sample, useful for eyeballing what the generator emits.
fn demo_one_sample() -> Str {
  let gen := p.generate(user_schema(), random.seed(7))
  let v := match gen { (v1, _) => v1 }
  jv.stringify_pretty(v)
}
