# lex-schema — std.cli integration
#
# `std.cli`'s `parse` returns a `Json` value with the shape
#
#   {"command": [...], "positionals": {...}, "flags": {...}, "options": {...}}
#
# which is exactly what we want to run against a `ModelSchema`.
# This module bridges the two:
#
#   1. `parse_and_validate_argv(spec, argv, schema)` —
#      argv → cli.parse → validate against our schema → typed value.
#   2. `parsed_to_value(parsed_json)` — convert the std.cli result
#      (which lex types as the opaque `Json` constructor) into the
#      richer `json_value.Json` ADT for path-aware traversal.
#
# The bridge funnels through `json.stringify` + `jv.parse` — the
# only round-trip available today because lex-lang's opaque `Json`
# can't be inspected from user code. When/if upstream gains
# `json.to_value` (#322 / its sibling), the round-trip drops out.
#
# Effects: none.

import "std.cli" as cli

import "std.json" as json

import "std.str" as str

import "std.list" as list

import "./error" as e

import "./json_value" as jv

import "./schema" as s

import "./combine" as cm

# ---- Bridge: opaque Json -> our Json ADT --------------------------
# Round-trip through string form. Costs one extra serialize+parse
# per CLI invocation — fine in a CLI startup path where the human
# is the bottleneck.
fn parsed_to_value(parsed :: Json) -> Result[jv.Json, e.Errors] {
  let s_form := json.stringify(parsed)
  jv.parse_into_errors(s_form)
}

# ---- Combined entry point -----------------------------------------
# Build a spec, parse `argv`, validate against `schema`. Returns
# the validated `Json` (a JObj) — drop into downstream business
# logic with `jv.j_str` / `jv.j_int` / etc.
#
# Three error sources, each tagged with a distinct code:
#   - argv didn't parse against the spec ⇒ code = "parse"
#   - cli result couldn't be re-decoded   ⇒ code = "parse"
#   - schema validation failed             ⇒ per-field codes
fn parse_and_validate_argv(spec :: Json, argv :: List[Str], schema :: s.ModelSchema) -> Result[jv.Json, e.Errors] {
  match cli.parse(spec, argv) {
    Err(m) => Err(e.single("", e.code_parse(), m)),
    Ok(parsed) => cm.and_then(parsed_to_value(parsed), fn (v :: jv.Json) -> Result[jv.Json, e.Errors] {
      s.validate(schema, flatten_cli_result(v))
    }),
  }
}

# ---- Shape reconciliation -----------------------------------------
#
# `cli.parse` returns
#   {"command": [...], "positionals": {...}, "flags": {...}, "options": {...}}
# but the user's schema is written against the *flat* shape
#   {field1: ..., field2: ..., ...}
# We flatten by merging `positionals`, `flags`, and `options` into
# a single object the schema can walk. `command` is dropped (it's
# the resolved subcommand path, not a user-validated field).
#
# If the same key appears in multiple buckets the later one wins;
# in practice they're disjoint (a CLI tool's flag and option names
# don't collide with positionals).
fn flatten_cli_result(parsed :: jv.Json) -> jv.Json {
  let bucket_keys := ["positionals", "options", "flags"]
  let entries := list.fold(bucket_keys, [], fn (acc :: List[(Str, jv.Json)], key :: Str) -> List[(Str, jv.Json)] {
    match jv.get_field(parsed, key) {
      None => acc,
      Some(b) => match jv.as_obj(b) {
        None => acc,
        Some(pairs) => list.concat(acc, pairs),
      },
    }
  })
  JObj(entries)
}

# ---- Help / introspection passthroughs ----------------------------
#
# Re-exported so callers don't need to import both modules. Useful
# at the top of a `main` that wants to print help on `--help`
# before falling into the validation pipeline.
fn help(spec :: Json) -> Str {
  cli.help(spec)
}

# The "what's this spec's machine-readable shape" — useful for
# integration tests and for emitting alongside `to_openapi_schema`
# in repos that ship both an HTTP and a CLI surface.
fn describe(spec :: Json) -> Json {
  cli.describe(spec)
}

