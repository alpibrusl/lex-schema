# lex-schema

A **runtime validation library** for [lex-lang](https://github.com/alpibrusl/lex-lang),
inspired by [pydantic](https://docs.pydantic.dev/)'s constraint
catalog + multi-error accumulation semantics but designed
ground-up for Lex's effect system, variant ADTs, and codegen
pipelines. Written in pure Lex — no Rust shims, no host hooks,
no native code. Runs on stock `lex run` / `lex check` and uses
only the existing stdlib (`std.str`, `std.list`, `std.regex`,
`std.json`, `std.datetime`, `std.random`, `std.crypto`,
`std.cli`, ...).

## Two paths to validation

Pick the one that fits your call-site shape; both produce the same
`Result[_, List[Error]]` end-to-end.

### Path A — combinator-driven (smallest surface)

Hand-write the validator as a `combineN` over per-field checks.
Best when the field set is fixed at compile time and you want
maximum control over the constructed value.

```lex
import "./src/error"       as e
import "./src/constraints" as c
import "./src/field"       as f
import "./src/combine"     as cm
import "./src/parse"       as p

type User = { email :: Str, username :: Str, age :: Int }

fn build(em :: Str, un :: Str, ag :: Int) -> User {
  { email: em, username: un, age: ag }
}

fn parse_user(input :: Str) -> Result[User, List[e.Error]] {
  cm.and_then(
    p.from_json(input, ["email", "username", "age"]),
    fn (raw :: User) -> Result[User, List[e.Error]] {
      cm.combine3(
        f.check_str("email",    raw.email,    [StrEmail]),
        f.check_str("username", raw.username, [StrMinLen(3), StrMaxLen(32)]),
        f.check_int("age",      raw.age,      [IntInRange(13, 130)]),
        build
      )
    }
  )
}
```

### Path B — schema-driven (one source of truth)

Describe the schema as a value; runtime validation, JSON Schema
export, TypeScript stubs, and Python pydantic classes all derive
from the same `ModelSchema`. Best when the schema doubles as API
documentation or feeds downstream codegen.

```lex
import "./src/error"       as e
import "./src/constraints" as c
import "./src/schema"      as s
import "./src/validator"   as v

fn user_schema() -> s.ModelSchema {
  {
    title: "User", description: "",
    fields: [
      s.required_str("email",    [StrEmail]),
      s.required_str("username", [StrMinLen(3), StrMaxLen(32)]),
      s.required_int("age",      [IntInRange(13, 130)]),
    ],
  }
}

# One Validator value carries everything downstream.
fn user_validator() -> v.Validator { v.make(user_schema()) }
```

The validator bundle exposes:

```lex
v.validate_str(user_validator(), body)        # runtime validation
v.export_typescript(user_validator())         # TS interfaces
v.export_python(user_validator())             # Pydantic v2 classes
v.export_json_schema_str(user_validator())    # Draft 2020-12
v.export_openapi_str(user_validator())        # OpenAPI 3.1 component
```

### Live output

```bash
$ lex run examples/01_user_signup.lex format_demo
email: not a valid email address [email]
username: must be at least 3 characters [min_len]
username: does not match pattern ^[a-zA-Z0-9_]+$ [pattern]
age: must be >= 13 [min]
password: must be at least 8 characters [min_len]
password: does not match pattern .*[0-9].* [pattern]

$ lex run examples/02_nested.lex format_demo
email: not a valid email address [email]
address.street: must be at least 1 characters [min_len]
address.city:   must be at least 1 characters [min_len]
address.zip:    does not match pattern ^[0-9]{5}$ [pattern]
address.country: does not match pattern ^[A-Z]{2}$ [pattern]

$ lex run examples/03_list_of_items.lex format_demo
customer:               must be at least 1 characters [min_len]
items[0].sku:           does not match pattern ^[A-Z]{3}-[0-9]{4}$ [pattern]
items[1].quantity:      must be > 0 [min]
items[1].price_cents:   must be >= 0 [min]
items[2].sku:           does not match pattern ^[A-Z]{3}-[0-9]{4}$ [pattern]
items[2].quantity:      must be > 0 [min]
```

## What it covers

Lex's type system already catches mismatched shapes at compile time
— that's the whole pitch. So why need pydantic-style runtime checks?
Because data crosses trust boundaries: HTTP bodies, query strings,
config files, env vars. The type system can't tell you a string
carrying a JSON body has a 5-digit zip; that an `Int` parsed from
a request body is between 13 and 130; that a list of items isn't
empty. These are **runtime invariants** the type system deliberately
doesn't model. lex-schema covers the gap with:

- **Rich constraint catalog.** `StrMinLen`, `StrMaxLen`, `StrPattern`,
  `StrEmail`, `StrUrl`, `StrUuid`, `StrOneOf`, `IntInRange`,
  `FloatFinite`, `ListNonEmpty`, `DateBefore`, `DateInRange`, plus
  an open-ended `validate` for custom predicates.
- **Multi-error accumulation.** A bad signup form reports every
  failing field in one shot, not the first one that trips —
  pydantic semantics, applicative implementation.
- **Path-aware errors.** A leaf failure deep in a nested record
  surfaces as `address.zip` or `items[3].quantity`, ready to render
  into a form-validation UI.
- **JSON / TOML / YAML entry points.** Wraps
  `std.{json,toml,yaml}.parse_strict` so the outer parse failure
  uses the same `Errors` shape as the field-level checks.
- **Safe-mode JSON.** A first-class `Json` ADT + recursive-descent
  parser for untrusted input. JSON type mismatches surface as
  typed `Errors`, not VM panics.
- **Coercion.** `str → int / float / bool` for query strings, form
  bodies, env vars — every value arrives as text but downstream
  code wants typed fields.
- **Optional fields + defaults.** Both pydantic patterns
  (`Optional[T] = None`, `T = "default"`) cleanly handled.
- **Discriminated unions.** Route a JSON payload to one of N
  variant-specific validators by a tag field.
- **Datetime bounds.** ISO 8601 parsing + `DateBefore` / `DateAfter`
  / `DateInRange` constraints with canonical-form normalization.
- **Cross-field rules.** `cm.cross_check` for "password and
  confirm_password must match" — pydantic's `@model_validator`
  equivalent.
- **Schema-as-value.** `ModelSchema` describes the field set
  declaratively; one value drives runtime validation *and*
  generates JSON Schema 2020-12 / OpenAPI 3.1 / TypeScript
  interfaces / Pydantic v2 classes.
- **JSON Schema import.** Read a JSON Schema document and
  produce a `ModelSchema` — the inverse of the export path.
- **CLI integration.** Wire `std.cli`'s argv parser through the
  schema; one call validates flags, options, and positionals.
- **Property-based testing.** Generate constraint-respecting
  samples from any schema; assert the round-trip property
  (every generated sample validates).
- **Fuzz driver.** 30+ hand-picked malformed inputs verify every
  validator surfaces `Errors`, never a VM panic.
- **Webhook idempotency.** SHA-256 content keys + a threaded
  `Set[Str]` for at-least-once delivery deduplication.

## Status

Pre-1.0. The surface is small (16 modules, ~3000 lines of pure Lex),
and stable in the sense that no breaking changes are planned for the
listed API. Verified against lex-lang `v0.8.2`:

- Every `src/` module type-checks (`lex check`).
- Every test suite returns `run_all = 0` (~185 cases).
- Every `examples/` demo runs end-to-end.

CHANGELOG carries the exact `lex --version` used. **All seventeen
ergonomic / correctness issues this library filed against lex-lang
have landed** — sixteen closed in `lex 0.8.0`-`0.8.2`; the
remaining three closed in `0.8.2` (`#331` datetime comparison,
`#334` `list.cons`, `#345` alias unfold through closure params).
The library now compiles and runs against vanilla `lex` with
zero workarounds in source.

| Module | Purpose | LoC |
|---|---|---|
| `src/error.lex`         | `Error` type + path helpers + formatting | ~120 |
| `src/constraints.lex`   | `StrCheck`/`IntCheck`/`FloatCheck`/`ListCheck` ADTs + evaluators | ~220 |
| `src/field.lex`         | `check_str`/`check_int`/...; optional variants + `with_default` | ~250 |
| `src/combine.lex`       | `combine2..combine6`, `and_then`, `or_else`, `traverse`, `with_path`, `cross_check` | ~230 |
| `src/parse.lex`         | `from_json` / `from_toml` / `from_yaml` | ~50 |
| `src/coerce.lex`        | `str → int / float / bool` coercion + Map-based `require_*` / `optional_*` | ~190 |
| `src/json_value.lex`    | Safe-mode `Json` ADT + parser + path-aware extractors + stringify | ~640 |
| `src/datetime.lex`      | ISO 8601 datetime + ordered `DateCheck` bounds | ~170 |
| `src/union.lex`         | Discriminated-union (tagged-union) dispatch | ~80 |
| `src/schema.lex`        | `ModelSchema` value + schema-driven `validate` + JSON Schema / OpenAPI export | ~310 |
| `src/schema_import.lex` | JSON Schema → `ModelSchema` (inverse of `to_json_schema`) | ~220 |
| `src/cli.lex`           | `std.cli` ↔ `ModelSchema` bridge (`parse_and_validate_argv`) | ~80 |
| `src/sdk.lex`           | `ModelSchema` → TypeScript / Python codegen for client SDKs | ~340 |
| `src/property.lex`      | Schema-driven sample generation + round-trip property check | ~310 |
| `src/validator.lex`     | `Validator` bundle (schema + pre-computed exports + validate) | ~70 |
| `src/fuzz.lex`          | Malformed-input fuzz driver — every category surfaces as `Err` | ~140 |
| `src/problem.lex`       | RFC 7807 `problem+json` renderer (presets + serialization) | ~120 |
| `src/migrate.lex`       | Schema migrations (`Transform` ADT) + backward-compat check | ~320 |
| `src/form.lex`          | `x-www-form-urlencoded` decoder + dispatch by Content-Type | ~200 |

## Install

The library has no dependencies beyond lex-lang's standard library.
Drop the `src/` directory next to your code and import what you need:

```lex
import "./lex-schema/src/error"       as e
import "./lex-schema/src/constraints" as c
import "./lex-schema/src/field"       as f
import "./lex-schema/src/combine"     as cm
import "./lex-schema/src/parse"       as p
# … plus json_value / schema / validator / etc. as needed.
```

Each module is a separate import because Lex resolves module names
file-by-file; the import is a few lines, no bundler.

## API at a glance

### Errors

```lex
type Error = { path :: Str, code :: Str, message :: Str }

# Construction
e.error(path, code, message)   -> Error
e.single(path, code, message)  -> List[Error]   # one-item list

# Composition
e.concat(a, b)         -> List[Error]
e.flatten([a, b, ...]) -> List[Error]

# Path manipulation
e.prefix_path("address", inner)   # leaf "zip"   -> "address.zip"
e.prefix_index("items", 3, inner) # leaf "name"  -> "items[3].name"

# Diagnostics
e.format(errs)         # "path: message [code]\n..."
```

### Constraints

Each check is a *value* (a variant), not a closure — so you can
inspect, store, and audit them, e.g. `lex audit --calls StrPattern`
lists every regex check in a tree.

```lex
type StrCheck =
    StrNonEmpty | StrMinLen(Int) | StrMaxLen(Int) | StrExactLen(Int)
  | StrPattern(Str) | StrOneOf(List[Str])
  | StrStartsWith(Str) | StrEndsWith(Str)
  | StrEmail | StrUrl | StrUuid

type IntCheck =
    IntMin(Int) | IntMax(Int) | IntInRange(Int, Int)
  | IntEq(Int) | IntOneOf(List[Int])
  | IntPositive | IntNonNegative

type FloatCheck =
    FloatMin(Float) | FloatMax(Float) | FloatInRange(Float, Float)
  | FloatFinite | FloatPositive | FloatNonNegative

type ListCheck =
    ListMinLen(Int) | ListMaxLen(Int) | ListExactLen(Int) | ListNonEmpty

# Plus `datetime.DateCheck` for ISO 8601 bounds:
type DateCheck =
    DateBefore(Str) | DateAfter(Str)
  | DateAtOrBefore(Str) | DateAtOrAfter(Str)
  | DateInRange(Str, Str)
```

### Field validators

Every validator returns `Result[T, List[Error]]` and *accumulates*
every failing constraint for that field — never short-circuits at
the first.

```lex
f.check_str(path, value, [StrEmail, StrMaxLen(254)])
f.check_int(path, value, [IntInRange(0, 130)])
f.check_float(path, value, [FloatFinite, FloatNonNegative])
f.check_bool(path, value)
f.check_list_shape(path, xs, [ListMinLen(1)])
f.check_list_of(name, xs, [ListMaxLen(50)], element_validator)
f.validate(path, value, code, predicate)   # escape hatch

# Optional variants — None is always Ok(None).
f.check_optional_str(path, opt, [StrMaxLen(40)])
f.check_optional_int(path, opt, [IntPositive])
f.check_optional_float(path, opt, [FloatFinite])
f.check_optional_bool(path, opt)

# Defaults — lift Option[T] to T then run the regular checker.
f.with_default(opt, "anonymous")
f.with_default_lazy(opt, fn () -> Str { lookup_default() })
```

### Coercion (string → typed)

For query strings, form posts, env vars — every value arrives as a
`Str` but downstream code wants typed fields with the regular
constraint catalog.

```lex
coerce.coerce_str_to_int(path, "42")          -> Result[Int,   List[Error]]
coerce.coerce_str_to_float(path, "3.14")      -> Result[Float, List[Error]]
coerce.coerce_str_to_bool(path, "yes")        -> Result[Bool,  List[Error]]

# Coerce + validate in one step.
coerce.check_str_as_int(path, s, [IntPositive])
coerce.check_str_as_float(path, s, [FloatNonNegative])

# Pull a value out of a Map[Str, Str] (query strings, form bodies).
coerce.require_int_from_map(qs, "page", [IntPositive])
coerce.require_bool_from_map(qs, "debug")
coerce.optional_str_from_map(qs, "query", [StrMaxLen(120)])
```

Truthy bool words: `true`, `1`, `yes`, `on`, `y`, `t`. Falsy:
`false`, `0`, `no`, `off`, `n`, `f`. Case-insensitive, trimmed.

### Combinators

```lex
# Applicative builders — every failing branch's errors merge.
cm.combine2(ra, rb, builder)
cm.combine3(ra, rb, rc, builder)
cm.combine4(ra, rb, rc, rd, builder)
cm.combine5(ra, rb, rc, rd, re, builder)
cm.combine6(ra, rb, rc, rd, re, rf, builder)

# Monadic chaining — second step only runs if first succeeded.
cm.and_then(r, k)

# Recovery — handler sees the errors, decides the next move.
cm.or_else(r, handler)

# Walk a homogeneous list with per-element validation; errors merge.
cm.traverse(xs, f)

# Prefix every error's path. Used at nested-record boundaries.
cm.with_path("address", inner_result)

# Cross-field rules — run after a successful combineN via and_then.
cm.cross_check(value, [rule1, rule2, ...])   # rule :: T -> Option[List[Error]]
cm.require(value, predicate, path, code, message)  # one-shot

# Lift / fail helpers
cm.pure(v)     # Ok(v)
cm.fail(es)    # Err(es)
```

### Entry points

```lex
# Parse JSON, then validate. Strict mode checks listed top-level fields.
p.from_json(source, ["email", "age"])   -> Result[T, List[Error]]
p.from_toml(source, ["license"])        -> Result[T, List[Error]]
p.from_yaml(source, ["name"])           -> Result[T, List[Error]]
```

### Safe-mode JSON (`json_value`)

For untrusted inputs where the JSON↔Lex type guarantees of the
polymorphic `from_json` path aren't acceptable. The library parses
into a `Json` ADT (`JNull | JBool(Bool) | JInt(Int) | JFloat(Float)
| JStr(Str) | JList(...) | JObj(...)`) and every extractor is
total: a JSON `"thirty"` against an expected `Int` field is a
`type` error, not a VM crash.

```lex
# Parse: O(n) for escape-free strings, O(n²) worst-case for nested
# arrays / objects (blocked on lex-lang#334).
jv.parse(body)                              -> Result[Json, ParseErr]
jv.parse_into_errors(body)                  -> Result[Json, List[Error]]

# Field extractors — same constraint catalog, total over input.
jv.j_str(prefix, json, "email", [StrEmail])
jv.j_int(prefix, json, "age",   [IntInRange(13, 130)])
jv.j_optional_str(prefix, json, "nickname", [StrMaxLen(40)])
jv.j_obj(prefix, json, "address")             # nested record
jv.j_list(prefix, json, "items")              # list of Json

# Dotted-path navigation — no intermediate with_path needed.
jv.get_path(json, "user.address.zip")         -> Option[Json]
jv.j_str_at(json, "user.email", [StrEmail])

# Round-trip-able serializer.
jv.stringify(json)         # compact
jv.stringify_pretty(json)  # 2-space indent
```

### Discriminated unions (`union`)

Route a JSON payload to one of N variant-specific validators based
on a tag field. Three failure modes each tag with their own code:
missing tag → `missing`, wrong type → `type`, unknown discriminator
→ `one_of` (message lists the known set).

```lex
type WebhookEvent =
    Signup({ user_id :: Str, email :: Str })
  | Purchase({ user_id :: Str, cents :: Int })

fn validate_event(j :: jv.Json) -> Result[WebhookEvent, List[Error]] {
  u.discriminate("", j, "event", [
    ("signup",   validate_signup),
    ("purchase", validate_purchase),
  ])
}
```

### Datetime (`datetime`)

ISO 8601 parsing + ordered bound checks. The validator returns the
canonical UTC string so downstream code stores a uniformly ordered
form. Comparisons go through a packed `YYYYMMDDhhmmss` `Int` key
(workaround for lex-lang#331 + #332).

```lex
dt.check_iso_datetime("ts", s, [
  DateAfter("2026-01-01T00:00:00Z"),
  DateAtOrBefore("2026-12-31T23:59:59Z"),
])
dt.check_iso_in_past("created_at", s)     # [time]-flavored preset
dt.check_iso_in_future("expires_at", s)
```

### Schemas as values (`schema`)

A `ModelSchema` is a `List[Field]`, each `Field` carries a
`FieldKind` ADT (`KStr` / `KInt` / `KFloat` / `KBool` / `KArray` /
`KObject`) with constraint lists inline. Three operations off one
schema:

```lex
# Run-time validation, returns normalized Json.
s.validate(schema, json) -> Result[Json, List[Error]]

# Emit JSON Schema 2020-12 (full doc with $schema URI).
s.to_json_schema(schema) -> Json

# Emit OpenAPI 3.1 component schema (no $schema, with title).
s.to_openapi_schema(schema) -> Json

# Builders that pin the nominal type (workaround for lex-lang#328).
s.required_str(name, checks) | s.required_int / float / bool / array / object
s.optional(field)                       # flip required → false
s.with_desc(field, "human-readable")    # add description
```

Round-trip import:

```lex
si.from_str(json_schema_text)  -> Result[ModelSchema, List[Error]]
si.from_json_schema(jv_value)  -> Result[ModelSchema, List[Error]]
```

### Validator bundle (`validator`)

`make(schema)` runs every emitter once and stores results in a
single record. Pass the `Validator` around for both runtime
validation and codegen.

```lex
let val := v.make(user_schema())

v.validate(val, payload_json)        -> Result[Json, List[Error]]
v.validate_str(val, payload_str)     -> Result[Json, List[Error]]
v.export_json_schema_str(val)        -> Str
v.export_openapi_str(val)            -> Str
v.export_typescript(val)             -> Str
v.export_python(val)                 -> Str
v.summary(val)                       -> Str   # "Validator{title=..., fields=N}"
```

### SDK codegen (`sdk`)

```lex
sdk.to_typescript(schema)    # export interface User { ... }
sdk.to_python(schema)        # class User(BaseModel): ...
```

`StrOneOf` renders as `"a" | "b"` (TS) / `Literal["a", "b"]` (Py).
Nested records emit their own interface/class. Optional fields use
`?:` / `Optional[T]`. Constraint catalog maps to JSDoc hints (TS)
and pydantic field args (Py).

### CLI integration (`cli`)

```lex
cl.parse_and_validate_argv(spec, argv, schema)
  -> Result[Json, List[Error]]

cl.help(spec)                                   # human-readable
cl.describe(spec)                               # machine-readable JSON
```

Three error sources tag distinctly: `cli.parse` failure (code
`parse`), bridge decode (`parse`), constraint failure (per-rule).

### Property-based testing (`property`)

```lex
# Pure + deterministic via std.random's SplitMix64.
p.generate(schema, rng)              -> (Json, Rng)

# n round-trip cycles. Ok(n) on a clean sweep.
p.round_trip(schema, n, seed)        -> Result[Int, List[Error]]
```

Constraint-respecting generators for str (length, format, OneOf),
int (range, OneOf), float (range), bool, list (length, element-
kind), and nested objects.

### Fuzz driver (`fuzz`)

```lex
fz.run_all(schema)              -> List[Tally]
fz.count_escapes(schema)        -> Int             # 0 = every input errored
fz.format_tallies(tallies)      -> Str
```

Five hand-picked catalogues (parse failures, type mismatches,
missing required, constraint failures, deep nesting) run against
the schema. The pass condition is `count_escapes == 0` *and* no VM
panic — the latter enforced by the run completing.

## Examples

All examples in `examples/` are runnable end-to-end via
`lex run <file> <fn> [args]`. Some require effect grants
(`--allow-effects net,io,time`); each example's header carries the
exact invocation.

| File | Demonstrates |
|---|---|
| `01_user_signup.lex`           | One-shot signup form validation, error accumulation |
| `02_nested.lex`                | Nested record (User → Address) with `with_path` |
| `03_list_of_items.lex`         | Indexed list-of-records validation (`items[3].sku`) |
| `04_api_request.lex`           | HTTP endpoint pipeline: parse → validate → 200/400 |
| `05_optional_and_defaults.lex` | `Option[T]` fields + `with_default` over a `Map[Str, Str]` source |
| `06_coerce_query_string.lex`   | Query-string parsing with coercion + constraints |
| `07_safe_mode_json.lex`        | Safe-mode validation via the `Json` ADT — total over malformed input |
| `08_discriminated_union.lex`   | Webhook payload routing into a Lex ADT via `u.discriminate` |
| `09_datetime_and_paths.lex`    | ISO 8601 bounds + dotted-path extraction (`organizer.email`) |
| `10_schema_introspection.lex`  | `ModelSchema` value + run-time validation + JSON Schema / OpenAPI export |
| `11_cli_args.lex`              | `std.cli` argv → ModelSchema validation in one call |
| `12_cross_field.lex`           | Cross-field rules: password match, date ordering |
| `13_property_test.lex`         | 200 generate→validate cycles against a User schema; all pass |
| `14_json_schema_round_trip.lex` | Emit JSON Schema, parse it back, validate the same payload through both |
| `15_sdk_export.lex`            | Generate TypeScript interfaces + Pydantic v2 classes from one schema |
| `16_validation_service.lex`    | HTTP `/v1/validate` service accepting `{schema, payload}` over the wire |
| `17_webhook_dedup.lex`         | SHA-256 idempotency keying on top of the discriminator pattern |
| `18_cli_codegen.lex`           | Load a JSON Schema file from disk, emit TS / Python / JSON-Schema text |
| `19_fuzz_driver.lex`           | Run 30+ malformed inputs through a schema; assert every one surfaces as `Err` |

Run the bad-input demos to see the full error trail:

```bash
$ lex run examples/01_user_signup.lex format_demo
$ lex run examples/02_nested.lex      format_demo
$ lex run examples/03_list_of_items.lex format_demo
$ lex run examples/08_discriminated_union.lex format_bad_field
$ lex run examples/19_fuzz_driver.lex demo_tallies   # "parse_failures: 12/12 ..."
```

Generate an SDK off one schema:

```bash
$ lex run examples/15_sdk_export.lex demo_typescript
$ lex run examples/15_sdk_export.lex demo_python
$ lex run examples/15_sdk_export.lex demo_json_schema
```

## Tests

17 suites, ~185 cases. The full sweep:

```bash
for f in tests/test_*.lex; do
  echo -n "$(basename $f): "
  lex run --allow-effects time "$f" run_all
done
```

Reference output: every line ends in `0` (zero failures).

Each module has its own suite:

```bash
lex run tests/test_error.lex         run_all   # ~11 cases
lex run tests/test_constraints.lex   run_all   # ~21 cases
lex run tests/test_field.lex         run_all   # ~8  cases
lex run tests/test_combine.lex       run_all   # ~11 cases
lex run tests/test_coerce.lex        run_all   # ~12 cases
lex run tests/test_json_value.lex    run_all   # ~23 cases
lex run tests/test_json_extra.lex    run_all   # ~12 cases
lex run tests/test_union.lex         run_all   # ~6  cases
lex run tests/test_datetime.lex      run_all   # ~13 cases
lex run tests/test_schema.lex        run_all   # ~13 cases
lex run tests/test_cli.lex           run_all   # ~6  cases
lex run tests/test_cross_field.lex   run_all   # ~7  cases
lex run tests/test_property.lex      run_all   # ~8  cases
lex run tests/test_schema_import.lex run_all   # ~7  cases
lex run tests/test_sdk.lex           run_all   # ~12 cases
lex run tests/test_validator.lex     run_all   # ~9  cases
lex run tests/test_fuzz.lex          run_all   # ~4  cases
```

Coverage spans every constraint's pass/fail branches, error
accumulation in `combineN`, path manipulation, coercion,
the Json ADT parser + extractors + round-trip, discriminated-union
dispatch, ISO 8601 bounds, schema-driven validation + JSON Schema /
OpenAPI emission, SDK codegen for TS + Python, the validator
bundle, property-based round-trip on randomly-generated samples,
and the fuzz driver's malformed-input catalogues.

## Design notes

### Why constraints are variants, not closures

In a closure-based design (pydantic-py: `Field(min_length=1)`),
each constraint is an opaque callable. We instead model them as
ADT variants:

```lex
type StrCheck = StrMinLen(Int) | StrMaxLen(Int) | ...
```

Three concrete payoffs:

1. **Inspectable by `lex audit`.** `lex audit --calls StrPattern`
   lists every regex constraint in a tree. Closures vanish into
   call-site bodies.
2. **Codegen-friendly.** `sdk.to_typescript`, `to_python`, and
   `s.to_json_schema` all walk the constraint list and emit
   appropriate annotations / Field-args / JSON Schema keywords.
   A closure-based design would lose this for free.
3. **Cheaper.** A variant is a tagged record; a closure carries
   captures + an indirect call.

The trade-off is the fixed catalog. To add a new constraint kind,
add a variant + a branch in `eval_xxx` + a branch in each codegen
emitter. The library leans into "the small total surface" rule
from the Lex design rules — better four well-named checks than
a thousand one-off lambdas.

For genuinely custom predicates the `f.validate(path, value,
code, predicate)` escape hatch takes a closure directly, and
`cm.cross_check` takes a list of closures for model-level rules.

### Why applicative, not monadic, for sibling fields

Sibling fields should report failures *all at once*. Monadic
short-circuit (`Result.and_then`) hides the second field's errors
behind the first's. We use applicative `combine2..combine6` so a
form with three bad fields surfaces three errors, not
one-then-fix-then-rerun-three-times.

When one field's *type* depends on another's value (i.e., a real
dependency), use `cm.and_then` to chain. That's the rare case;
sibling validation is the common one.

### Two trust models around JSON

`p.from_json` wraps `std.json.parse_strict`. The standard library
parser does field-presence checks (#168), but it doesn't yet do
deep type validation: a JSON `{"age": "thirty"}` parsed against a
Lex record `{age :: Int}` returns a record with a `Value::Str` in
the `age` slot, which crashes the first time downstream code does
arithmetic on it. The acceptance test for the full fix is tracked
at [lex-lang#322](https://github.com/alpibrusl/lex-lang/issues/322);
when it lands, `p.from_json` becomes fully runtime-safe end-to-end
with no surface change.

For now, two paths cover both threat models:

- **Trusted-producer mode** — `p.from_json` + field validators.
  Lightweight; relies on the JSON producer (another Lex service,
  a typed client, your own code) emitting types that match the
  declared Lex record.
- **Safe mode** — `jv.parse` + `jv.j_str` / `jv.j_int` extractors.
  Fully total over input. The parser is O(n) for escape-free
  strings and O(n²) worst-case for nested arrays / objects
  (the latter blocked on [lex-lang#334](https://github.com/alpibrusl/lex-lang/issues/334)).

Both produce the same `Errors` shape; callers swap freely as the
trust model changes.

### Pure + deterministic by construction

Every `src/*.lex` module type-checks under `lex check` with no
effects required. `datetime.check_iso_in_past` / `_in_future`
carry `[time]` because they read the wall clock; everything else
is pure. Property-based test generation is deterministic via
`std.random`'s SplitMix64 — the same seed produces the same
sample on every platform.

### Issues filed against lex-lang

Seventeen small ergonomic or correctness gaps came up while
building the library. **All seventeen landed in lex 0.8.0-0.8.2.**
The cleanup commits restored the library to a no-workaround
state — every spelling in source is the direct, idiomatic Lex.

| Issue | Status | Topic |
|---|---|---|
| [#319](https://github.com/alpibrusl/lex-lang/issues/319) | ✅ 0.8.0 | Inline type ascription `(expr :: Type)` |
| [#320](https://github.com/alpibrusl/lex-lang/issues/320) | ✅ 0.8.0 | `option.unwrap_or_else` |
| [#321](https://github.com/alpibrusl/lex-lang/issues/321) | ✅ 0.8.0 | `list.enumerate` |
| [#322](https://github.com/alpibrusl/lex-lang/issues/322) | ✅ 0.8.0 | Deep JSON type validation in `json.parse_strict` |
| [#323](https://github.com/alpibrusl/lex-lang/issues/323) | ✅ 0.8.0 (simple positions) → fully closed by #345 in 0.8.2 | Type-alias asymmetry |
| [#324](https://github.com/alpibrusl/lex-lang/issues/324) | ✅ 0.8.0 | `_` as a lambda parameter name |
| [#325](https://github.com/alpibrusl/lex-lang/issues/325) | ✅ 0.8.0 | Scientific-notation float literals |
| [#326](https://github.com/alpibrusl/lex-lang/issues/326) | ✅ 0.8.0 | `regex.is_match_str` to skip the compile round-trip |
| [#328](https://github.com/alpibrusl/lex-lang/issues/328) | ✅ 0.8.0 | Record-alias coercion under nested constructors |
| [#329](https://github.com/alpibrusl/lex-lang/issues/329) | ✅ 0.8.0 | Negative integer literals in match patterns |
| [#331](https://github.com/alpibrusl/lex-lang/issues/331) | ✅ 0.8.2 | `datetime.before` / `after` / `compare` + `std.duration` |
| [#332](https://github.com/alpibrusl/lex-lang/issues/332) | ✅ 0.8.0 | `Str < Str` works at runtime |
| [#334](https://github.com/alpibrusl/lex-lang/issues/334) | ✅ 0.8.0 (`list.reverse`) + 0.8.2 (`list.cons`) | O(n) list builders |
| [#337](https://github.com/alpibrusl/lex-lang/issues/337) | ✅ 0.8.0 | Constructor-pattern fail path leaks scrutinee |
| [#338](https://github.com/alpibrusl/lex-lang/issues/338) | ✅ 0.8.0 | `list.sort_by[T, K]` for canonicalization |
| [#339](https://github.com/alpibrusl/lex-lang/issues/339) | ✅ 0.8.0 | Top-level fn shadowing a cross-module param |
| [#345](https://github.com/alpibrusl/lex-lang/issues/345) | ✅ 0.8.2 | Type-alias unfold reaches polymorphic-stdlib closure params |

**No workarounds remain in source.** The library compiles and
runs against vanilla `lex 0.8.2` with the direct, idiomatic
spellings:

- `type Errors = List[Error]` is the canonical alias throughout.
- `src/datetime.lex` calls `datetime.before` / `datetime.after`
  / `datetime.compare` directly on parsed `Instant`s.
- `src/json_value.lex` parser is O(n) via `list.cons` +
  `list.reverse` for array / object builders.

## License

EUPL-1.2 — to match the parent `lex-lang` project.
