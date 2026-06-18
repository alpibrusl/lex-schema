# lex-schema — property-based test harness
#
# Generate random valid inputs from a `ModelSchema`, then assert
# a property over them. The canonical use is the **round-trip
# property**: every value the generator produces must be `Ok`
# when fed back through `schema.validate`. A failure either
# means the generator emits values the validator rejects (a
# generator bug) or — more interestingly — that the schema is
# internally inconsistent (a constraint says "min 10" while
# another path says "max 5").
#
# Generation is pure and deterministic — every run takes a seed,
# threads the `std.random` RNG through, and produces the same
# sequence on every platform. That's a hard property for a
# regression suite to lean on.
#
# Effects: none. `std.random` is a pure threaded RNG (no `[rand]`
# effect tag because the seed is visible in the value flow).

import "std.str" as str

import "std.int" as int

import "std.float" as float

import "std.list" as list

import "std.random" as random

import "./error" as e

import "./constraints" as c

import "./json_value" as jv

import "./schema" as s

# ---- Constraint introspection -------------------------------------
# Pull a length range out of a `StrCheck` list. Defaults are 1..32
# if no min/max is specified — small enough to keep tests fast,
# large enough that constraint-respecting strings have room to
# vary. `StrExactLen(n)` pins both ends to n.
fn str_len_bounds(checks :: List[c.StrCheck]) -> (Int, Int) {
  list.fold(checks, (1, 32), fn (acc :: (Int, Int), chk :: c.StrCheck) -> (Int, Int) {
    let lo := match acc {
      (l, _) => l,
    }
    let hi := match acc {
      (_, h) => h,
    }
    match chk {
      StrMinLen(n) => (max_int(lo, n), hi),
      StrMaxLen(n) => (lo, min_int(hi, n)),
      StrExactLen(n) => (n, n),
      StrNonEmpty => (max_int(lo, 1), hi),
      _ => acc,
    }
  })
}

# Pull a numeric range out of an `IntCheck` list. Defaults span
# the full Int64 surface so unbounded fields still produce
# values, but `IntInRange` / `IntMin` / `IntMax` clamp tightly.
fn int_bounds(checks :: List[c.IntCheck]) -> (Int, Int) {
  list.fold(checks, default_int_bounds(), fn (acc :: (Int, Int), chk :: c.IntCheck) -> (Int, Int) {
    let lo := match acc {
      (l, _) => l,
    }
    let hi := match acc {
      (_, h) => h,
    }
    match chk {
      IntMin(n) => (max_int(lo, n), hi),
      IntMax(n) => (lo, min_int(hi, n)),
      IntInRange(a, b) => (max_int(lo, a), min_int(hi, b)),
      IntEq(n) => (n, n),
      IntPositive => (max_int(lo, 1), hi),
      IntNonNegative => (max_int(lo, 0), hi),
      IntOneOf(_) => acc,
    }
  })
}

fn default_int_bounds() -> (Int, Int) {
  (0 - 1000000, 1000000)
}

fn float_bounds(checks :: List[c.FloatCheck]) -> (Float, Float) {
  list.fold(checks, (0.0 - 1000.0, 1000.0), fn (acc :: (Float, Float), chk :: c.FloatCheck) -> (Float, Float) {
    let lo := match acc {
      (l, _) => l,
    }
    let hi := match acc {
      (_, h) => h,
    }
    match chk {
      FloatMin(x) => (max_float(lo, x), hi),
      FloatMax(x) => (lo, min_float(hi, x)),
      FloatInRange(a, b) => (max_float(lo, a), min_float(hi, b)),
      FloatPositive => (max_float(lo, 0.0000001), hi),
      FloatNonNegative => (max_float(lo, 0.0), hi),
      FloatFinite => acc,
    }
  })
}

fn list_len_bounds(checks :: List[c.ListCheck]) -> (Int, Int) {
  list.fold(checks, (0, 5), fn (acc :: (Int, Int), chk :: c.ListCheck) -> (Int, Int) {
    let lo := match acc {
      (l, _) => l,
    }
    let hi := match acc {
      (_, h) => h,
    }
    match chk {
      ListMinLen(n) => (max_int(lo, n), hi),
      ListMaxLen(n) => (lo, min_int(hi, n)),
      ListExactLen(n) => (n, n),
      ListNonEmpty => (max_int(lo, 1), hi),
    }
  })
}

