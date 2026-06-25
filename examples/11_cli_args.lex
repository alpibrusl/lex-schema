# lex-schema — CLI-arg validation
#
# A `gen` subcommand that takes a positional path, an `--output`
# option, and a `--verbose` flag. The CLI spec lives in `std.cli`;
# constraints live in a `ModelSchema` built with `s.required_*`.
# `cl.parse_and_validate_argv` runs both passes in one call and
# surfaces a uniform error trail.
#
# Run:
#   lex run examples/11_cli_args.lex demo_good
#   lex run examples/11_cli_args.lex demo_missing_path
#   lex run examples/11_cli_args.lex demo_bad_output

import "std.cli" as cli

import "std.list" as list

import "../src/error" as e

import "../src/constraints" as c

import "../src/json_value" as jv

import "../src/schema" as s

import "../src/cli" as cl

# ---- CLI spec -----------------------------------------------------
fn build_spec() -> Json {
  cli.spec("genctl", "generate things", [cli.flag("verbose", Some("v"), "noisy output"), cli.option("output", Some("o"), "output file path", Some("out.txt")), cli.positional("path", "input directory", true)], [])
}

# ---- Schema -------------------------------------------------------
fn arg_schema() -> s.ModelSchema {
  { title: "GenCtlArgs", description: "", fields: [s.required_str("path", [StrMinLen(1), StrMaxLen(1024)]), s.required_str("output", [StrEndsWith(".txt"), StrMaxLen(255)]), s.required_bool("verbose")] }
}

# ---- Pipeline ----------------------------------------------------
fn run_args(argv :: List[Str]) -> Result[jv.Json, e.Errors] {
  cl.parse_and_validate_argv(build_spec(), argv, arg_schema())
}

# ---- Demos --------------------------------------------------------
fn demo_good() -> Result[jv.Json, e.Errors] {
  run_args(["./src", "--verbose"])
}

fn demo_missing_path() -> Result[jv.Json, e.Errors] {
  run_args(["--verbose"])
}

fn demo_bad_output() -> Result[jv.Json, e.Errors] {
  run_args(["./src", "--output", "report.pdf"])
}

fn format_missing_path() -> Str {
  match demo_missing_path() {
    Ok(_) => "no errors",
    Err(es) => e.format(es),
  }
}

fn format_bad_output() -> Str {
  match demo_bad_output() {
    Ok(_) => "no errors",
    Err(es) => e.format(es),
  }
}

fn show_help() -> Str {
  cl.help(build_spec())
}

