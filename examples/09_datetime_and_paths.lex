# lex-pydantic — datetime constraints + dotted-path extraction
#
# A scheduled-event payload exercising both new pieces:
#
#   - `datetime.check_iso_datetime` validates ISO 8601 syntax and
#     enforces bounds (the event must be at or before
#     "2027-01-01T00:00:00Z").
#   - `jv.j_str_at` reads nested fields via dotted paths
#     (`organizer.email`, `location.address.city`), keeping the
#     error trail accurate without intermediate `with_path` calls.
#
# Run:
#   lex run examples/09_datetime_and_paths.lex demo_good
#   lex run examples/09_datetime_and_paths.lex demo_bad

import "../src/error"       as e
import "../src/constraints" as c
import "../src/combine"     as cm
import "../src/json_value"  as jv
import "../src/datetime"    as dt

# ---- Target type --------------------------------------------------
# `scheduled_for` is stored as a canonical ISO 8601 Str — the same
# representation `dt.check_iso_datetime` produces — so downstream
# code has a uniform comparable form.

type ScheduledEvent = {
  title :: Str,
  scheduled_for :: Str,
  organizer_email :: Str,
  city :: Str,
}

fn mk_event(
  t :: Str,
  s :: Str,
  em :: Str,
  ci :: Str
) -> ScheduledEvent {
  { title: t, scheduled_for: s, organizer_email: em, city: ci }
}

# ---- Validator ----------------------------------------------------

fn upper_bound() -> Str { "2027-01-01T00:00:00Z" }

fn validate(j :: jv.Json) -> Result[ScheduledEvent, e.Errors] {
  cm.combine4(
    jv.j_str("", j, "title", [StrMinLen(1), StrMaxLen(120)]),
    dt_field(j, "scheduled_for", [DateAtOrBefore(upper_bound())]),
    jv.j_str_at(j, "organizer.email",       [StrEmail]),
    jv.j_str_at(j, "location.address.city", [StrMinLen(1)]),
    mk_event
  )
}

# Small adapter: pull a Str field from `j` and run it through
# `dt.check_iso_datetime`. Keeps the call site reading like the
# other combinators.
fn dt_field(
  j :: jv.Json,
  field :: Str,
  checks :: List[dt.DateCheck]
) -> Result[Str, e.Errors] {
  match jv.j_str("", j, field, []) {
    Err(es) => Err(es),
    Ok(s)   => dt.check_iso_datetime(field, s, checks),
  }
}

fn parse_event(body :: Str) -> Result[ScheduledEvent, e.Errors] {
  cm.and_then(jv.parse_into_errors(body),
    fn (j :: jv.Json) -> Result[ScheduledEvent, e.Errors] { validate(j) })
}

# ---- Demos --------------------------------------------------------

fn demo_good() -> Result[ScheduledEvent, e.Errors] {
  parse_event(
    "{\"title\":\"Team offsite\",\"scheduled_for\":\"2026-08-12T09:30:00Z\",\"organizer\":{\"email\":\"alice@example.com\"},\"location\":{\"address\":{\"city\":\"Berlin\"}}}"
  )
}

fn demo_bad() -> Result[ScheduledEvent, e.Errors] {
  # title empty, date in 2030 (past the upper bound),
  # organizer.email is not a string, location.address.city missing.
  parse_event(
    "{\"title\":\"\",\"scheduled_for\":\"2030-06-01T10:00:00Z\",\"organizer\":{\"email\":42},\"location\":{\"address\":{}}}"
  )
}

fn format_bad() -> Str {
  match demo_bad() {
    Ok(_)   => "no errors",
    Err(es) => e.format(es),
  }
}
