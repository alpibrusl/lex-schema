# Changelog

All notable changes to lex-schema are tracked here.

## [Unreleased] — 0.8.1

### Added

- `src/form.lex` — HTTP form-body decoders. `decode_urlencoded`
  parses `application/x-www-form-urlencoded` (handles `+`-as-
  space, `%XX` byte escapes for ASCII, bare-key-as-empty-value,
  multi-`=`-in-value). `decode_body(body, content_type)`
  dispatches on Content-Type (accepts the standard
  `; charset=UTF-8` suffix). `multipart/form-data` is stubbed —
  v2 will land the full parser.
- `src/sdk.lex` — `to_go_struct(schema)` emits a Go struct per
  schema with `encoding/json` tags. PascalCases field names
  (treating `_` and `-` as word separators), wraps optional
  fields as `*T` with `omitempty`, drops constraint metadata
  into `// constraints: ...` doc comments.
- `src/schema.lex` — `to_mermaid_er(schema)` emits a Mermaid
  `erDiagram` block. Nested `KObject` fields become
  `||--||` entity relationships; `KArray(KObject(_), _)`
  becomes `||--o{`. Output drops straight into Markdown for
  GitHub / GitLab / Notion / VS Code preview.
- `examples/21_form_and_diagram.lex` — login-form pipeline
  (URL-encoded body → `cm.combine3` validation → typed
  `LoginFields`), plus Mermaid ER diagram + Go struct emitted
  from the same schema.
- `tests/test_form.lex` — 10 cases (round-trips, plus
  edge cases like `%XX`, bare keys, `=` in values, charset
  suffix).
- `tests/test_codegen_more.lex` — 12 cases (Go-struct
  coverage, Mermaid ER coverage).

### Filed upstream

- [`alpibrusl/lex-lang#353`](https://github.com/alpibrusl/lex-lang/issues/353)
  — package proposal for **`lex-web`**, an HTTP framework
  on top of `net.serve` that integrates with lex-schema for
  typed body validation and auto-OpenAPI export. Sketches the
  ~1000-1500 LoC v0.1 surface and lists `lex-auth` /
  `lex-orm` / `lex-log` / `lex-trace` as follow-up packages
  that compose on top.

### Verified against

- `lex 0.8.2`.
- 23 of 23 test suites: 0 failures (~265 cases).
- 21 of 21 examples run end-to-end.
- Every `src/*.lex` module `lex check`s cleanly.

## [Unreleased] — 0.8.0

### Renamed

The library is now **lex-schema** (was `lex-pydantic` through
v0.7.x). pydantic remains the credited inspiration for the
constraint catalog + multi-error accumulation; the new name
better reflects that this is a Lex-native library, not a
port. The `lex-pydantic` label on the issue tracker stays for
historical references.

### Added

- `src/constraints.lex` — nine new `StrCheck` variants:
  `StrIPv4`, `StrIPv6`, `StrHostname`, `StrIsoDate`,
  `StrIsoTime`, `StrBase64`, `StrHex`, `StrPhoneE164`,
  `StrCreditCardLuhn` (with Luhn-algorithm checksum). Each maps
  to the appropriate JSON Schema `format` keyword and to the
  matching Zod / pydantic / Rust-doc rendering.
- `src/problem.lex` — RFC 7807 `application/problem+json`
  renderer. `validation_problem(type, instance, errors)`
  produces the standard envelope. Helpers for the common HTTP
  status presets (`not_found`, `method_not_allowed`,
  `unauthorized`, `forbidden`, `bad_request`,
  `internal_server_error`). `to_json` / `to_str` /
  `to_pretty` / `to_response` for serialization.
- `src/migrate.lex` — schema migrations + backward-compat check.
  - `Transform` ADT with `Rename` / `DropField` / `AddField`
    / `SetField` / `CoerceStrToInt` / `CoerceStrToFloat` /
    `CoerceStrToBool` / `NestInto` / `UnnestFrom`.
  - `apply(json, [transform, ...])` runs them in sequence.
  - `is_backward_compatible(old, new)` returns `Ok(())` or
    `Err([Incompat{field, reason}])`. Flags new required fields,
    type changes, optional → required transitions.
- `src/sdk.lex` — two new codegen backends:
  - `to_zod(schema)` emits a Zod schema (TypeScript runtime
    validation). Chain syntax with `.min` / `.max` / `.email` /
    `.regex` / `.ip` / `.optional` / `.nonempty`.
  - `to_rust_struct(schema)` emits a `#[derive(Debug, Clone,
    Serialize, Deserialize)]` struct with `Option<T>` +
    `#[serde(default)]` for optionals and constraint metadata
    in `///` doc comments.
- `examples/20_payments_api.lex` — combined tour: a payments
  schema using IP + Luhn + phone validators, RFC 7807 error
  responses, all four codegen backends (TS / Python / Zod /
  Rust), and a v1 → v2 migration with a compat-check failure.
- `tests/test_formats.lex` — 21 cases across all nine new
  format validators.
- `tests/test_problem.lex` — 9 cases (envelope shape, status
  presets, serialization).
- `tests/test_sdk_more.lex` — 10 cases (Zod + Rust codegen
  coverage).
- `tests/test_migrate.lex` — 12 cases (each transform + chained
  transforms + compat check truth table).

### Verified against

- `lex 0.8.2`.
- 21 of 21 test suites: 0 failures (~245 cases).
- 20 of 20 examples run end-to-end.
- Every `src/*.lex` module `lex check`s cleanly.

## [Unreleased] — 0.7.2

### Pinned lex version

- Built against `lex 0.8.2`. The 0.8.2 release closed the last
  three lex-schema-labeled issues:
  - **#331** — `datetime.before` / `datetime.after` /
    `datetime.compare` (and a new `std.duration` module with
    `duration.seconds`).
  - **#334** — `list.cons` (companion to `list.reverse` which
    landed earlier).
  - **#345** — type-alias unfold now recurses through closure
    params in polymorphic stdlib signatures.