# ---- Generators ---------------------------------------------------
# Generate a `Json` value matching the given schema. The output
# walks the field list in declaration order; required fields are
# always produced, optional fields are emitted with 50% probability.
fn generate(schema :: s.ModelSchema, rng :: Rng) -> (jv.Json, Rng) {
  let result := list.fold(schema.fields, init_obj(rng), fn (acc :: (List[(Str, jv.Json)], Rng), field :: s.Field) -> (List[(Str, jv.Json)], Rng) {
    let entries := match acc {
      (e1, _r) => e1,
    }
    let r := match acc {
      (_e, r1) => r1,
    }
    if field.required {
      let gen := gen_kind(field.kind, r)
      let v := match gen {
        (v1, _) => v1,
      }
      let r2 := match gen {
        (_, r1) => r1,
      }
      (list.concat(entries, [(field.name, v)]), r2)
    } else {
      let coin := random.int(r, 0, 1)
      let bit := match coin {
        (b, _) => b,
      }
      let r1 := match coin {
        (_, r1) => r1,
      }
      if bit == 1 {
        let gen := gen_kind(field.kind, r1)
        let v := match gen {
          (v1, _) => v1,
        }
        let r2 := match gen {
          (_, r2) => r2,
        }
        (list.concat(entries, [(field.name, v)]), r2)
      } else {
        (entries, r1)
      }
    }
  })
  let entries := match result {
    (e1, _) => e1,
  }
  let rng_out := match result {
    (_, r1) => r1,
  }
  (JObj(entries), rng_out)
}

# Polymorphic empty accumulator (lex-lang#319 workaround).
fn init_obj(rng :: Rng) -> (List[(Str, jv.Json)], Rng) {
  ([], rng)
}

fn init_list(rng :: Rng) -> (List[jv.Json], Rng) {
  ([], rng)
}

# Dispatch on the field's kind and produce a matching `Json`.
fn gen_kind(kind :: s.FieldKind, rng :: Rng) -> (jv.Json, Rng) {
  match kind {
    KStr(checks) => gen_str(checks, rng),
    KInt(checks) => gen_int(checks, rng),
    KFloat(checks) => gen_float(checks, rng),
    KBool => gen_bool(rng),
    KArray(elem, shape) => gen_array(elem, shape, rng),
    KObject(sub) => generate(sub, rng),
  }
}

# Generate a `Str`. If a known-format check is present (Email,
# Url, Uuid), emit a known-valid sample so the validator accepts.
# `StrPattern` / `StrStartsWith` / `StrEndsWith` are general
# enough that no fixed sample works; we emit a plain alphabetic
# string and let the property-test signal failure if the schema
# is using a pattern the generator can't satisfy.
fn gen_str(checks :: List[c.StrCheck], rng :: Rng) -> (jv.Json, Rng) {
  if has_email(checks) {
    gen_email(rng)
  } else {
    if has_url(checks) {
      gen_url(rng)
    } else {
      if has_uuid(checks) {
        gen_uuid(rng)
      } else {
        if has_one_of(checks) {
          gen_one_of_str(checks, rng)
        } else {
          let bounds := str_len_bounds(checks)
          let lo := match bounds {
            (l, _) => l,
          }
          let hi := match bounds {
            (_, h) => h,
          }
          let len_draw := random.int(rng, lo, hi)
          let len_ := match len_draw {
            (n, _) => n,
          }
          let r := match len_draw {
            (_, r1) => r1,
          }
          gen_str_of_len(len_, r)
        }
      }
    }
  }
}

fn has_email(checks :: List[c.StrCheck]) -> Bool {
  list.fold(checks, false, fn (acc :: Bool, chk :: c.StrCheck) -> Bool {
    acc or match chk {
      StrEmail => true,
      _ => false,
    }
  })
}

fn has_url(checks :: List[c.StrCheck]) -> Bool {
  list.fold(checks, false, fn (acc :: Bool, chk :: c.StrCheck) -> Bool {
    acc or match chk {
      StrUrl => true,
      _ => false,
    }
  })
}

fn has_uuid(checks :: List[c.StrCheck]) -> Bool {
  list.fold(checks, false, fn (acc :: Bool, chk :: c.StrCheck) -> Bool {
    acc or match chk {
      StrUuid => true,
      _ => false,
    }
  })
}

fn has_one_of(checks :: List[c.StrCheck]) -> Bool {
  list.fold(checks, false, fn (acc :: Bool, chk :: c.StrCheck) -> Bool {
    acc or match chk {
      StrOneOf(_) => true,
      _ => false,
    }
  })
}

fn gen_one_of_str(checks :: List[c.StrCheck], rng :: Rng) -> (jv.Json, Rng) {
  let opts := find_one_of(checks)
  match random.choose(rng, opts) {
    None => (JStr(""), rng),
    Some(p) => match p {
      (s, r) => (JStr(s), r),
    },
  }
}

