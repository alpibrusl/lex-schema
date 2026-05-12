# Changelog

All notable changes to lex-pydantic are tracked here.

## [Unreleased] — 0.1.0

Initial release. Five-module pure-Lex library implementing
pydantic-style runtime validation on top of `lex-lang`'s stdlib.

### Added

- `src/error.lex` — `Error` / `Errors` record types, single/concat/
  flatten constructors, path-prefix helpers (`prefix_path`,
  `prefix_index`), `format` for stable diagnostic strings.
- `src/constraints.lex` — `StrCheck`, `IntCheck`, `FloatCheck`,
  `ListCheck` variant types and their evaluators. Built-in
  regex patterns for email, URL, and UUID.
- `src/field.lex` — `check_str`, `check_int`, `check_float`,
  `check_bool`, `check_list_shape`, `check_list_of`, plus a
  generic `validate` escape hatch for custom predicates.
- `src/combine.lex` — applicative `combine2..combine6`, monadic
  `and_then` / `or_else`, list-level `traverse`, path-prefixing
  `with_path`, `pure` / `fail` lifters.
- `src/parse.lex` — `from_json` / `from_toml` / `from_yaml`
  wrappers around `std.{json,toml,yaml}.parse_strict` that
  surface outer-shell parse failures as `Errors`.
- `examples/01_user_signup.lex` — minimum-viable signup form.
- `examples/02_nested.lex` — nested User → Address with path
  prefixing.
- `examples/03_list_of_items.lex` — indexed list-of-records
  validation; per-element paths `items[3].quantity`.
- `examples/04_api_request.lex` — full HTTP endpoint pipeline:
  parse → validate → respond.
- `tests/test_error.lex` — 11 cases covering `Error` construction,
  list manipulation, path helpers, and `format` output.
- `tests/test_constraints.lex` — 21 cases (~all variants × pass/fail).
- `tests/test_field.lex` — 8 cases, including error accumulation
  on a single field with multiple failing constraints.
- `tests/test_combine.lex` — 11 cases covering `combineN`,
  `traverse`, `and_then` / `or_else`, and `with_path`.

### Verified against

- `lex 0.7.1` (built from `alpibrusl/lex-lang` `main`).
- Every `src/*.lex` module type-checks under `lex check`.
- Every test suite (`tests/test_*.lex`) returns `run_all = 0`
  failures.
- Every example (`examples/0{1..4}_*.lex`) runs end-to-end.

### Dependencies

- `lex-lang` ≥ `0.7.x` (stdlib surface in use:
  `json.parse_strict` from #168, `std.regex`,
  `std.{toml,yaml}.parse_strict`, refinement types).
- No native dependencies.

### Issues filed against lex-lang

Tracking the ergonomic gaps that surfaced while writing the
library. Each has a documented workaround in the source; the
upstream fixes would let those workarounds go away.

- [`alpibrusl/lex-lang#319`](https://github.com/alpibrusl/lex-lang/issues/319)
  Inline type ascription `(expr :: Type)`. Worked around with
  typed-init helpers (`zip_index_init[T]`, `err_int`,
  `traverse_init`).
- [`alpibrusl/lex-lang#320`](https://github.com/alpibrusl/lex-lang/issues/320)
  `option.unwrap_or_else` — closure-thunk default to match
  `result.or_else`.
- [`alpibrusl/lex-lang#321`](https://github.com/alpibrusl/lex-lang/issues/321)
  `list.enumerate`. Re-implemented locally as `zip_index` in
  `src/field.lex`.
- [`alpibrusl/lex-lang#322`](https://github.com/alpibrusl/lex-lang/issues/322)
  Deep JSON type validation under `json.parse_strict` (follow-up
  to lex-lang#168). When it lands, `lex-pydantic` becomes fully
  runtime-safe end-to-end with no surface change.
- [`alpibrusl/lex-lang#323`](https://github.com/alpibrusl/lex-lang/issues/323)
  Type-alias asymmetry: Record aliases are transparent but
  List/Tuple/Option aliases are nominal. Worked around by
  writing `List[Error]` directly throughout rather than
  defining `type Errors = List[Error]`.
- [`alpibrusl/lex-lang#324`](https://github.com/alpibrusl/lex-lang/issues/324)
  `_` rejected as a lambda parameter name. Worked around by
  naming such parameters `_es` / `_x`.
- [`alpibrusl/lex-lang#325`](https://github.com/alpibrusl/lex-lang/issues/325)
  Float literals lack scientific notation. Worked around in
  `FloatFinite` by computing `math.pow(10.0, 309.0)` at runtime
  instead of an `1.79e308` literal.
- [`alpibrusl/lex-lang#326`](https://github.com/alpibrusl/lex-lang/issues/326)
  `regex.is_match_str` to skip the `regex.compile` round-trip.
  Worked around with the local `re_match` helper in
  `src/constraints.lex`.

All eight are tagged `lex-pydantic` in the lex-lang tracker.
