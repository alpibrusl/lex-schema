# Tests for the `cross_check` and `require` combinators in
# `src/combine.lex`.

import "std.list" as list

import "std.str" as str

import "../src/error" as e

import "../src/combine" as cm

# A toy record used across the suite.
type Pair = { a :: Int, b :: Int }

# Constructor pins the nominal Pair type — needed because lex's
# record-alias coercion doesn't reach into nested constructors
# (lex-lang#328).
fn pair(a :: Int, b :: Int) -> Pair {
  { a: a, b: b }
}

fn equal_check(p :: Pair) -> Option[e.Errors] {
  if p.a == p.b {
    None
  } else {
    Some(e.single("a", "mismatch", "a must equal b"))
  }
}

fn positive_check(p :: Pair) -> Option[e.Errors] {
  if p.a > 0 and p.b > 0 {
    None
  } else {
    Some(e.single("", "non_positive", "both must be > 0"))
  }
}

# ---- cross_check --------------------------------------------------
fn passes_all() -> Result[Unit, Str] {
  match cm.cross_check(pair(1, 1), [equal_check, positive_check]) {
    Ok(_) => Ok(()),
    Err(_) => Err("expected Ok"),
  }
}

fn fails_one() -> Result[Unit, Str] {
  match cm.cross_check(pair(1, 2), [equal_check, positive_check]) {
    Ok(_) => Err("expected Err"),
    Err(es) => if list.len(es) == 1 {
      Ok(())
    } else {
      Err("wrong count")
    },
  }
}

fn accumulates_both() -> Result[Unit, Str] {
  match cm.cross_check(pair(0, 1), [equal_check, positive_check]) {
    Ok(_) => Err("expected Err"),
    Err(es) => if list.len(es) == 2 {
      Ok(())
    } else {
      Err("expected 2")
    },
  }
}

# ---- require ------------------------------------------------------
fn require_passes() -> Result[Unit, Str] {
  match cm.require(pair(1, 1), fn (p :: Pair) -> Bool {
    p.a == p.b
  }, "a", "mismatch", "values must agree") {
    Ok(_) => Ok(()),
    Err(_) => Err("expected Ok"),
  }
}

fn require_fails() -> Result[Unit, Str] {
  match cm.require(pair(1, 2), fn (p :: Pair) -> Bool {
    p.a == p.b
  }, "a", "mismatch", "values must agree") {
    Ok(_) => Err("expected Err"),
    Err(es) => match list.head(es) {
      None => Err("empty"),
      Some(er) => if er.code == "mismatch" {
        Ok(())
      } else {
        Err(str.concat("wrong code: ", er.code))
      },
    },
  }
}

# ---- Sequencing with combineN ------------------------------------
fn make_pair(a :: Int, b :: Int) -> Pair {
  { a: a, b: b }
}

fn end_to_end_ok() -> Result[Unit, Str] {
  let r := cm.and_then(cm.combine2(Ok(2), Ok(2), make_pair), fn (p :: Pair) -> Result[Pair, e.Errors] {
    cm.cross_check(p, [equal_check])
  })
  match r {
    Ok(_) => Ok(()),
    Err(_) => Err("expected Ok"),
  }
}

fn end_to_end_cross_fails() -> Result[Unit, Str] {
  let r := cm.and_then(cm.combine2(Ok(2), Ok(3), make_pair), fn (p :: Pair) -> Result[Pair, e.Errors] {
    cm.cross_check(p, [equal_check])
  })
  match r {
    Ok(_) => Err("expected Err"),
    Err(es) => match list.head(es) {
      None => Err("empty"),
      Some(er) => if er.code == "mismatch" {
        Ok(())
      } else {
        Err(str.concat("wrong code: ", er.code))
      },
    },
  }
}

# ---- Suite --------------------------------------------------------
fn suite() -> List[Result[Unit, Str]] {
  [passes_all(), fails_one(), accumulates_both(), require_passes(), require_fails(), end_to_end_ok(), end_to_end_cross_fails()]
}

fn run_all_count() -> Int {
  list.fold(suite(), 0, fn (acc :: Int, v :: Result[Unit, Str]) -> Int {
    match v {
      Ok(_) => acc,
      Err(_) => acc + 1,
    }
  })
}

# `lex test` calls `run_all` and DISCARDS what it returns (lex-lang#757), so a
# returned failure count reports `ok` however many assertions failed. Only a
# raise fails a file — the same idiom lex-ems, lex-web and lex-guard use.
# Run `run_all_count` directly to see which assertions failed.
fn run_all() -> Unit {
  if run_all_count() == 0 {
    ()
  } else {
    let __boom := 1 / 0
    ()
  }
}

