# Tests for the error type and its formatting helpers.

import "std.list" as list

import "std.str" as str

import "../src/error" as e

fn error_record_shape() -> Result[Unit, Str] {
  let err := e.error("user.email", "type", "expected string")
  if err.path == "user.email" and err.code == "type" and err.message == "expected string" {
    Ok(())
  } else {
    Err("error fields not set as expected")
  }
}

fn single_makes_one_item_list() -> Result[Unit, Str] {
  let es := e.single("p", "c", "m")
  if list.len(es) == 1 {
    Ok(())
  } else {
    Err("expected length 1")
  }
}

fn concat_merges() -> Result[Unit, Str] {
  let a := e.single("x", "c1", "m1")
  let b := e.single("y", "c2", "m2")
  let merged := e.concat(a, b)
  if list.len(merged) == 2 {
    Ok(())
  } else {
    Err("merged size != 2")
  }
}

fn flatten_handles_empty() -> Result[Unit, Str] {
  let flat := e.flatten([e.single("x", "c", "m"), [], e.single("y", "c", "m")])
  if list.len(flat) == 2 {
    Ok(())
  } else {
    Err("flatten lost an entry")
  }
}

fn prefix_path_handles_empty_inner() -> Result[Unit, Str] {
  let inner := e.single("", "c", "m")
  let prefixed := e.prefix_path("address", inner)
  match list.head(prefixed) {
    None => Err("empty"),
    Some(er) => if er.path == "address" {
      Ok(())
    } else {
      Err(str.concat("wrong path: ", er.path))
    },
  }
}

fn prefix_path_joins_with_dot() -> Result[Unit, Str] {
  let inner := e.single("zip", "c", "m")
  let prefixed := e.prefix_path("address", inner)
  match list.head(prefixed) {
    None => Err("empty"),
    Some(er) => if er.path == "address.zip" {
      Ok(())
    } else {
      Err(str.concat("wrong path: ", er.path))
    },
  }
}

fn prefix_index_emits_brackets() -> Result[Unit, Str] {
  let inner := e.single("name", "c", "m")
  let prefixed := e.prefix_index("items", 3, inner)
  match list.head(prefixed) {
    None => Err("empty"),
    Some(er) => if er.path == "items[3].name" {
      Ok(())
    } else {
      Err(str.concat("wrong path: ", er.path))
    },
  }
}

fn format_one() -> Result[Unit, Str] {
  let es := e.single("x", "c", "m")
  if e.format(es) == "x: m [c]" {
    Ok(())
  } else {
    Err(str.concat("got: ", e.format(es)))
  }
}

fn format_root_path() -> Result[Unit, Str] {
  let es := e.single("", "parse", "bad json")
  if e.format(es) == "<root>: bad json [parse]" {
    Ok(())
  } else {
    Err(str.concat("got: ", e.format(es)))
  }
}

fn is_ok_empty_true() -> Result[Unit, Str] {
  if e.is_ok([]) {
    Ok(())
  } else {
    Err("[] should be ok")
  }
}

fn is_ok_nonempty_false() -> Result[Unit, Str] {
  if e.is_ok(e.single("p", "c", "m")) {
    Err("singleton should not be ok")
  } else {
    Ok(())
  }
}

fn suite() -> List[Result[Unit, Str]] {
  [error_record_shape(), single_makes_one_item_list(), concat_merges(), flatten_handles_empty(), prefix_path_handles_empty_inner(), prefix_path_joins_with_dot(), prefix_index_emits_brackets(), format_one(), format_root_path(), is_ok_empty_true(), is_ok_nonempty_false()]
}

fn run_all() -> Int {
  list.fold(suite(), 0, fn (acc :: Int, v :: Result[Unit, Str]) -> Int {
    match v {
      Ok(_) => acc,
      Err(_) => acc + 1,
    }
  })
}

