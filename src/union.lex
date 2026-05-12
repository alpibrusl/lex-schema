# lex-schema — tagged-union (discriminated-union) validation
#
# JSON payloads like
#
#   {"kind":"user",  "name":"alice"}
#   {"kind":"admin", "name":"bob", "permissions":["read","write"]}
#
# map naturally onto a Lex variant type. Pydantic's
# `Discriminator(...)` covers the same pattern; here we make the
# dispatch a small, regular value.
#
# Usage:
#
#   type Account = User({ name :: Str })
#                | Admin({ name :: Str, permissions :: List[Str] })
#
#   fn validate_user(j :: Json)  -> Result[Account, List[Error]] { ... }
#   fn validate_admin(j :: Json) -> Result[Account, List[Error]] { ... }
#
#   fn parse(j :: Json) -> Result[Account, List[Error]] {
#     u.discriminate("", j, "kind", [
#       ("user",  validate_user),
#       ("admin", validate_admin),
#     ])
#   }
#
# Effects: none.

import "std.str"  as str
import "std.list" as list

import "./error"      as e
import "./json_value" as jv

# A single (tag, validator) branch — a closure-in-tuple value.
# Lex's closure-as-record-field support landed late (see lex-lang
# design doc on `closures-in-records.md`); we use tuples here
# because tuple-stored closures have always been first-class.

# `discriminate` reads the tag at `field` from `j`, finds the
# matching branch, and runs its validator. Three failure modes,
# each with its own error code:
#
#   - missing tag       -> code = "missing"
#   - tag isn't a Str   -> code = "type"
#   - tag isn't in set  -> code = "one_of"   (message lists known tags)
fn discriminate[T](
  path_prefix :: Str,
  j :: jv.Json,
  field :: Str,
  branches :: List[(Str, (jv.Json) -> Result[T, e.Errors])]
) -> Result[T, e.Errors] {
  match jv.j_str(path_prefix, j, field, []) {
    Err(es) => Err(es),
    Ok(tag) => match find_branch(branches, tag) {
      Some(handler) => handler(j),
      None => Err(e.single(
        joined_path(path_prefix, field),
        e.code_one_of(),
        str.concat("unknown discriminator `",
          str.concat(tag,
            str.concat("`, expected one of ",
              str.join(branch_tags(branches), ", ")))))),
    },
  }
}

# Lookup helpers — pure list folds.

fn find_branch[T](
  branches :: List[(Str, (jv.Json) -> Result[T, e.Errors])],
  tag :: Str
) -> Option[(jv.Json) -> Result[T, e.Errors]] {
  list.fold(branches, find_init(),
    fn (
      acc :: Option[(jv.Json) -> Result[T, e.Errors]],
      pair :: (Str, (jv.Json) -> Result[T, e.Errors])
    ) -> Option[(jv.Json) -> Result[T, e.Errors]] {
      match acc {
        Some(_) => acc,
        None    => match pair {
          (k, v) => if k == tag { Some(v) } else { None },
        },
      }
    })
}

# Polymorphic empty init (see lex-lang#319 for why we need the
# helper rather than an inline `None`).
fn find_init[T]() -> Option[(jv.Json) -> Result[T, e.Errors]] {
  None
}

fn branch_tags[T](
  branches :: List[(Str, (jv.Json) -> Result[T, e.Errors])]
) -> List[Str] {
  list.map(branches, fn (
    pair :: (Str, (jv.Json) -> Result[T, e.Errors])
  ) -> Str {
    match pair { (k, _v) => k }
  })
}

fn joined_path(prefix :: Str, leaf :: Str) -> Str {
  if str.is_empty(prefix) { leaf }
  else { str.concat(prefix, str.concat(".", leaf)) }
}