fn find_one_of(checks :: List[c.StrCheck]) -> List[Str] {
  list.fold(checks, [], fn (acc :: List[Str], c :: c.StrCheck) -> List[Str] {
    match c {
      StrOneOf(opts) => if list.is_empty(acc) {
        opts
      } else {
        acc
      },
      _ => acc,
    }
  })
}

fn gen_str_of_len(len_ :: Int, rng :: Rng) -> (jv.Json, Rng) {
  let alphabet := alphabet_chars()
  let result := list.fold(list.range(0, len_), gen_str_init(rng), fn (acc :: (Str, Rng), _i :: Int) -> (Str, Rng) {
    let s := match acc {
      (s1, _) => s1,
    }
    let r := match acc {
      (_, r1) => r1,
    }
    match random.choose(r, alphabet) {
      None => (s, r),
      Some(pair) => match pair {
        (c, r2) => (str.concat(s, c), r2),
      },
    }
  })
  let s := match result {
    (s1, _) => s1,
  }
  let r := match result {
    (_, r1) => r1,
  }
  (JStr(s), r)
}

fn gen_str_init(rng :: Rng) -> (Str, Rng) {
  ("", rng)
}

fn alphabet_chars() -> List[Str] {
  ["a", "b", "c", "d", "e", "f", "g", "h", "i", "j", "k", "l", "m", "n", "o", "p", "q", "r", "s", "t", "u", "v", "w", "x", "y", "z", "0", "1", "2", "3", "4", "5", "6", "7", "8", "9"]
}

# Email / URL / UUID generators emit *known-valid* values; the
# random arm is the local-part / host / hex-digits, so successive
# runs vary while still passing the format check.
fn gen_email(rng :: Rng) -> (jv.Json, Rng) {
  let local := gen_str_of_len(6, rng)
  let l := match local {
    (JStr(s), _) => s,
    _ => "",
  }
  let r := match local {
    (_, r1) => r1,
  }
  (JStr(str.concat(l, "@example.com")), r)
}

fn gen_url(rng :: Rng) -> (jv.Json, Rng) {
  let host := gen_str_of_len(8, rng)
  let h := match host {
    (JStr(s), _) => s,
    _ => "",
  }
  let r := match host {
    (_, r1) => r1,
  }
  (JStr(str.concat("https://", str.concat(h, ".example.com/"))), r)
}

fn gen_uuid(rng :: Rng) -> (jv.Json, Rng) {
  let hex := hex_chars()
  let g8 := gen_hex_run(8, rng, hex)
  let s1 := match g8 {
    (s1, _) => s1,
  }
  let r1 := match g8 {
    (_, r1) => r1,
  }
  let g4a := gen_hex_run(4, r1, hex)
  let s2 := match g4a {
    (s, _) => s,
  }
  let r2 := match g4a {
    (_, r) => r,
  }
  let g4b := gen_hex_run(4, r2, hex)
  let s3 := match g4b {
    (s, _) => s,
  }
  let r3 := match g4b {
    (_, r) => r,
  }
  let g4c := gen_hex_run(4, r3, hex)
  let s4 := match g4c {
    (s, _) => s,
  }
  let r4 := match g4c {
    (_, r) => r,
  }
  let g12 := gen_hex_run(12, r4, hex)
  let s5 := match g12 {
    (s, _) => s,
  }
  let r5 := match g12 {
    (_, r) => r,
  }
  let joined := str.concat(s1, str.concat("-", str.concat(s2, str.concat("-", str.concat(s3, str.concat("-", str.concat(s4, str.concat("-", s5))))))))
  (JStr(joined), r5)
}

fn hex_chars() -> List[Str] {
  ["0", "1", "2", "3", "4", "5", "6", "7", "8", "9", "a", "b", "c", "d", "e", "f"]
}

fn gen_hex_run(n :: Int, rng :: Rng, alphabet :: List[Str]) -> (Str, Rng) {
  list.fold(list.range(0, n), ("", rng), fn (acc :: (Str, Rng), _i :: Int) -> (Str, Rng) {
    let s := match acc {
      (s1, _) => s1,
    }
    let r := match acc {
      (_, r1) => r1,
    }
    match random.choose(r, alphabet) {
      None => (s, r),
      Some(pair) => match pair {
        (c, r2) => (str.concat(s, c), r2),
      },
    }
  })
}

