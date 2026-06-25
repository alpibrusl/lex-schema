# lex-schema — optional fields + defaults
#
# Two distinct patterns sit under the "optional" umbrella in
# pydantic, and lex-schema separates them cleanly:
#
#   1. `Optional[str] = None`  — field stays as `Option[T]` in the
#      model. Use `f.check_optional_str` etc.
#   2. `str = "anonymous"`     — field becomes a `T` in the model,
#      with a default filling in for missing input. Use
#      `f.with_default` to lift, then the regular `f.check_str`.
#
# Run:
#   lex run examples/05_optional_and_defaults.lex demo_present
#   lex run examples/05_optional_and_defaults.lex demo_absent
#   lex run examples/05_optional_and_defaults.lex demo_bad

import "std.map" as map

import "../src/error" as e

import "../src/constraints" as c

import "../src/field" as f

import "../src/combine" as cm

# ---- Target type ---------------------------------------------------
# `nickname` is genuinely optional; the consumer cares whether the
# user set one. `display_color` always has a value — missing input
# defaults to "dark".
type Profile = { username :: Str, nickname :: Option[Str], display_color :: Str }

fn mk_profile(un :: Str, nick :: Option[Str], color :: Str) -> Profile {
  { username: un, nickname: nick, display_color: color }
}

# ---- Source type: dict-like input via Map[Str, Str] ---------------
# We use `map.get` (returns `Option[T]`) so absent keys are first-
# class. This is the natural source shape for query strings,
# form bodies, env vars, etc.
fn validate(src :: Map[Str, Str]) -> Result[Profile, e.Errors] {
  cm.combine3(require_str(src, "username", [StrMinLen(3), StrMaxLen(32), StrPattern("^[a-zA-Z0-9_]+$")]), f.check_optional_str("nickname", map.get(src, "nickname"), [StrMaxLen(40)]), f.check_str("display_color", f.with_default(map.get(src, "display_color"), "dark"), [StrOneOf(["dark", "light", "auto"])]), mk_profile)
}

# Small local helper: `map.get` followed by a presence-or-Err check.
# A v0.2 of the library will likely fold this into `f.require_str_from_map`
# (see `src/coerce.lex`); we inline it here so the example reads
# end-to-end without jumping modules.
fn require_str(src :: Map[Str, Str], key :: Str, checks :: List[c.StrCheck]) -> Result[Str, e.Errors] {
  match map.get(src, key) {
    None => Err(e.single(key, e.code_missing(), "field is required")),
    Some(s) => f.check_str(key, s, checks),
  }
}

# ---- Demo inputs --------------------------------------------------
fn demo_present() -> Result[Profile, e.Errors] {
  let src := map.from_list([("username", "alice_42"), ("nickname", "Ally"), ("display_color", "light")])
  validate(src)
}

fn demo_absent() -> Result[Profile, e.Errors] {
  let src := map.from_list([("username", "bob_99")])
  validate(src)
}

fn demo_bad() -> Result[Profile, e.Errors] {
  let src := map.from_list([("username", "x"), ("nickname", "a-very-long-nickname-that-definitely-exceeds-forty-chars"), ("display_color", "neon")])
  validate(src)
}

fn format_demo() -> Str {
  match demo_bad() {
    Ok(_) => "no errors",
    Err(es) => e.format(es),
  }
}

