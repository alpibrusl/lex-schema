# lex-pydantic — applicative combinators
#
# These functions lift N field validators into a single record
# builder, accumulating *every* failure across the N branches rather
# than short-circuiting at the first.
#
# The intent is to read like a pydantic model declaration:
#
#   fn build(name :: Str, age :: Int) -> User { { name: name, age: age } }
#
#   fn parse(raw :: { name :: Str, age :: Int }) -> Result[User, Errors] {
#     combine2(
#       check_str("name", raw.name, [StrNonEmpty]),
#       check_int("age",  raw.age,  [IntInRange(0, 150)]),
#       build
#     )
#   }
#
# We provide `combine2..combine6`. For more fields, chain combines
# or use a nested record.
#
# Effects: none.

import "./error" as e
import "std.list" as list

# Two-field builder.
fn combine2[A, B, T](
  a :: Result[A, e.Errors],
  b :: Result[B, e.Errors],
  build :: (A, B) -> T
) -> Result[T, e.Errors] {
  match (a, b) {
    (Ok(av), Ok(bv)) => Ok(build(av, bv)),
    (ar, br) => Err(e.concat(errs_of(ar), errs_of(br))),
  }
}

fn combine3[A, B, C, T](
  a :: Result[A, e.Errors],
  b :: Result[B, e.Errors],
  c :: Result[C, e.Errors],
  build :: (A, B, C) -> T
) -> Result[T, e.Errors] {
  match (a, b, c) {
    (Ok(av), Ok(bv), Ok(cv)) => Ok(build(av, bv, cv)),
    (ar, br, cr) => Err(e.flatten([errs_of(ar), errs_of(br), errs_of(cr)])),
  }
}

fn combine4[A, B, C, D, T](
  a :: Result[A, e.Errors],
  b :: Result[B, e.Errors],
  c :: Result[C, e.Errors],
  d :: Result[D, e.Errors],
  build :: (A, B, C, D) -> T
) -> Result[T, e.Errors] {
  match (a, b, c, d) {
    (Ok(av), Ok(bv), Ok(cv), Ok(dv)) => Ok(build(av, bv, cv, dv)),
    (ar, br, cr, dr) => Err(e.flatten([
      errs_of(ar), errs_of(br), errs_of(cr), errs_of(dr),
    ])),
  }
}

fn combine5[A, B, C, D, E, T](
  a :: Result[A, e.Errors],
  b :: Result[B, e.Errors],
  c :: Result[C, e.Errors],
  d :: Result[D, e.Errors],
  ee :: Result[E, e.Errors],
  build :: (A, B, C, D, E) -> T
) -> Result[T, e.Errors] {
  match (a, b, c, d, ee) {
    (Ok(av), Ok(bv), Ok(cv), Ok(dv), Ok(ev)) => Ok(build(av, bv, cv, dv, ev)),
    (ar, br, cr, dr, er) => Err(e.flatten([
      errs_of(ar), errs_of(br), errs_of(cr), errs_of(dr), errs_of(er),
    ])),
  }
}

fn combine6[A, B, C, D, E, F, T](
  a :: Result[A, e.Errors],
  b :: Result[B, e.Errors],
  c :: Result[C, e.Errors],
  d :: Result[D, e.Errors],
  ee :: Result[E, e.Errors],
  f :: Result[F, e.Errors],
  build :: (A, B, C, D, E, F) -> T
) -> Result[T, e.Errors] {
  match (a, b, c, d, ee, f) {
    (Ok(av), Ok(bv), Ok(cv), Ok(dv), Ok(ev), Ok(fv)) =>
      Ok(build(av, bv, cv, dv, ev, fv)),
    (ar, br, cr, dr, er, fr) => Err(e.flatten([
      errs_of(ar), errs_of(br), errs_of(cr), errs_of(dr), errs_of(er), errs_of(fr),
    ])),
  }
}

# Extract the Errors from a Result, or empty list on Ok. The combine
# functions use this to merge sibling-field failures.
fn errs_of[T](r :: Result[T, e.Errors]) -> e.Errors {
  match r {
    Ok(_)   => [],
    Err(es) => es,
  }
}

# Two-step pipeline: run a first validator, then a follow-up that
# depends on the first's output. Standard monadic bind, kept around
# for cases where one field's validity depends on another.
#
# Errors do *not* accumulate across the bind boundary (the second
# validator can't even run unless the first succeeded). For sibling
# fields where you want full accumulation, use `combineN`.
fn and_then[A, B](
  r :: Result[A, e.Errors],
  k :: (A) -> Result[B, e.Errors]
) -> Result[B, e.Errors] {
  match r {
    Ok(a)   => k(a),
    Err(es) => Err(es),
  }
}

