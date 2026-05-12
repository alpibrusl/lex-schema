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

### Pinned dependencies

- `lex-lang` ≥ `0.7.x` (matches the stdlib surface at the time of
  writing — `json.parse_strict` from #168, `std.regex`,
  `std.{toml,yaml}.parse_strict`, refinement types).
- No native dependencies.

### Issues filed against lex-lang

Tracking the small ergonomic gaps that surfaced while writing the
library. None block any feature; they'd make user code cleaner.

- [`alpibrusl/lex-lang#319`](https://github.com/alpibrusl/lex-lang/issues/319)
  Inline type ascription `(expr :: Type)`. The library works around
  this with typed-init helpers (`zip_index_init[T]`, `err_int`,
  `traverse_init`, ...).
- [`alpibrusl/lex-lang#320`](https://github.com/alpibrusl/lex-lang/issues/320)
  `option.unwrap_or_else` — closure-thunk default to match
  `result.or_else`.
- [`alpibrusl/lex-lang#321`](https://github.com/alpibrusl/lex-lang/issues/321)
  `list.enumerate` for index-paired iteration. The library
  re-implements this locally as `zip_index` in `src/field.lex`.
- [`alpibrusl/lex-lang#322`](https://github.com/alpibrusl/lex-lang/issues/322)
  Deep JSON type validation under `json.parse_strict` (follow-up
  to lex-lang#168). When it lands, `lex-pydantic` becomes fully
  runtime-safe end-to-end with no surface change.

All four are tagged `lex-pydantic` in the lex-lang tracker.
