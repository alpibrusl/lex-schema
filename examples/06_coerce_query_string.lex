# lex-schema — query-string / form coercion
#
# A query string arrives as `?page=3&per_page=20&debug=true`. Every
# value is a Str, but we want typed Ints / Bools downstream with
# the usual constraints (`page >= 1`, `per_page` in (0, 100]).
#
# `coerce` is the entry point for "every value is text but I want
# typed fields with constraints" — the coercion failure and the
# constraint failure produce different error codes so the API
# response can dispatch on them.
#
# Run:
#   lex run examples/06_coerce_query_string.lex demo_good
#   lex run examples/06_coerce_query_string.lex demo_bad

import "std.map" as map

import "std.str" as str

import "std.list" as list

import "../src/error" as e

import "../src/constraints" as c

import "../src/coerce" as coerce

import "../src/combine" as cm

type ListParams = { page :: Int, per_page :: Int, query :: Option[Str], include_archived :: Bool }

fn mk(p :: Int, pp :: Int, q :: Option[Str], ia :: Bool) -> ListParams {
  { page: p, per_page: pp, query: q, include_archived: ia }
}

fn validate(qs :: Map[Str, Str]) -> Result[ListParams, e.Errors] {
  cm.combine4(coerce.require_int_from_map(qs, "page", [IntPositive]), coerce.require_int_from_map(qs, "per_page", [IntInRange(1, 100)]), coerce.optional_str_from_map(qs, "query", [StrMaxLen(120)]), coerce.require_bool_from_map(qs, "include_archived"), mk)
}

# ---- Inputs --------------------------------------------------------
fn parse_query(s :: Str) -> Map[Str, Str] {
  let pairs := list.map(str.split(s, "&"), fn (kv :: Str) -> (Str, Str) {
    let parts := str.split(kv, "=")
    match list.head(parts) {
      None => ("", ""),
      Some(k) => match list.head(list.tail(parts)) {
        None => (k, ""),
        Some(v) => (k, v),
      },
    }
  })
  map.from_list(pairs)
}

fn demo_good() -> Result[ListParams, e.Errors] {
  validate(parse_query("page=3&per_page=20&query=lex&include_archived=true"))
}

fn demo_bad() -> Result[ListParams, e.Errors] {
  validate(parse_query("page=foo&per_page=999&include_archived=maybe"))
}

fn format_demo() -> Str {
  match demo_bad() {
    Ok(_) => "no errors",
    Err(es) => e.format(es),
  }
}

