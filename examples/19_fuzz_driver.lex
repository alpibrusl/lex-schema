# lex-schema — fuzz driver demo
#
# Run every malformed-input catalogue against a User schema and
# print the tally. The contract is "every input in every category
# must surface as Err"; if the run prints a non-zero `escapes`
# count or the VM panics, that's a regression.
#
# Run:
#   lex run examples/19_fuzz_driver.lex demo_tallies
#   lex run examples/19_fuzz_driver.lex demo_escape_count

import "../src/constraints" as c
import "../src/schema"      as s
import "../src/fuzz"        as fz

fn user_schema() -> s.ModelSchema {
  {
    title: "User", description: "",
    fields: [
      s.required_str("name", [StrMinLen(1), StrMaxLen(80)]),
      s.required_int("age",  [IntInRange(13, 130)]),
    ],
  }
}

fn demo_tallies() -> Str {
  fz.format_tallies(fz.run_all(user_schema()))
}

fn demo_escape_count() -> Int {
  fz.count_escapes(user_schema())
}
