# lex-schema — webhook deduplication
#
# Webhook delivery from Stripe / GitHub / Slack / etc. is
# at-least-once: the same event can arrive twice if the first
# response timed out, dropped, or got partitioned. The naïve fix
# (process whatever lands) double-charges customers, posts
# duplicate messages, and writes audit rows twice. The standard
# fix is **idempotency by content hash**: compute a key from the
# event body, look it up against a seen-set, skip if matched.
#
# This example shows the full pipeline:
#
#   1. Parse the event JSON via the safe-mode `json_value` parser.
#   2. Discriminate on the `event` tag via `u.discriminate`.
#   3. Compute SHA-256 over the parser-output bytes. Order is
#      preserved as it arrived — which matches the webhook-delivery
#      contract: Stripe / GitHub / Slack retry with byte-identical
#      bodies, not semantically-identical bodies. For
#      cross-key-order equality, sort the `JObj` entries before
#      stringifying (blocked on a `list.sort_by` upstream — see
#      lex-lang issue tracker; the workaround is a hand-rolled
#      insertion sort in user code).
#   4. Look up against the seen-set. If hit, return `Skipped`.
#      Otherwise process and return `Processed(response)` plus the
#      updated seen-set for the caller to thread forward.
#
# The seen-set is a pure `Set[Str]` threaded through the call. A
# production deployment would back it with `std.kv` or `std.sql`
# for cross-process durability; the in-memory form is fine for
# single-process workers + tests.
#
# Run:
#   lex run examples/17_webhook_dedup.lex demo_no_dupes
#   lex run examples/17_webhook_dedup.lex demo_dupe_pair

import "std.str" as str

import "std.list" as list

import "std.set" as set

import "std.bytes" as bytes

import "std.crypto" as crypto

import "../src/error" as e

import "../src/constraints" as c

import "../src/combine" as cm

import "../src/json_value" as jv

import "../src/union" as u

# ---- Event ADT + validators (mirrors example 08) ------------------
type WebhookEvent = Charge({ id :: Str, cents :: Int }) | Refund({ id :: Str, cents :: Int })

fn validate_charge(j :: jv.Json) -> Result[WebhookEvent, e.Errors] {
  cm.combine2(jv.j_str("", j, "id", [StrMinLen(1)]), jv.j_int("", j, "cents", [IntPositive]), fn (i :: Str, c :: Int) -> WebhookEvent {
    Charge({ id: i, cents: c })
  })
}

fn validate_refund(j :: jv.Json) -> Result[WebhookEvent, e.Errors] {
  cm.combine2(jv.j_str("", j, "id", [StrMinLen(1)]), jv.j_int("", j, "cents", [IntPositive]), fn (i :: Str, c :: Int) -> WebhookEvent {
    Refund({ id: i, cents: c })
  })
}

fn validate_event(j :: jv.Json) -> Result[WebhookEvent, e.Errors] {
  u.discriminate("", j, "event", [("charge", validate_charge), ("refund", validate_refund)])
}

# ---- Idempotency-key extraction -----------------------------------
#
# SHA-256 of the canonical-form re-serialization. We hash the *parsed*
# Json's `stringify` output rather than the raw input bytes, so two
# requests with the same fields in a different order land on the same
# key — which is the correctness property we actually want.
fn idempotency_key(j :: jv.Json) -> Str {
  let canonical := jv.stringify(j)
  let digest := crypto.sha256(bytes.from_str(canonical))
  crypto.hex_encode(digest)
}

# ---- Dispatcher ---------------------------------------------------
# The pure dispatch result: either we processed the event for the
# first time (and the caller should record its response), or we
# skipped it because we'd already seen this content. Both arms
# carry the idempotency key so the caller can log / persist.
type Outcome = Processed({ key :: Str, event :: WebhookEvent }) | Skipped({ key :: Str }) | Rejected({ errors :: e.Errors })

fn process_one(body :: Str, seen :: Set[Str]) -> (Outcome, Set[Str]) {
  match jv.parse_into_errors(body) {
    Err(es) => (Rejected({ errors: es }), seen),
    Ok(j) => {
      let key := idempotency_key(j)
      if set.has(seen, key) {
        (Skipped({ key: key }), seen)
      } else {
        match validate_event(j) {
          Err(es) => (Rejected({ errors: es }), seen),
          Ok(ev) => (Processed({ key: key, event: ev }), set.add(seen, key)),
        }
      }
    },
  }
}

# Batch helper: process a list of bodies threading the seen-set.
fn process_many(bodies :: List[Str]) -> (List[Outcome], Set[Str]) {
  list.fold(bodies, init_state(), fn (acc :: (List[Outcome], Set[Str]), body :: Str) -> (List[Outcome], Set[Str]) {
    let outs := match acc {
      (o, _) => o,
    }
    let seen := match acc {
      (_, s) => s,
    }
    let step := process_one(body, seen)
    let next_out := match step {
      (o, _) => o,
    }
    let next_seen := match step {
      (_, s) => s,
    }
    (list.concat(outs, [next_out]), next_seen)
  })
}

fn init_state() -> (List[Outcome], Set[Str]) {
  ([], set.new())
}

# ---- Demos --------------------------------------------------------
fn demo_no_dupes() -> List[Outcome] {
  let result := process_many(["{\"event\":\"charge\",\"id\":\"ch_1\",\"cents\":1000}", "{\"event\":\"refund\",\"id\":\"rf_1\",\"cents\":500}", "{\"event\":\"charge\",\"id\":\"ch_2\",\"cents\":2500}"])
  match result {
    (outs, _) => outs,
  }
}

fn demo_dupe_pair() -> List[Outcome] {
  let result := process_many(["{\"event\":\"charge\",\"id\":\"ch_1\",\"cents\":1000}", "{\"event\":\"charge\",\"id\":\"ch_1\",\"cents\":1000}", "{\"event\":\"charge\",\"id\":\"ch_1\",\"cents\":1000}"])
  match result {
    (outs, _) => outs,
  }
}

fn demo_invalid() -> List[Outcome] {
  let result := process_many(["{\"event\":\"charge\",\"id\":\"ch_z\",\"cents\":-1}", "{\"event\":\"unknown\",\"id\":\"x\"}", "not even json"])
  match result {
    (outs, _) => outs,
  }
}

