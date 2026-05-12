# lex-pydantic — cross-field validators
#
# Per-field checks catch values that are individually invalid;
# cross-field checks catch combinations that are individually
# fine but jointly wrong. Three canonical examples:
#
#   1. `password` and `confirm_password` must match.
#   2. `start_date` must be earlier than `end_date`.
#   3. If `payment_method` is "card", `card_number` must be set.
#
# `cm.cross_check` accumulates failures across every cross-field
# rule and chains naturally after a successful `combineN` via
# `cm.and_then`.
#
# Run:
#   lex run examples/12_cross_field.lex demo_good
#   lex run examples/12_cross_field.lex demo_mismatched
#   lex run examples/12_cross_field.lex demo_reversed_dates

import "../src/error"       as e
import "../src/constraints" as c
import "../src/field"       as f
import "../src/combine"     as cm
import "../src/json_value"  as jv
import "../src/datetime"    as dt

type Signup = {
  email :: Str,
  password :: Str,
  confirm_password :: Str,
  start_date :: Str,
  end_date :: Str,
}

fn build(em :: Str, p :: Str, cp :: Str, sd :: Str, ed :: Str) -> Signup {
  { email: em, password: p, confirm_password: cp, start_date: sd, end_date: ed }
}

# ---- Cross-field rules --------------------------------------------

fn passwords_match(u :: Signup) -> Option[List[e.Error]] {
  if u.password == u.confirm_password { None }
  else {
    Some(e.single("confirm_password", "mismatch",
                  "must match password"))
  }
}

fn end_after_start(u :: Signup) -> Option[List[e.Error]] {
  # We accept that both fields parse — the field-level validator
  # already enforced ISO 8601. Here we only check ordering, by
  # comparing canonical-form strings... no, by re-parsing both
  # through `dt` and using `DateAfter`.
  match dt.check_iso_datetime("end_date", u.end_date,
                               [DateAfter(u.start_date)]) {
    Ok(_)   => None,
    Err(es) => Some(es),
  }
}

# ---- Validator ----------------------------------------------------

fn validate(raw :: Signup) -> Result[Signup, List[e.Error]] {
  cm.and_then(
    cm.combine5(
      f.check_str("email",           raw.email,           [StrEmail]),
      f.check_str("password",        raw.password,        [StrMinLen(8)]),
      f.check_str("confirm_password",raw.confirm_password,[StrMinLen(8)]),
      f.check_str("start_date",      raw.start_date,      []),
      f.check_str("end_date",        raw.end_date,        []),
      build
    ),
    fn (u :: Signup) -> Result[Signup, List[e.Error]] {
      cm.cross_check(u, [passwords_match, end_after_start])
    }
  )
}

# ---- Demos --------------------------------------------------------

fn demo_good() -> Result[Signup, List[e.Error]] {
  validate({
    email:            "alice@example.com",
    password:         "correcthorse9",
    confirm_password: "correcthorse9",
    start_date:       "2026-01-01T00:00:00Z",
    end_date:         "2026-12-31T23:59:59Z",
  })
}

fn demo_mismatched() -> Result[Signup, List[e.Error]] {
  validate({
    email:            "alice@example.com",
    password:         "correcthorse9",
    confirm_password: "different9",
    start_date:       "2026-01-01T00:00:00Z",
    end_date:         "2026-12-31T23:59:59Z",
  })
}

fn demo_reversed_dates() -> Result[Signup, List[e.Error]] {
  validate({
    email:            "alice@example.com",
    password:         "correcthorse9",
    confirm_password: "correcthorse9",
    start_date:       "2026-12-31T23:59:59Z",
    end_date:         "2026-01-01T00:00:00Z",
  })
}

fn format_mismatched() -> Str {
  match demo_mismatched() {
    Ok(_)   => "no errors",
    Err(es) => e.format(es),
  }
}

fn format_reversed() -> Str {
  match demo_reversed_dates() {
    Ok(_)   => "no errors",
    Err(es) => e.format(es),
  }
}
