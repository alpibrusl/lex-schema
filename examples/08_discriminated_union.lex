# lex-schema — discriminated-union (tagged-union) parsing
#
# Real-world webhook payloads frequently arrive as a heterogeneous
# stream, distinguished by a tag field:
#
#   {"event":"signup","user_id":"u_1","email":"a@b.com"}
#   {"event":"purchase","user_id":"u_1","cents":499,"sku":"ABC-1234"}
#   {"event":"cancel","user_id":"u_1","reason":"too_expensive"}
#
# Each event maps to a variant of a `WebhookEvent` ADT. `u.discriminate`
# reads the tag, dispatches to the matching validator, and returns
# the typed variant.
#
# Run:
#   lex run examples/08_discriminated_union.lex demo_signup
#   lex run examples/08_discriminated_union.lex demo_purchase
#   lex run examples/08_discriminated_union.lex demo_unknown_tag
#   lex run examples/08_discriminated_union.lex demo_bad_field

import "../src/error" as e

import "../src/constraints" as c

import "../src/combine" as cm

import "../src/json_value" as jv

import "../src/union" as u

# ---- Target ADT ---------------------------------------------------
type WebhookEvent = Signup({ user_id :: Str, email :: Str }) | Purchase({ user_id :: Str, cents :: Int, sku :: Str }) | Cancel({ user_id :: Str, reason :: Str })

fn validate_signup(j :: jv.Json) -> Result[WebhookEvent, e.Errors] {
  cm.combine2(jv.j_str("", j, "user_id", [StrPattern("^u_[a-zA-Z0-9]+$")]), jv.j_str("", j, "email", [StrEmail]), fn (uid :: Str, em :: Str) -> WebhookEvent {
    Signup({ user_id: uid, email: em })
  })
}

fn validate_purchase(j :: jv.Json) -> Result[WebhookEvent, e.Errors] {
  cm.combine3(jv.j_str("", j, "user_id", [StrPattern("^u_[a-zA-Z0-9]+$")]), jv.j_int("", j, "cents", [IntPositive]), jv.j_str("", j, "sku", [StrPattern("^[A-Z]{3}-[0-9]{4}$")]), fn (uid :: Str, c :: Int, s :: Str) -> WebhookEvent {
    Purchase({ user_id: uid, cents: c, sku: s })
  })
}

fn validate_cancel(j :: jv.Json) -> Result[WebhookEvent, e.Errors] {
  cm.combine2(jv.j_str("", j, "user_id", [StrPattern("^u_[a-zA-Z0-9]+$")]), jv.j_str("", j, "reason", [StrMinLen(1), StrMaxLen(120)]), fn (uid :: Str, r :: Str) -> WebhookEvent {
    Cancel({ user_id: uid, reason: r })
  })
}

# ---- Dispatcher ---------------------------------------------------
fn validate_event(j :: jv.Json) -> Result[WebhookEvent, e.Errors] {
  u.discriminate("", j, "event", [("signup", validate_signup), ("purchase", validate_purchase), ("cancel", validate_cancel)])
}

fn parse_event(body :: Str) -> Result[WebhookEvent, e.Errors] {
  cm.and_then(jv.parse_into_errors(body), fn (j :: jv.Json) -> Result[WebhookEvent, e.Errors] {
    validate_event(j)
  })
}

# ---- Demos --------------------------------------------------------
fn demo_signup() -> Result[WebhookEvent, e.Errors] {
  parse_event("{\"event\":\"signup\",\"user_id\":\"u_alice\",\"email\":\"alice@example.com\"}")
}

fn demo_purchase() -> Result[WebhookEvent, e.Errors] {
  parse_event("{\"event\":\"purchase\",\"user_id\":\"u_alice\",\"cents\":2500,\"sku\":\"ABC-1234\"}")
}

fn demo_unknown_tag() -> Result[WebhookEvent, e.Errors] {
  parse_event("{\"event\":\"refund\",\"user_id\":\"u_alice\"}")
}

fn demo_bad_field() -> Result[WebhookEvent, e.Errors] {
  parse_event("{\"event\":\"purchase\",\"user_id\":\"u_alice\",\"cents\":-1,\"sku\":\"nope\"}")
}

fn format_unknown_tag() -> Str {
  match demo_unknown_tag() {
    Ok(_) => "no errors",
    Err(es) => e.format(es),
  }
}

fn format_bad_field() -> Str {
  match demo_bad_field() {
    Ok(_) => "no errors",
    Err(es) => e.format(es),
  }
}

