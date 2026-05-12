# lex-pydantic — datetime constraints
#
# Dates arrive in payloads as ISO 8601 strings
# (`"2026-05-12T14:30:00Z"`). We use the std.datetime parser to
# *validate* the syntax, then express bounds as ISO 8601 strings
# themselves. ISO 8601 in canonical form (UTC `Z`, no fractional
# seconds, lex-order matches chronological order) sorts
# lexicographically — so string `<` is the same as time-ordering
# for the canonical form.
#
# When `Instant` gains a comparison surface upstream
# (lex-lang#331), we'll swap the implementation behind the same
# `DateCheck` constraint surface — no caller change.
#
# Effects: pure for parse-and-bound; `[time]` for the `now`-relative
# checks (`check_iso_in_past`, etc.).

import "std.str"      as str
import "std.list"     as list
import "std.datetime" as datetime

import "./error" as e

# ---- DateCheck variants -------------------------------------------
#
# Bounds are canonical ISO 8601 strings — `"2026-01-01T00:00:00Z"`
# style. Non-canonical forms (with `+05:30`, fractional seconds,
# etc.) won't compare correctly with `<`; the constraint emitters
# below funnel everything through `datetime.parse_iso` +
# `datetime.format_iso` first so the *normalized* string is what
# we compare against.

type DateCheck =
    DateBefore(Str)
  | DateAfter(Str)
  | DateAtOrBefore(Str)
  | DateAtOrAfter(Str)
  | DateInRange(Str, Str)

# Pack an `Instant` into a single comparable `Int` of shape
# `YYYYMMDDhhmmss`. UTC throughout so callers don't pay an effect
# tax just to compare. This is the workaround for lex-lang#331
# (`Instant` has no ordering surface) and lex-lang#332 (`Str < Str`
# fails at runtime); when either lands we collapse back to the
# direct form.
fn instant_sort_key(ins :: Instant) -> Int {
  match datetime.to_components(ins, Utc) {
    Err(_)  => 0,
    Ok(c)   =>
        c.year   * 10000000000
      + c.month  *   100000000
      + c.day    *     1000000
      + c.hour   *       10000
      + c.minute *         100
      + c.second
  }
}

# Bounds come in as Str (ISO 8601); we re-parse on each eval. The
# expense is one parse per check per record — fine at the
# constraint-list sizes typical of validation. If a hot path needs
# pre-parsed bounds, fold them into a wrapper that calls
# `parse_iso` once and reuses the key.
fn bound_key(s :: Str) -> Int {
  match datetime.parse_iso(s) {
    Err(_)  => 0,
    Ok(ins) => instant_sort_key(ins),
  }
}

fn eval_date(c :: DateCheck, ts_key :: Int) -> Option[Str] {
  match c {
    DateBefore(hi) => {
      let h := bound_key(hi)
      if ts_key < h { None } else { Some(str.concat("must be before ", hi)) }
    },
    DateAtOrBefore(hi) => {
      let h := bound_key(hi)
      if ts_key <= h { None } else { Some(str.concat("must be at or before ", hi)) }
    },
    DateAfter(lo) => {
      let l := bound_key(lo)
      if ts_key > l { None } else { Some(str.concat("must be after ", lo)) }
    },
    DateAtOrAfter(lo) => {
      let l := bound_key(lo)
      if ts_key >= l { None } else { Some(str.concat("must be at or after ", lo)) }
    },
    DateInRange(lo, hi) => {
      let l := bound_key(lo)
      let h := bound_key(hi)
      if ts_key < l {
        Some(str.concat("must be at or after ", lo))
      } else {
        if ts_key > h { Some(str.concat("must be at or before ", hi)) }
        else          { None }
      }
    },
  }
}

fn date_code(c :: DateCheck) -> Str {
  match c {
    DateBefore(_)      => e.code_max(),
    DateAtOrBefore(_)  => e.code_max(),
    DateAfter(_)       => e.code_min(),
    DateAtOrAfter(_)   => e.code_min(),
    DateInRange(_, _)  => e.code_min(),
  }
}

# ---- Field validator entry points ---------------------------------

# Parse `s` as ISO 8601, then run the bound checks. Returns the
# canonical-form string so downstream code stores a uniformly
# ordered representation.
fn check_iso_datetime(
  path :: Str,
  s :: Str,
  checks :: List[DateCheck]
) -> Result[Str, List[e.Error]] {
  match datetime.parse_iso(s) {
    Err(m) => Err(e.single(path, e.code_type(),
      str.concat("not a valid ISO 8601 datetime: ", m))),
    Ok(ins) => {
      let canonical := datetime.format_iso(ins)
      let key := instant_sort_key(ins)
      let errs := run_date_checks(path, key, checks)
      if e.is_ok(errs) { Ok(canonical) } else { Err(errs) }
    },
  }
}

# `strftime`-style fallback for when the input isn't strict ISO 8601
# but still has a known format. The parsed Instant is re-formatted
# into canonical ISO 8601 for storage and comparison.
fn check_datetime(
  path :: Str,
  s :: Str,
  format :: Str,
  checks :: List[DateCheck]
) -> Result[Str, List[e.Error]] {
  match datetime.parse(s, format) {
    Err(m) => Err(e.single(path, e.code_type(),
      str.concat("date didn't match format `",
        str.concat(format, str.concat("`: ", m))))),
    Ok(ins) => {
      let canonical := datetime.format_iso(ins)
      let key := instant_sort_key(ins)
      let errs := run_date_checks(path, key, checks)
      if e.is_ok(errs) { Ok(canonical) } else { Err(errs) }
    },
  }
}

# Parse-only: returns the canonical ISO 8601 form of `s` without
# any bound check. Useful as the leaf step of a `check_str`
# pipeline where you only care that the field is well-formed.
fn parse_iso(path :: Str, s :: Str) -> Result[Str, List[e.Error]] {
  check_iso_datetime(path, s, [])
}

# ---- Now-relative presets -----------------------------------------
#
# Built on `datetime.now()` so the bound moves with wall-clock
# time. The functions carry `[time]`; the call site inherits it.
# That's intentional — readers see the time dependency at the
# type level.

# Must be in the past or now.
fn check_iso_in_past(
  path :: Str,
  s :: Str
) -> [time] Result[Str, List[e.Error]] {
  let now_iso := datetime.format_iso(datetime.now())
  check_iso_datetime(path, s, [DateAtOrBefore(now_iso)])
}

# Must be in the future or now.
fn check_iso_in_future(
  path :: Str,
  s :: Str
) -> [time] Result[Str, List[e.Error]] {
  let now_iso := datetime.format_iso(datetime.now())
  check_iso_datetime(path, s, [DateAtOrAfter(now_iso)])
}

# ---- Internal: run a list of date checks --------------------------

fn run_date_checks(
  path :: Str,
  ts_key :: Int,
  checks :: List[DateCheck]
) -> List[e.Error] {
  list.fold(checks, [], fn (acc :: List[e.Error], chk :: DateCheck) -> List[e.Error] {
    match eval_date(chk, ts_key) {
      None      => acc,
      Some(msg) => list.concat(acc, e.single(path, date_code(chk), msg)),
    }
  })
}
