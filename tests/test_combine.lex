# Tests for the applicative combinators.
#
# The headline property is *error accumulation*: when N branches all
# fail, the combined result should carry N errors, not 1. These tests
# pin that invariant.

import "std.list" as list
import "std.str"  as str
import "std.int"  as int

import "../src/error"   as e
import "../src/combine" as cm

# Errors and Results we'll thread through the tests.
fn err1() -> List[e.Error] { e.single("a", "type", "bad a") }
fn err2() -> List[e.Error] { e.single("b", "type", "bad b") }
fn err3() -> List[e.Error] { e.single("c", "type", "bad c") }

# Builder used by `combine3`.
fn make_record(a :: Int, b :: Int, c :: Int) -> { a :: Int, b :: Int, c :: Int } {
  { a: a, b: b, c: c }
}

# ---- combine2 -----------------------------------------------------

fn combine2_all_ok() -> Result[Unit, Str] {
  match cm.combine2(Ok(1), Ok(2), fn (a :: Int, b :: Int) -> Int { a + b }) {
    Ok(3)  => Ok(()),
    Ok(n)  => Err(str.concat("expected 3, got ", int.to_str(n))),
    Err(_) => Err("unexpected Err"),
  }
}

# Helper that wraps the constructor with an explicit return type
# so the polymorphic `Result[_, _]` gets pinned at the call site —
# Lex doesn't have an `(expr :: Type)` ascription form.
fn err_int(es :: List[e.Error]) -> Result[Int, List[e.Error]] { Err(es) }
fn ok_int(n :: Int)        -> Result[Int, List[e.Error]] { Ok(n) }

fn combine2_both_err() -> Result[Unit, Str] {
  match cm.combine2(
    err_int(err1()),
    err_int(err2()),
    fn (a :: Int, b :: Int) -> Int { a + b }
  ) {
    Ok(_)    => Err("expected Err"),
    Err(es)  => if list.len(es) == 2 { Ok(()) } else {
      Err(str.concat("expected 2 errors, got len=", int.to_str(list.len(es))))
    },
  }
}

fn combine2_one_err() -> Result[Unit, Str] {
  match cm.combine2(
    ok_int(1),
    err_int(err2()),
    fn (a :: Int, b :: Int) -> Int { a + b }
  ) {
    Ok(_)    => Err("expected Err"),
    Err(es)  => if list.len(es) == 1 { Ok(()) } else {
      Err("expected 1 error")
    },
  }
}

# ---- combine3 -----------------------------------------------------

fn combine3_all_err_accumulates() -> Result[Unit, Str] {
  let r := cm.combine3(
    err_int(err1()),
    err_int(err2()),
    err_int(err3()),
    make_record
  )
  match r {
    Ok(_)   => Err("expected Err"),
    Err(es) => if list.len(es) == 3 { Ok(()) } else {
      Err(str.concat("expected 3 errors, got len=", int.to_str(list.len(es))))
    },
  }
}

fn combine3_paths_preserved() -> Result[Unit, Str] {
  let r := cm.combine3(
    err_int(err1()),
    err_int(err2()),
    err_int(err3()),
    make_record
  )
  match r {
    Ok(_)   => Err("expected Err"),
    Err(es) => {
      let paths := list.map(es, fn (er :: e.Error) -> Str { er.path })
      if joined(paths) == "a,b,c" { Ok(()) } else {
        Err(str.concat("got paths: ", joined(paths)))
      }
    },
  }
}

# ---- and_then / or_else -------------------------------------------

fn and_then_chains() -> Result[Unit, Str] {
  let r := cm.and_then(
    Ok(5),
    fn (n :: Int) -> Result[Int, List[e.Error]] { Ok(n * 2) }
  )
  match r {
    Ok(10) => Ok(()),
    Ok(n)  => Err(str.concat("expected 10, got ", int.to_str(n))),
    Err(_) => Err("expected Ok"),
  }
}

fn and_then_short_circuits() -> Result[Unit, Str] {
  let r := cm.and_then(
    err_int(err1()),
    fn (n :: Int) -> Result[Int, List[e.Error]] { Ok(n * 2) }
  )
  match r {
    Ok(_)   => Err("expected Err"),
    Err(es) => if list.len(es) == 1 { Ok(()) } else { Err("wrong size") },
  }
}

fn or_else_recovers() -> Result[Unit, Str] {
  let r := cm.or_else(
    err_int(err1()),
    fn (_es :: List[e.Error]) -> Result[Int, List[e.Error]] { Ok(0) }
  )
  match r {
    Ok(0)  => Ok(()),
    Ok(n)  => Err(str.concat("expected 0, got ", int.to_str(n))),
    Err(_) => Err("expected recovery"),
  }
}

# ---- traverse -----------------------------------------------------

fn traverse_all_ok() -> Result[Unit, Str] {
  let r := cm.traverse([1, 2, 3],
    fn (n :: Int) -> Result[Int, List[e.Error]] { Ok(n + 1) })
  match r {
    Ok(out) => if list.len(out) == 3 { Ok(()) } else { Err("wrong len") },
    Err(_)  => Err("expected Ok"),
  }
}

fn traverse_accumulates() -> Result[Unit, Str] {
  let r := cm.traverse([1, 2, 3],
    fn (n :: Int) -> Result[Int, List[e.Error]] {
      if n == 2 { Err(e.single("at[1]", "type", "two")) } else { Ok(n) }
    })
  match r {
    Ok(_)   => Err("expected Err"),
    Err(es) => if list.len(es) == 1 { Ok(()) } else { Err("wrong size") },
  }
}

# ---- with_path ----------------------------------------------------

fn with_path_prefixes_errors() -> Result[Unit, Str] {
  let inner :: Result[Int, List[e.Error]] := Err(e.single("zip", "pattern", "bad"))
  let r := cm.with_path("address", inner)
  match r {
    Ok(_)    => Err("expected Err"),
    Err(es)  => match list.head(es) {
      None      => Err("empty"),
      Some(er)  => if er.path == "address.zip" { Ok(()) } else {
        Err(str.concat("wrong path: ", er.path))
      },
    },
  }
}

# ---- Suite --------------------------------------------------------

fn joined(xs :: List[Str]) -> Str { str.join(xs, ",") }

fn suite() -> List[Result[Unit, Str]] {
  [
    combine2_all_ok(),
    combine2_both_err(),
    combine2_one_err(),
    combine3_all_err_accumulates(),
    combine3_paths_preserved(),
    and_then_chains(),
    and_then_short_circuits(),
    or_else_recovers(),
    traverse_all_ok(),
    traverse_accumulates(),
    with_path_prefixes_errors(),
  ]
}

fn run_all() -> Int {
  list.fold(suite(), 0, fn (acc :: Int, v :: Result[Unit, Str]) -> Int {
    match v {
      Ok(_)  => acc,
      Err(_) => acc + 1,
    }
  })
}