# Recover from validation failure with an alternative. The handler
# receives the accumulated errors and decides what to do — often used
# to fall back to a default value (returning `Ok(default)`) or to
# transform the errors before re-raising (`Err(transform(errs))`).
fn or_else[T](
  r :: Result[T, e.Errors],
  handler :: (e.Errors) -> Result[T, e.Errors]
) -> Result[T, e.Errors] {
  match r {
    Ok(v)   => Ok(v),
    Err(es) => handler(es),
  }
}

# Lift a plain value into the Result world.
fn pure[T](v :: T) -> Result[T, e.Errors] { Ok(v) }

# Force an Errors into the Result world.
fn fail[T](es :: e.Errors) -> Result[T, e.Errors] { Err(es) }

# Walk a List of items, applying `f` to each. Errors accumulate
# across the entire list before short-circuiting. The output preserves
# the original ordering.
#
# This is the natural lift for "validate every element of a homogeneous
# list" — e.g., when the field is `List[Email]`.
fn traverse[A, B](
  xs :: List[A],
  f :: (A) -> Result[B, e.Errors]
) -> Result[List[B], e.Errors] {
  list.fold(xs, traverse_init(),
    fn (acc :: Result[List[B], e.Errors], x :: A) -> Result[List[B], e.Errors] {
      match (acc, f(x)) {
        (Ok(out), Ok(b))    => Ok(list.concat(out, [b])),
        (Ok(_),   Err(es))  => Err(es),
        (Err(es), Ok(_))    => Err(es),
        (Err(es), Err(es2)) => Err(list.concat(es, es2)),
      }
    })
}

# Polymorphic empty accumulator for `traverse`. Wrapped in its own
# function so the caller's `Result[List[B], _]` shape pins down the
# `B` parameter through ordinary return-type inference instead of an
# inline type ascription (which Lex doesn't support).
fn traverse_init[B]() -> Result[List[B], e.Errors] { Ok([]) }

# Apply a path-prefix to all errors a sub-validator emits. Useful
# when a nested record builder reports leaf errors with just the
# inner field name; the parent prepends its own field name as the
# segment.
#
# Example: an inner address validator returns `Err([{path:"zip", ...}])`;
# wrapping with `with_path("address", ...)` rewrites to `address.zip`.
fn with_path[T](prefix :: Str, r :: Result[T, e.Errors]) -> Result[T, e.Errors] {
  match r {
    Ok(v)   => Ok(v),
    Err(es) => Err(e.prefix_path(prefix, es)),
  }
}

# Run one or more cross-field checks against a fully-built record.
# Each check is `(T) -> Option[List[Error]]` — `None` means pass,
# `Some(errs)` means fail with those errors. Use `and_then` to
# sequence after a successful `combineN`:
#
#   cm.and_then(combine4(..., build_user),
#     fn (u :: User) -> Result[User, List[Error]] {
#       cm.cross_check(u, [
#         fn (u2 :: User) -> Option[List[Error]] {
#           if u2.password == u2.confirm_password { None }
#           else { Some(e.single("confirm_password", "mismatch",
#                                "passwords must match")) }
#         },
#       ])
#     })
#
# Errors from every check accumulate, never short-circuit. The
# pydantic analog is `@model_validator(mode="after")`.
fn cross_check[T](
  value :: T,
  checks :: List[(T) -> Option[e.Errors]]
) -> Result[T, e.Errors] {
  let errs := list.fold(checks, [],
    fn (
      acc :: e.Errors,
      check :: (T) -> Option[e.Errors]
    ) -> e.Errors {
      match check(value) {
        None     => acc,
        Some(es) => list.concat(acc, es),
      }
    })
  if e.is_ok(errs) { Ok(value) } else { Err(errs) }
}

# Same as `cross_check` but takes a single predicate + a fixed
# code/message pair — convenient for one-off "X and Y must agree"
# checks where building a full `Option[Errors]` shape is overkill.
fn require[T](
  value :: T,
  predicate :: (T) -> Bool,
  path :: Str,
  code :: Str,
  message :: Str
) -> Result[T, e.Errors] {
  if predicate(value) { Ok(value) }
  else { Err(e.single(path, code, message)) }
}
