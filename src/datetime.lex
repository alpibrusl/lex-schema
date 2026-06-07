# lex-schema — datetime constraints
#
# Dates arrive in payloads as ISO 8601 strings
# (`"2026-05-12T14:30:00Z"`). We parse them via `std.datetime`,
# carry the bounds as ISO 8601 strings, and use the
# `datetime.before` / `datetime.after` / `datetime.compare`
# comparison surface to evaluate `DateCheck` constraints.
#
# Effects: pure for parse-and-bound; `[time]` for the `now`-
# relative checks (`check_iso_in_past`, etc.).

import "std.str" as str

import "std.list" as list

import "std.datetime" as datetime

import "./error" as e

# ---- DateCheck variants -------------------------------------------
#
# Bounds are ISO 8601 strings — `"2026-01-01T00:00:00Z"` style.
# Any form `datetime.parse_iso` accepts is fine; comparisons go
# through the typed Instant surface so non-canonical offsets and
# fractional seconds compare correctly.
type DateCheck = DateBefore(Str) | DateAfter(Str) | DateAtOrBefore(Str) | DateAtOrAfter(Str) | DateInRange((Str, Str))

fn bound_instant(s :: Str) -> Option[Instant] {
  match datetime.parse_iso(s) {
    Ok(ins) => Some(ins),
    Err(_) => None,
  }
}

fn eval_date(c :: DateCheck, ts :: Instant) -> Option[Str] {
  match c {
    DateBefore(hi) => match bound_instant(hi) {
      None => Some(str.concat("invalid bound: ", hi)),
      Some(h_in) => if datetime.before(ts, h_in) {
        None
      } else {
        Some(str.concat("must be before ", hi))
      },
    },
    DateAtOrBefore(hi) => match bound_instant(hi) {
      None => Some(str.concat("invalid bound: ", hi)),
      Some(h_in) => if datetime.compare(ts, h_in) <= 0 {
        None
      } else {
        Some(str.concat("must be at or before ", hi))
      },
    },
    DateAfter(lo) => match bound_instant(lo) {
      None => Some(str.concat("invalid bound: ", lo)),
      Some(l_in) => if datetime.after(ts, l_in) {
        None
      } else {
        Some(str.concat("must be after ", lo))
      },
    },
    DateAtOrAfter(lo) => match bound_instant(lo) {
      None => Some(str.concat("invalid bound: ", lo)),
      Some(l_in) => if datetime.compare(ts, l_in) >= 0 {
        None
      } else {
        Some(str.concat("must be at or after ", lo))
      },
    },
    DateInRange(lo, hi) => match bound_instant(lo) {
      None => Some(str.concat("invalid bound: ", lo)),
      Some(l_in) => match bound_instant(hi) {
        None => Some(str.concat("invalid bound: ", hi)),
        Some(h_in) => if datetime.compare(ts, l_in) < 0 {
          Some(str.concat("must be at or after ", lo))
        } else {
          if datetime.compare(ts, h_in) > 0 {
            Some(str.concat("must be at or before ", hi))
          } else {
            None
          }
        },
      },
    },
  }
}

fn date_code(c :: DateCheck) -> Str {
  match c {
    DateBefore(_) => e.code_max(),
    DateAtOrBefore(_) => e.code_max(),
    DateAfter(_) => e.code_min(),
    DateAtOrAfter(_) => e.code_min(),
    DateInRange(_, _) => e.code_min(),
  }
}

# ---- Field validator entry points ---------------------------------
# Parse `s` as ISO 8601, then run the bound checks. Returns the
# canonical-form string so downstream code stores a uniformly
# ordered representation.
fn check_iso_datetime(path :: Str, s :: Str, checks :: List[DateCheck]) -> Result[Str, e.Errors] {
  match datetime.parse_iso(s) {
    Err(m) => Err(e.single(path, e.code_type(), str.concat("not a valid ISO 8601 datetime: ", m))),
    Ok(ins) => {
      let canonical := datetime.format_iso(ins)
      let errs := run_date_checks(path, ins, checks)
      if e.is_ok(errs) {
        Ok(canonical)
      } else {
        Err(errs)
      }
    },
  }
}

# `strftime`-style fallback for when the input isn't strict ISO 8601
# but still has a known format. The parsed Instant is re-formatted
# into canonical ISO 8601 for storage and comparison.
fn check_datetime(path :: Str, s :: Str, format :: Str, checks :: List[DateCheck]) -> Result[Str, e.Errors] {
  match datetime.parse(s, format) {
    Err(m) => Err(e.single(path, e.code_type(), str.concat("date didn't match format `", str.concat(format, str.concat("`: ", m))))),
    Ok(ins) => {
      let canonical := datetime.format_iso(ins)
      let errs := run_date_checks(path, ins, checks)
      if e.is_ok(errs) {
        Ok(canonical)
      } else {
        Err(errs)
      }
    },
  }
}

# Parse-only: returns the canonical ISO 8601 form of `s` without
# any bound check. Useful as the leaf step of a `check_str`
# pipeline where you only care that the field is well-formed.
fn parse_iso(path :: Str, s :: Str) -> Result[Str, e.Errors] {
  check_iso_datetime(path, s, [])
}

# ---- Now-relative presets -----------------------------------------
#
# Built on `datetime.now()` so the bound moves with wall-clock
# time. The functions carry `[time]`; the call site inherits it.
# That's intentional — readers see the time dependency at the
# type level.
# Must be in the past or now.
fn check_iso_in_past(path :: Str, s :: Str) -> [time] Result[Str, e.Errors] {
  let now_iso := datetime.format_iso(datetime.now())
  check_iso_datetime(path, s, [DateAtOrBefore(now_iso)])
}

# Must be in the future or now.
fn check_iso_in_future(path :: Str, s :: Str) -> [time] Result[Str, e.Errors] {
  let now_iso := datetime.format_iso(datetime.now())
  check_iso_datetime(path, s, [DateAtOrAfter(now_iso)])
}

# ---- Internal: run a list of date checks --------------------------
fn run_date_checks(path :: Str, ts :: Instant, checks :: List[DateCheck]) -> e.Errors {
  list.fold(checks, [], fn (acc :: e.Errors, chk :: DateCheck) -> e.Errors {
    match eval_date(chk, ts) {
      None => acc,
      Some(msg) => list.concat(acc, e.single(path, date_code(chk), msg)),
    }
  })
}