fn gen_int(checks :: List[c.IntCheck], rng :: Rng) -> (jv.Json, Rng) {
  let opts := find_one_of_int(checks)
  if list.is_empty(opts) {
    let bounds := int_bounds(checks)
    let lo := match bounds {
      (l, _) => l,
    }
    let hi := match bounds {
      (_, h) => h,
    }
    let real_hi := if hi < lo {
      lo
    } else {
      hi
    }
    let draw := random.int(rng, lo, real_hi)
    let n := match draw {
      (n1, _) => n1,
    }
    let r := match draw {
      (_, r1) => r1,
    }
    (JInt(n), r)
  } else {
    match random.choose(rng, opts) {
      None => (JInt(0), rng),
      Some(p) => match p {
        (n, r) => (JInt(n), r),
      },
    }
  }
}

fn find_one_of_int(checks :: List[c.IntCheck]) -> List[Int] {
  list.fold(checks, [], fn (acc :: List[Int], c :: c.IntCheck) -> List[Int] {
    match c {
      IntOneOf(opts) => if list.is_empty(acc) {
        opts
      } else {
        acc
      },
      _ => acc,
    }
  })
}

fn gen_float(checks :: List[c.FloatCheck], rng :: Rng) -> (jv.Json, Rng) {
  let bounds := float_bounds(checks)
  let lo := match bounds {
    (l, _) => l,
  }
  let hi := match bounds {
    (_, h) => h,
  }
  let real_hi := if hi < lo {
    lo
  } else {
    hi
  }
  let draw := random.float(rng)
  let u := match draw {
    (f, _) => f,
  }
  let r := match draw {
    (_, r1) => r1,
  }
  (JFloat(lo + u * (real_hi - lo)), r)
}

fn gen_bool(rng :: Rng) -> (jv.Json, Rng) {
  let draw := random.int(rng, 0, 1)
  let n := match draw {
    (b, _) => b,
  }
  let r := match draw {
    (_, r1) => r1,
  }
  (JBool(n == 1), r)
}

fn gen_array(elem :: s.FieldKind, shape :: List[c.ListCheck], rng :: Rng) -> (jv.Json, Rng) {
  let bounds := list_len_bounds(shape)
  let lo := match bounds {
    (l, _) => l,
  }
  let hi := match bounds {
    (_, h) => h,
  }
  let len_draw := random.int(rng, lo, hi)
  let n := match len_draw {
    (m, _) => m,
  }
  let r := match len_draw {
    (_, r1) => r1,
  }
  let result := list.fold(list.range(0, n), init_list(r), fn (acc :: (List[jv.Json], Rng), _i :: Int) -> (List[jv.Json], Rng) {
    let items := match acc {
      (i1, _) => i1,
    }
    let r1 := match acc {
      (_, r1) => r1,
    }
    let gen := gen_kind(elem, r1)
    let v := match gen {
      (v1, _) => v1,
    }
    let r2 := match gen {
      (_, r2) => r2,
    }
    (list.concat(items, [v]), r2)
  })
  let items := match result {
    (i1, _) => i1,
  }
  let r2 := match result {
    (_, r1) => r1,
  }
  (JList(items), r2)
}

# ---- The round-trip property -------------------------------------
# Run `n` rounds of (generate → validate); return Ok(n) on a clean
# sweep, Err(...) on the first failure with the generator's input
# attached. Useful in test suites as a property assertion.
fn round_trip(schema :: s.ModelSchema, iterations :: Int, seed :: Int) -> Result[Int, e.Errors] {
  round_trip_loop(schema, iterations, random.seed(seed), 0)
}

fn round_trip_loop(schema :: s.ModelSchema, remaining :: Int, rng :: Rng, passed :: Int) -> Result[Int, e.Errors] {
  if remaining <= 0 {
    Ok(passed)
  } else {
    let g := generate(schema, rng)
    let sample := match g {
      (v, _) => v,
    }
    let r2 := match g {
      (_, r) => r,
    }
    match s.validate(schema, sample) {
      Ok(_) => round_trip_loop(schema, remaining - 1, r2, passed + 1),
      Err(es) => {
        let path := str.concat("iteration[", str.concat(int.to_str(passed), "]"))
        Err(list.concat(e.single(path, "round_trip_fail", str.concat("generator produced an invalid sample; serialized: ", jv.stringify(sample))), es))
      },
    }
  }
}

# ---- Min/max helpers ---------------------------------------------
fn max_int(a :: Int, b :: Int) -> Int {
  if a > b {
    a
  } else {
    b
  }
}

fn min_int(a :: Int, b :: Int) -> Int {
  if a < b {
    a
  } else {
    b
  }
}

fn max_float(a :: Float, b :: Float) -> Float {
  if a > b {
    a
  } else {
    b
  }
}

fn min_float(a :: Float, b :: Float) -> Float {
  if a < b {
    a
  } else {
    b
  }
}

