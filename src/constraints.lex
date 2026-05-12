# lex-pydantic — constraint datatypes + their evaluators
#
# Constraints are *values*, not closures. Each typed validator
# (`check_str`, `check_int`, ...) takes a `List[XxxCheck]` and runs
# each check in turn. Modeling them as variants keeps every active
# rule readable from the call site (no opaque function bodies), and
# `audit`-friendly: a search like `lex audit --calls StrPattern`
# instantly lists every regex check in a codebase.
#
# Each evaluator returns `Option[Str]`: `None` means "passed",
# `Some(msg)` means "failed with this message". The outer
# `check_xxx` translates these into `error.Error` records.
#
# Effects: none. The whole module is pure builtins.

import "std.str"   as str
import "std.int"  as int
import "std.float" as float
import "std.list"  as list
import "std.math"  as math
import "std.regex" as regex

# ---- Constraint datatypes -----------------------------------------

# Predicates on `Str` fields. Names are prefixed `Str` so variants
# don't collide with `IntMin` / `FloatMin` in the same scope.
type StrCheck =
    StrNonEmpty
  | StrMinLen(Int)
  | StrMaxLen(Int)
  | StrExactLen(Int)
  | StrPattern(Str)
  | StrOneOf(List[Str])
  | StrStartsWith(Str)
  | StrEndsWith(Str)
  | StrEmail
  | StrUrl
  | StrUuid

# Predicates on `Int` fields.
type IntCheck =
    IntMin(Int)
  | IntMax(Int)
  | IntInRange(Int, Int)
  | IntEq(Int)
  | IntOneOf(List[Int])
  | IntPositive
  | IntNonNegative

# Predicates on `Float` fields.
type FloatCheck =
    FloatMin(Float)
  | FloatMax(Float)
  | FloatInRange(Float, Float)
  | FloatFinite
  | FloatPositive
  | FloatNonNegative

# Predicates on `List[T]`. The element validator is applied to each
# entry separately via `check_list_of`; these checks only see the
# list's *shape*.
type ListCheck =
    ListMinLen(Int)
  | ListMaxLen(Int)
  | ListExactLen(Int)
  | ListNonEmpty

# ---- Built-in regex patterns --------------------------------------
#
# Conservative defaults. Callers wanting different policy can pass
# `StrPattern("...")` with their own regex. All patterns are
# anchored end-to-end so a partial match doesn't count.

# Practical email regex (per HTML5 form validation). Allows local
# parts with `+`, dots, etc. Doesn't try to enforce RFC 5322 — that
# spec admits weirdness no real service accepts.
fn email_pattern() -> Str {
  "^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$"
}

# http/https URL. The path/query parts are deliberately loose; tighter
# validation belongs in `StrPattern` per-caller.
fn url_pattern() -> Str {
  "^https?://[a-zA-Z0-9.-]+(:[0-9]+)?(/[^ \\t\\r\\n]*)?$"
}

# Canonical 8-4-4-4-12 UUID hex form. Version/variant bits aren't
# checked — most callers want shape, not RFC 4122 conformance.
fn uuid_pattern() -> Str {
  "^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$"
}

# ---- Per-constraint evaluators ------------------------------------

fn eval_str(c :: StrCheck, s :: Str) -> Option[Str] {
  match c {
    StrNonEmpty => if str.is_empty(s) {
      Some("must not be empty")
    } else { None },
    StrMinLen(n) => if str.len(s) < n {
      Some(str.concat("must be at least ", str.concat(int.to_str(n), " characters")))
    } else { None },
    StrMaxLen(n) => if str.len(s) > n {
      Some(str.concat("must be at most ", str.concat(int.to_str(n), " characters")))
    } else { None },
    StrExactLen(n) => if str.len(s) == n { None } else {
      Some(str.concat("must be exactly ", str.concat(int.to_str(n), " characters")))
    },
    StrPattern(p) => if re_match(p, s) { None } else {
      Some(str.concat("does not match pattern ", p))
    },
    StrOneOf(opts) => if list_contains_str(opts, s) { None } else {
      Some(str.concat("must be one of ", str.join(opts, ", ")))
    },
    StrStartsWith(p) => if str.starts_with(s, p) { None } else {
      Some(str.concat("must start with ", p))
    },
    StrEndsWith(p) => if str.ends_with(s, p) { None } else {
      Some(str.concat("must end with ", p))
    },
    StrEmail => if re_match(email_pattern(), s) { None } else {
      Some("not a valid email address")
    },
    StrUrl => if re_match(url_pattern(), s) { None } else {
      Some("not a valid http(s) URL")
    },
    StrUuid => if re_match(uuid_pattern(), s) { None } else {
      Some("not a valid UUID")
    },
  }
}

