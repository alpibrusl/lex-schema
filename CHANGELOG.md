# Changelog

All notable changes to lex-pydantic are tracked here.

## [Unreleased] — 0.4.0

### Added

- `src/schema.lex` — schemas as values. `ModelSchema` carries a
  `List[Field]`, each `Field` has a `FieldKind` (`KStr` / `KInt` /
  `KFloat` / `KBool` / `KArray` / `KObject`) plus required-flag
  and description. Three operations off one schema:
  - `validate(schema, json)` runs the constraint catalog against
    a `Json` value, returning a normalized `Json` (a `JObj` of
    validated fields).
  - `to_json_schema(schema)` emits JSON Schema 2020-12 (with
    `$schema`, `properties`, `required`, formats like `email`/`uri`).
  - `to_openapi_schema(schema)` emits the same body sans `$schema`,
    ready to drop into an OpenAPI 3.1 `components/schemas` entry.
- `src/cli.lex` — `std.cli` ↔ `ModelSchema` bridge.
  `parse_and_validate_argv(spec, argv, schema)` parses CLI args,
  flattens the `cli.parse` result (`positionals` + `flags` +
  `options` merged), and runs the schema. CLI parse errors carry
  `code = "parse"`; constraint failures keep their per-rule codes.
- `examples/10_schema_introspection.lex` — User+Address with
  arrays + nested record; one schema drives validation and emits
  formatted JSON Schema.
- `examples/11_cli_args.lex` — `genctl` CLI with a positional,
  option, and flag, validated through a `ModelSchema`.
- `tests/test_schema.lex` — 13 cases covering happy/sad paths,
  nested-path errors, indexed-array errors, JSON Schema field
  emission, and OpenAPI variant.
- `tests/test_cli.lex` — 6 cases covering happy path, default
  flowthrough, parse failure, schema failure, bucket flattening,
  and help passthrough.

### Optimized

- `json_value.lex` — `parse_string_raw` now uses a two-cursor
  scan that flushes escape-free runs via a single `str.slice`.
  Strings with no escapes (the common case) parse in O(n) bytes
  copied instead of O(n²). Strings with escapes still pay the
  per-segment concat — bounded by the number of escapes, not
  the total length.

### Issues filed

- [`#334`](https://github.com/alpibrusl/lex-lang/issues/334)
  `list.cons` / `list.reverse` for O(n) builder loops — what
  blocks the remaining O(n²) in the parser's array/object
  loops. The string fast path closes the inner hotspot;
  outer loops await this primitive.

### Verified against

- `lex 0.7.1` (HEAD of `main`).
- 11 of 11 test suites: 0 failures.
- 11 of 11 examples run end-to-end.
- Every `src/*.lex` module `lex check`s cleanly.

## [Unreleased] — 0.3.0

### Added

- `src/union.lex` — `discriminate(prefix, j, tag_field, branches)`
  for tagged-union JSON payloads. Branches are
  `(Str, (Json) -> Result[T, Errors])` pairs; missing/wrong/unknown
  tag failures each get a distinct error code.
- `src/datetime.lex` — `DateCheck` variants
  (`DateBefore` / `DateAfter` / `DateAtOrBefore` / `DateAtOrAfter`
  / `DateInRange`) plus `check_iso_datetime` /
  `check_datetime(format)`. Comparisons go through a packed
  `YYYYMMDDhhmmss` `Int` key derived from `datetime.to_components`
  — a workaround for lex-lang#331 (no `Instant` comparison) and
  lex-lang#332 (no runtime `Str < Str`). Now-relative presets
  (`check_iso_in_past` / `check_iso_in_future`) carry `[time]`.
- `src/json_value.lex` — dotted-path extraction (`get_path`,
  `j_str_at`, `j_int_at`, `j_optional_str_at`), `stringify`
  (compact, round-trips through `parse`), and `stringify_pretty`
  (two-space indented).
- `examples/08_discriminated_union.lex` — webhook event router
  with three event variants.
- `examples/09_datetime_and_paths.lex` — scheduled-event payload
  combining ISO 8601 bounds and dotted paths through nested
  records (`organizer.email`, `location.address.city`).
- `tests/test_union.lex` — 6 cases (happy path, missing tag,
  unknown tag, branch error propagation).
- `tests/test_datetime.lex` — 13 cases covering parse, bounds,
  accumulation, and canonical-form return.
- `tests/test_json_extra.lex` — 12 cases for `get_path`,
  `j_str_at`, `j_optional_str_at`, and stringify (primitives,
  round-trip, escapes, pretty form).

### Issues filed

- [`#331`](https://github.com/alpibrusl/lex-lang/issues/331)
  `Instant`/`Duration` have no comparison surface. Worked around
  in `src/datetime.lex` by packing to a 14-digit `YYYYMMDDhhmmss`
  Int via `to_components`.
- [`#332`](https://github.com/alpibrusl/lex-lang/issues/332)
  `Str < Str` type-checks but the VM's `NumLt` only handles
  `Int`/`Float`. Worked around with the same Int packing as #331.

### Verified against

- `lex 0.7.1` (HEAD of `main`).
- 9 of 9 test suites: 0 failures.
- 9 of 9 examples run end-to-end.
- Every `src/*.lex` module `lex check`s cleanly.

## [Unreleased] — 0.2.0

### Added

- `src/coerce.lex` — string-to-typed coercion (`coerce_str_to_int`,
  `coerce_str_to_float`, `coerce_str_to_bool`) and combined
  coerce-plus-validate (`check_str_as_int`, ...). Map-based
  `require_*` / `optional_*` helpers for the natural
  query-string / form-body shape.
- `src/json_value.lex` — first-class `Json` ADT (`JNull` / `JBool` /
  `JInt` / `JFloat` / `JStr` / `JList` / `JObj`) and a hand-rolled
  recursive-descent parser. Closes the runtime-safety gap for
  untrusted input by tagging every JSON value with its actual
  type up front; downstream `j_str` / `j_int` / `j_optional_*`
  extractors are total over malformed inputs.
- `src/field.lex` — optional-field variants
  (`check_optional_str` / `_int` / `_float` / `_bool`),
  `with_default` and `with_default_lazy` for the "field has a
  default" pydantic pattern.
- `examples/05_optional_and_defaults.lex` — Map-based source with
  one optional field (stays `Option[T]`) and one defaulted field.
- `examples/06_coerce_query_string.lex` — coercion pipeline for a
  HTTP-style `?page=3&debug=true` query string.
- `examples/07_safe_mode_json.lex` — Json-ADT pipeline that
  cleanly handles malformed JSON, wrong types, and missing fields.
- `tests/test_coerce.lex` — 12 cases covering coercion + Map
  helpers.
- `tests/test_json_value.lex` — 23 cases covering parser primitives,
  containers, escapes, whitespace tolerance, malformed inputs,
  and the path-aware extractor surface.

### Issues filed

- [`#328`](https://github.com/alpibrusl/lex-lang/issues/328)
  record-alias coercion stops working under nested constructors
  (`Result[T, MyAlias]`). Worked around with `mk_*` constructor
  helpers in `src/json_value.lex`.
- [`#329`](https://github.com/alpibrusl/lex-lang/issues/329)
  negative integer literals in match patterns. Worked around by
  binding-then-comparing in the test suite.

### Verified against

- `lex 0.7.1`.
- 6 of 6 test suites: 0 failures.
- 7 of 7 examples run end-to-end.
- Every `src/*.lex` module `lex check`s cleanly.

## [0.1.0]

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
