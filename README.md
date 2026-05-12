# lex-pydantic

A pydantic-style **runtime validation library** for [lex-lang](https://github.com/alpibrusl/lex-lang).
Written in pure Lex — no Rust shims, no host hooks, no native code. It
runs on stock `lex run` / `lex check` and uses only the existing
stdlib (`std.str`, `std.list`, `std.regex`, `std.json`, ...).

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

fn parse_user(input :: Str) -> Result[User, e.Errors] {
  cm.and_then(
    p.from_json(input, ["email", "username", "age"]),
    fn (raw :: User) -> Result[User, e.Errors] {
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

```bash
$ lex run examples/01_user_signup.lex format_demo
"email: not a valid email address [email]
username: must be at least 3 characters [min_len]
username: does not match pattern ^[a-zA-Z0-9_]+$ [pattern]
age: must be >= 13 [min]
password: must be at least 8 characters [min_len]
password: does not match pattern .*[0-9].* [pattern]"
```

## Why a validation library at all?

Lex's type system already catches mismatched shapes at compile time —
that's the whole pitch. So why need pydantic-style runtime checks?

Because data crosses trust boundaries. The type system can't tell you
that a string carrying a JSON body has a 5-digit zip; that an `Int`
parsed from a request body is between 13 and 130; that a list of
items isn't empty. These are **runtime invariants** the type system
deliberately doesn't model. `lex-pydantic` covers the gap:

- **Constraints beyond types.** `StrMinLen`, `IntInRange`, `StrPattern`,
  `StrEmail`, `ListNonEmpty`, plus an open-ended `validate` for
  custom predicates.
- **Multi-error accumulation.** A bad signup form reports every
  failing field in one shot, not the first one that trips. Pydantic
  semantics, applicative implementation.
- **Path-aware errors.** A leaf failure deep in a nested record
  surfaces as `address.zip` or `items[3].quantity`, ready to render
  into a form-validation UI.
- **JSON / TOML / YAML entry points.** Wraps `std.{json,toml,yaml}.parse_strict`
  to surface the outer parse failure as the same `Errors` shape as
  the field-level checks — a uniform `Result[T, Errors]` end-to-end.

## Status

Pre-1.0. The surface is small (5 modules, ~700 lines), and stable in
the sense that no breaking changes are planned for the listed API.
Tested against lex-lang `main` (rev pinned in `CHANGELOG.md`).

| Module | Purpose | LoC |
|---|---|---|
| `src/error.lex`       | `Error` / `Errors` types + path helpers + formatting | ~120 |
| `src/constraints.lex` | `StrCheck`/`IntCheck`/`FloatCheck`/`ListCheck` ADTs + evaluators | ~220 |
| `src/field.lex`       | `check_str` / `check_int` / `check_float` / `check_list_of` | ~180 |
| `src/combine.lex`     | `combine2..combine6`, `and_then`, `or_else`, `traverse`, `with_path` | ~180 |
| `src/parse.lex`       | `from_json` / `from_toml` / `from_yaml` | ~50 |

## Install

The library has no dependencies beyond lex-lang's standard library.
Drop the `src/` directory next to your code and import what you need:

```lex
import "./lex-pydantic/src/error"       as e
import "./lex-pydantic/src/constraints" as c
import "./lex-pydantic/src/field"       as f
import "./lex-pydantic/src/combine"     as cm
import "./lex-pydantic/src/parse"       as p
```

Each module is a separate import because Lex resolves
module names file-by-file; the import is a few lines, no bundler.

## API at a glance

### Errors

```lex
type Error  = { path :: Str, code :: Str, message :: Str }
type Errors = List[Error]

# Construction
e.error(path, code, message)   -> Error
e.single(path, code, message)  -> Errors        # one-item list

# Composition
e.concat(a, b)        -> Errors
e.flatten([a, b, ...]) -> Errors

# Path manipulation
e.prefix_path("address", inner)   # leaf "zip"   -> "address.zip"
e.prefix_index("items", 3, inner) # leaf "name"  -> "items[3].name"

# Diagnostics
e.format(errs)         # "path: message [code]\n..."
```

### Constraints

Each check is a *value* (a variant), not a closure — so you can
inspect, store, and audit them, e.g.
`lex audit --calls StrPattern` lists every regex check in a tree.

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
```

### Field validators

Every validator returns `Result[T, Errors]` and *accumulates* every
failing constraint for that field — never short-circuits at the first.

```lex
f.check_str(path, value, [StrEmail, StrMaxLen(254)])
f.check_int(path, value, [IntInRange(0, 130)])
f.check_float(path, value, [FloatFinite, FloatNonNegative])
f.check_bool(path, value)
f.check_list_shape(path, xs, [ListMinLen(1)])
f.check_list_of(name, xs, [ListMaxLen(50)], element_validator)
f.validate(path, value, code, predicate)   # escape hatch
```

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

# Lift / fail helpers
cm.pure(v)     # Ok(v)
cm.fail(es)    # Err(es)
```

### Entry points

```lex
# Parse JSON, then validate. Strict mode checks listed top-level fields.
p.from_json(source, ["email", "age"])   -> Result[T, Errors]
p.from_toml(source, ["license"])        -> Result[T, Errors]
p.from_yaml(source, ["name"])           -> Result[T, Errors]
```

## Examples

All examples in `examples/` are runnable end-to-end via
`lex run <file> <fn> [args]`.

| File | Demonstrates |
|---|---|
| `01_user_signup.lex`  | One-shot signup form validation, error accumulation |
| `02_nested.lex`       | Nested record (User → Address) with `with_path` |
| `03_list_of_items.lex` | Indexed list-of-records validation (`items[3].sku`) |
| `04_api_request.lex`  | HTTP endpoint pipeline: parse → validate → 200/400 |

Run the bad-input demos to see the full error trail:

```bash
$ lex run examples/01_user_signup.lex format_demo
$ lex run examples/02_nested.lex      format_demo
$ lex run examples/03_list_of_items.lex format_demo
```

## Tests

```bash
lex run tests/test_constraints.lex run_all   # 0 ⇒ all pass
lex run tests/test_field.lex       run_all
lex run tests/test_combine.lex     run_all
lex run tests/test_error.lex       run_all
```

The suite covers ~50 cases across the four modules — each
constraint's pass and fail branches, error accumulation in
`combineN`, path manipulation, and the recovery combinators.

## Design notes

### Why constraints are variants, not closures

In a closure-based design (pydantic-py: `Field(min_length=1)`), each
constraint is an opaque callable. We instead model them as ADT
variants:

```lex
type StrCheck = StrMinLen(Int) | StrMaxLen(Int) | ...
```

Three concrete payoffs:

1. **Inspectable by `lex audit`.** `lex audit --calls StrPattern` lists
   every regex constraint in a tree. Closures vanish into call-site bodies.
2. **No closure-in-record surprises.** Lex's closures-in-records
   support landed late (#169); ADTs are first-class from day one.
3. **Cheaper.** A variant is a tagged record; a closure carries
   captures + an indirect call.

The trade-off is the fixed catalog. To add a new constraint kind, add
a variant + a branch in `eval_xxx`. The library leans into "the small
total surface" rule from the Lex design rules — better four well-named
checks than a thousand one-off lambdas.

For genuinely custom predicates the `f.validate(path, value, code,
predicate)` escape hatch takes a closure directly.

### Why applicative, not monadic, for sibling fields

Sibling fields should report failures *all at once*. Monadic
short-circuit (`Result.and_then`) hides the second field's errors
behind the first's. We use applicative `combine2..combine6` so a
form with three bad fields surfaces three errors, not one-then-fix-
then-rerun-three-times.

When one field's *type* depends on another's value (i.e., a real
dependency), use `cm.and_then` to chain. That's the rare case;
sibling validation is the common one.

### The trust model around `from_json`

`p.from_json` wraps `std.json.parse_strict`. The standard library
parser does field-presence checks (#168), but it doesn't yet do deep
type validation: a JSON `{"age": "thirty"}` parsed against a Lex
record `{age :: Int}` returns a record with a `Value::Str` in the
`age` slot, which crashes the first time downstream code does
arithmetic on it.

The library treats this as a `std.json` concern. The acceptance test
for the future fix is tracked at
[lex-lang#168](https://github.com/alpibrusl/lex-lang/issues/168);
when it lands, `lex-pydantic` becomes fully runtime-safe end-to-end
with no changes to its surface. For now, well-typed JSON producers
(other Lex services, statically-typed clients) are safe; arbitrary
internet input has the same caveat lex itself has today.

### Issues filed against lex-lang

While building this library a few small ergonomic gaps came up. They
don't block any of the features here, but they'd make the code
cleaner. Each is filed under the `lex-pydantic` label on
[`alpibrusl/lex-lang`](https://github.com/alpibrusl/lex-lang):

- [#319](https://github.com/alpibrusl/lex-lang/issues/319) — inline
  type ascription `(expr :: Type)`
- [#320](https://github.com/alpibrusl/lex-lang/issues/320) —
  `option.unwrap_or_else`
- [#321](https://github.com/alpibrusl/lex-lang/issues/321) —
  `list.enumerate`
- [#322](https://github.com/alpibrusl/lex-lang/issues/322) — deep
  JSON type validation under `json.parse_strict`

## License

EUPL-1.2 — to match the parent `lex-lang` project.