fn eval_int(c :: IntCheck, n :: Int) -> Option[Str] {
  match c {
    IntMin(lo) => if n < lo {
      Some(str.concat("must be >= ", int.to_str(lo)))
    } else { None },
    IntMax(hi) => if n > hi {
      Some(str.concat("must be <= ", int.to_str(hi)))
    } else { None },
    IntInRange(lo, hi) => if n < lo {
      Some(str.concat("must be >= ", int.to_str(lo)))
    } else {
      if n > hi { Some(str.concat("must be <= ", int.to_str(hi))) }
      else      { None }
    },
    IntEq(target) => if n == target { None } else {
      Some(str.concat("must equal ", int.to_str(target)))
    },
    IntOneOf(opts) => if list_contains_int(opts, n) { None } else {
      Some(str.concat("must be one of ",
        str.join(list.map(opts, fn (x :: Int) -> Str { int.to_str(x) }), ", ")))
    },
    IntPositive => if n > 0 { None } else { Some("must be > 0") },
    IntNonNegative => if n >= 0 { None } else { Some("must be >= 0") },
  }
}

fn eval_float(c :: FloatCheck, x :: Float) -> Option[Str] {
  match c {
    FloatMin(lo) => if x < lo {
      Some(str.concat("must be >= ", float.to_str(lo)))
    } else { None },
    FloatMax(hi) => if x > hi {
      Some(str.concat("must be <= ", float.to_str(hi)))
    } else { None },
    FloatInRange(lo, hi) => if x < lo {
      Some(str.concat("must be >= ", float.to_str(lo)))
    } else {
      if x > hi { Some(str.concat("must be <= ", float.to_str(hi))) }
      else      { None }
    },
    # NaN detection: NaN is the only float for which `x != x`. We can
    # rule out infinities by comparing against `math.pow(10, 309)`
    # (which evaluates to +inf at runtime since f64 tops out near
    # 1.8e308 and Lex floats have no exponent literal syntax).
    FloatFinite => if (x == x) and (math.abs(x) < math.pow(10.0, 309.0)) {
      None
    } else { Some("must be a finite number") },
    FloatPositive => if x > 0.0 { None } else { Some("must be > 0") },
    FloatNonNegative => if x >= 0.0 { None } else { Some("must be >= 0") },
  }
}

fn eval_list(c :: ListCheck, n :: Int) -> Option[Str] {
  match c {
    ListMinLen(m) => if n < m {
      Some(str.concat("must have at least ", str.concat(int.to_str(m), " items")))
    } else { None },
    ListMaxLen(m) => if n > m {
      Some(str.concat("must have at most ", str.concat(int.to_str(m), " items")))
    } else { None },
    ListExactLen(m) => if n == m { None } else {
      Some(str.concat("must have exactly ", str.concat(int.to_str(m), " items")))
    },
    ListNonEmpty => if n > 0 { None } else { Some("must not be empty") },
  }
}

# ---- Internal helpers ---------------------------------------------

# Pattern → Bool wrapper. `regex.is_match` is typed `Regex -> Str -> Bool`
# in lex-types, so callers have to round-trip through `regex.compile`
# even though the runtime stores the compiled regex as the original
# pattern string anyway. Bad patterns surface as a non-match — same
# behavior as a successful no-match.
fn re_match(pattern :: Str, s :: Str) -> Bool {
  match regex.compile(pattern) {
    Ok(r)  => regex.is_match(r, s),
    Err(_) => false,
  }
}

fn list_contains_str(xs :: List[Str], needle :: Str) -> Bool {
  list.fold(xs, false, fn (acc :: Bool, x :: Str) -> Bool {
    acc or (x == needle)
  })
}

fn list_contains_int(xs :: List[Int], needle :: Int) -> Bool {
  list.fold(xs, false, fn (acc :: Bool, x :: Int) -> Bool {
    acc or (x == needle)
  })
}