### Removed (workarounds for upstream fixes)

- `instant_sort_key` + `bound_key` in `src/datetime.lex` are
  gone. `eval_date` calls `datetime.before` / `datetime.after` /
  `datetime.compare` on parsed `Instant`s directly — no more
  packing into `YYYYMMDDhhmmss` Ints (#331).
- Restored `type Errors = List[Error]` in `src/error.lex`.
  Every `src/*.lex`, `examples/*.lex`, and `tests/*.lex` was
  swept from `List[e.Error]` back to `e.Errors`. The alias
  unfolds cleanly through fold reducers now (#345).
- `array_loop` and `object_loop` in `src/json_value.lex` now use
  `list.cons` + a single `list.reverse` at the close. JSON
  parsing is **O(n)** end-to-end (previously O(n²) on nested
  arrays/objects). The performance note at the top of the file
  is updated to reflect (#334).

### Verified against

- `lex 0.8.2`.
- 17 of 17 test suites: 0 failures (~185 cases).
- 19 of 19 examples run end-to-end.
- Every `src/*.lex` module `lex check`s cleanly.

### Issue tracker rollup

After 0.8.2, **zero** lex-schema-labeled issues remain open. The
library now compiles and runs against vanilla `lex` with no
workarounds. Sixteen filed → sixteen closed:

```
#319 #320 #321 #322 #323 #324 #325 #326 #328 #329
#331 #332 #334 #337 #338 #339 #345
```

## [Unreleased] — 0.7.1

### Pinned lex version

- Now built against `lex 0.8.0`. The previous v0.7.x line built
  against `lex 0.7.1`; 0.8.0 closes thirteen of the fifteen
  lex-lang issues this library filed during v0.1-v0.7. The cleanup
  in this release removes the workarounds for them.

### Removed (workarounds for upstream fixes)

- `mk_err` / `mk_step` / `mk_string_step` in `src/json_value.lex`,
  `mk_model` / `mk_field` in `src/schema.lex`, and `mk_tally` /
  `inc_if_err` in `src/fuzz.lex` are gone. The inline record
  literals now coerce to the nominal aliases through nested
  constructors thanks to **lex-lang#328**.
- `re_match` wrapper in `src/constraints.lex` is gone; the regex
  checks now call `regex.is_match_str(pattern, s)` directly —
  **lex-lang#326**.
- `zip_index` / `zip_index_init` in `src/field.lex`,
  `src/schema.lex`, and `examples/03_list_of_items.lex` are gone;
  callers use `list.enumerate(xs)` directly — **lex-lang#321**.
- Lifted-helper workaround for **lex-lang#337**
  (`is_email` / `is_url` / `is_uuid` / `is_one_of` top-level
  helpers in `src/property.lex`, ditto in
  `tests/test_schema_import.lex`) is gone. Inline
  `acc or match chk { Variant => true, _ => false }` works
  cleanly under the fixed PConstructor compilation.

### Held over (workarounds still required)

- `instant_sort_key` in `src/datetime.lex` — still packs
  `Instant` into a 14-digit Int via `to_components` because
  **lex-lang#331** (Instant/Duration comparison surface) is open.
- `List[e.Error]` spelled directly throughout — **lex-lang#323**
  is *partially* closed in 0.8.0 (simple positions work) but
  the alias unfold doesn't reach polymorphic stdlib closures.
  Filed as **lex-lang#345** follow-up.

### Issues filed

- [`#345`](https://github.com/alpibrusl/lex-lang/issues/345) —
  follow-up to #323: type-alias unfold doesn't reach fresh
  type-variables in polymorphic-stdlib closure params (e.g.,
  `list.fold` reducer annotated with an alias).

### Verified against

- `lex 0.8.0` (HEAD of `main` at the 0.8.0 tag).
- 17 of 17 test suites: 0 failures (~185 cases).
- 19 of 19 examples run end-to-end.
- Every `src/*.lex` module `lex check`s cleanly.

### Issue tracker rollup

After 0.8.0, the open lex-schema-labeled issues drop from 16 to
3 (one was re-opened as #345 above):

- **#331** Instant / Duration comparison surface.
- **#334** `list.cons` (only `list.reverse` shipped in 0.8.0).
- **#345** `List[alias]` in polymorphic closure params.

## [Unreleased] — 0.7.0

### Added

- `src/validator.lex` — `Validator` bundle. `make(schema)` runs
  every emitter once and stores results in a single record; the
  caller passes one value around for both runtime validation
  (`validate`, `validate_str`) and codegen (`export_typescript`,
  `export_python`, `export_json_schema_str`, `export_openapi_str`).
- `src/fuzz.lex` — malformed-input fuzz driver. Five hand-picked
  catalogues (parse failures, type mismatches, missing required,
  constraint failures, deep nesting) walk through the schema's
  validator. The pass condition is `count_escapes == 0` *and* no
  VM panic; the latter is enforced by the run completing.
- `examples/18_cli_codegen.lex` — read a JSON Schema file from
  disk, emit any of TypeScript / Python / JSON Schema / OpenAPI
  / summary, or validate a payload file against it. Uses `io.read`
  + the validator bundle for a Makefile-friendly surface.
- `examples/19_fuzz_driver.lex` — run all five fuzz catalogues
  against a User schema. The reference output is `0` escapes;
  every regression is loud.
- `tests/test_validator.lex` — 9 cases (make, summary,
  validate_str happy/sad/parse-failure, exports for all four
  formats).
- `tests/test_fuzz.lex` — 4 cases (zero escapes, per-category
  100%, format renders every category, corpus non-empty).

### Issues filed

- [`#339`](https://github.com/alpibrusl/lex-lang/issues/339)
  top-level fn whose name shadows a cross-module parameter is
  passed as a closure value, producing a silent miscompile that
  surfaces as `GetField on non-record: Closure { fn_id: N, ... }`
  far from the call site. Worked around by renaming test
  fixtures from `schema()` to `fixture_schema()`.

### Verified against

- `lex 0.7.1`.
- 17 of 17 test suites: 0 failures (~185 cases).
- 19 of 19 examples run end-to-end.
- Every `src/*.lex` module `lex check`s cleanly.

## [Unreleased] — 0.6.0

### Added

- `src/sdk.lex` — `ModelSchema` → client-SDK codegen.
  - `to_typescript(schema)` emits `export interface` declarations
    (one per nested record), with JSDoc descriptions, optional-
    field `?:`, `StrOneOf` rendered as `"a" | "b"` union types,
    and constraint hints in trailing `// minLength: ...` comments.
  - `to_python(schema)` emits pydantic v2 `BaseModel` classes.
    Constraints map to pydantic field args (`min_length`,
    `pattern`, `ge`/`le`, `Literal[...]`). Nested classes emit
    first so the top-level class can reference them without
    forward declarations. Output is drop-in pydantic source.
- `examples/15_sdk_export.lex` — one User schema produces three
  artifacts: JSON Schema, TypeScript interfaces, pydantic
  classes — same source of truth.
- `examples/16_validation_service.lex` — `POST /v1/validate`
  HTTP service that accepts `{schema, payload}` over the wire,
  returns 200 + normalized payload on success or 422 +
  structured `errors[]` on failure. Smoke-test entry points
  exercise the pipeline without binding the port.
- `examples/17_webhook_dedup.lex` — Stripe / GitHub /
  Slack-style at-least-once delivery, deduped via SHA-256
  idempotency key over the parser-output bytes. Threads a
  `Set[Str]` of seen keys through the dispatch.
- `tests/test_sdk.lex` — 12 cases (TS + Python coverage of
  enum, optional, nested, constraint mapping).

### Issues filed

- [`#338`](https://github.com/alpibrusl/lex-lang/issues/338)
  `list.sort_by[T, K]` for canonicalization / dedup pipelines.
  Used to canonicalize JSON key order so semantically-identical
  payloads with different key orders dedup the same.

### Verified against

- `lex 0.7.1`.
- 15 of 15 test suites: 0 failures (~170 cases).
- 17 of 17 examples run end-to-end.
- Every `src/*.lex` module `lex check`s cleanly.

## [Unreleased] — 0.5.0

### Added

- `src/combine.lex` — `cross_check[T](value, checks)` runs a list
  of `(T) -> Option[List[Error]]` rules against an already-built
  record. Accumulates failures across every rule; chains naturally
  after a successful `combineN` via `cm.and_then`. The
  `cm.require[T](value, predicate, path, code, message)` shortcut
  covers the one-rule-plus-fixed-message case.
- `src/property.lex` — schema-driven sample generation. `generate`
  walks a `ModelSchema` and emits a `Json` that respects every
  constraint (length bounds, ranges, `OneOf`, plus known-good
  templates for `email`/`url`/`uuid`). `round_trip(schema, n,
  seed)` runs `n` generate→validate cycles, returning `Ok(n)` on
  a clean sweep or `Err(...)` on the first mismatch. Pure and
  deterministic — `std.random`'s SplitMix64 means the same seed
  yields the same sequence everywhere.
- `src/schema_import.lex` — inverse of `to_json_schema`. Reads a
  JSON Schema document (Draft 2020-12) and produces a `ModelSchema`.
  Round-trip through `to_json_schema` is structurally preserving
  for the subset the library emits.
- `src/schema.lex` — `mk_model` / `mk_field` constructor helpers
  whose return types pin the nominal alias; needed by
  `schema_import` and any dynamic-schema builder because of
  lex-lang#328.
- `examples/12_cross_field.lex` — password+confirm match and
  date-ordering rules wired through `cross_check`.
- `examples/13_property_test.lex` — 200 generate→validate rounds
  against a User schema with email/uuid/array fields.
- `examples/14_json_schema_round_trip.lex` — emit JSON Schema,
  parse it back, validate the same payload through both.
- `tests/test_cross_field.lex` — 7 cases.
- `tests/test_property.lex` — 8 cases (bounds, format templates,
  determinism, round-trip).
- `tests/test_schema_import.lex` — 7 cases (round-trip, direct
  parse, format/constraint mapping, validates valid + rejects
  invalid).

### Issues filed

- [`#337`](https://github.com/alpibrusl/lex-lang/issues/337)
  constructor-pattern fail path leaks the scrutinee onto the
  stack. Symptom: `false or match x { Variant => true, _ => false }`
  panics at runtime when `x` is a non-matching variant. Worked
  around by lifting the inner match into a top-level helper
  function — its call frame contains the leaked stack value.

### Verified against

- `lex 0.7.1` (HEAD of `main`).
- 14 of 14 test suites: 0 failures (~155 cases).
- 14 of 14 examples run end-to-end.
- Every `src/*.lex` module `lex check`s cleanly.

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
  to lex-lang#168). When it lands, `lex-schema` becomes fully
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

All eight are tagged `lex-schema` in the lex-lang tracker.
