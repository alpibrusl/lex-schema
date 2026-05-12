# lex-schema — payments API tour
#
# Combines the four v0.7-feature additions in one realistic
# shape:
#
#   1. Format validators — credit-card Luhn, phone E.164, IP
#      address (for fraud rules).
#   2. RFC 7807 problem+json — what the HTTP handler returns on
#      validation failure.
#   3. SDK codegen — emit TypeScript, Pydantic, Zod, and Rust
#      stubs for downstream clients off one schema.
#   4. Schema migrations + compat check — the v2 payload renamed
#      `cc` to `card_number` and added a required `cvv`. The
#      backward-compat check flags it; the migration script
#      rewrites v1 payloads to the v2 shape.
#
# Run:
#   lex run examples/20_payments_api.lex demo_validate_v2
#   lex run examples/20_payments_api.lex demo_problem_json
#   lex run examples/20_payments_api.lex demo_typescript
#   lex run examples/20_payments_api.lex demo_zod
#   lex run examples/20_payments_api.lex demo_rust
#   lex run examples/20_payments_api.lex demo_migrate_v1_to_v2
#   lex run examples/20_payments_api.lex demo_compat_check

import "../src/error"       as e
import "../src/constraints" as c
import "../src/combine"     as cm
import "../src/json_value"  as jv
import "../src/schema"      as s
import "../src/sdk"         as sdk
import "../src/problem"     as pr
import "../src/migrate"     as m

# ---- Schemas ------------------------------------------------------

# v1 — original payment payload. `cc` was a free-form string.
fn payment_v1() -> s.ModelSchema {
  {
    title: "Payment",
    description: "A card payment (v1)",
    fields: [
      s.required_str("cc",     [StrCreditCardLuhn]),
      s.required_int("amount", [IntPositive, IntMax(1000000)]),
      s.required_str("payer_ip", [StrIPv4]),
    ],
  }
}

# v2 — `cc` renamed to `card_number`, `cvv` required, `phone`
# optional. Same network this version writes to.
fn payment_v2() -> s.ModelSchema {
  {
    title: "Payment",
    description: "A card payment (v2)",
    fields: [
      s.required_str("card_number", [StrCreditCardLuhn]),
      s.required_str("cvv",         [StrPattern("^[0-9]{3,4}$")]),
      s.required_int("amount",      [IntPositive, IntMax(1000000)]),
      s.required_str("payer_ip",    [StrIPv4]),
      s.optional(s.required_str("phone", [StrPhoneE164])),
    ],
  }
}

# ---- Validation pipeline ------------------------------------------

fn parse_and_validate(body :: Str) -> Result[jv.Json, e.Errors] {
  cm.and_then(jv.parse_into_errors(body),
    fn (j :: jv.Json) -> Result[jv.Json, e.Errors] {
      s.validate(payment_v2(), j)
    })
}

# ---- Demos: validation --------------------------------------------

fn demo_validate_v2() -> Result[jv.Json, e.Errors] {
  parse_and_validate(
    "{\"card_number\":\"4111111111111111\",\"cvv\":\"123\",\"amount\":2500,\"payer_ip\":\"192.168.1.1\"}"
  )
}

fn demo_validate_bad() -> Result[jv.Json, e.Errors] {
  parse_and_validate(
    "{\"card_number\":\"4111111111111112\",\"cvv\":\"12\",\"amount\":-1,\"payer_ip\":\"256.0.0.1\"}"
  )
}

# ---- Demos: RFC 7807 ----------------------------------------------

# Render a bad-payload response as RFC 7807. Useful for HTTP
# handlers that want the standard error envelope.
fn demo_problem_json() -> Str {
  match demo_validate_bad() {
    Ok(_)   => "(no errors)",
    Err(es) => {
      let p := pr.validation_problem(
        "https://example.com/problems/payment-validation",
        "/v1/payments",
        es
      )
      pr.to_pretty(p)
    },
  }
}

# ---- Demos: SDK codegen -------------------------------------------

fn demo_typescript() -> Str { sdk.to_typescript(payment_v2()) }
fn demo_zod()        -> Str { sdk.to_zod(payment_v2()) }
fn demo_rust()       -> Str { sdk.to_rust_struct(payment_v2()) }
fn demo_python()     -> Str { sdk.to_python(payment_v2()) }

# ---- Demos: migration v1 → v2 -------------------------------------

# The migration script every v1 payload needs to go through to
# match the v2 shape.
fn v1_to_v2_migration() -> List[m.Transform] {
  [
    Rename({ from: "cc", to: "card_number" }),
    AddField({ name: "cvv", default: JStr("000") }),
  ]
}

fn demo_migrate_v1_to_v2() -> jv.Json {
  match jv.parse("{\"cc\":\"4111111111111111\",\"amount\":2500,\"payer_ip\":\"10.0.0.1\"}") {
    Err(_) => JNull,
    Ok(j)  => m.apply(j, v1_to_v2_migration()),
  }
}

# ---- Demos: compat check ------------------------------------------

# This is the gate a CI step would run before shipping the v2
# schema: does v2 break v1 producers?
fn demo_compat_check() -> Str {
  match m.is_backward_compatible(payment_v1(), payment_v2()) {
    Ok(_)   => "compatible (v2 accepts v1 payloads)",
    Err(is) => m.format_incompats(is),
  }
}
