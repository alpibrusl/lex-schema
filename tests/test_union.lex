# Tests for `src/union.lex` — discriminated-union dispatch.

import "std.list" as list
import "std.str"  as str

import "../src/error"       as e
import "../src/constraints" as c
import "../src/combine"     as cm
import "../src/json_value"  as jv
import "../src/union"       as u

# A small ADT to dispatch into.
type Event =
    Hello({ who :: Str })
  | Goodbye({ who :: Str, reason :: Str })

fn make_hello(j :: jv.Json) -> Result[Event, e.Errors] {
  match jv.j_str("", j, "who", [StrMinLen(1)]) {
    Ok(w)   => Ok(Hello({ who: w })),
    Err(es) => Err(es),
  }
}

fn make_goodbye(j :: jv.Json) -> Result[Event, e.Errors] {
  cm.combine2(
    jv.j_str("", j, "who",    [StrMinLen(1)]),
    jv.j_str("", j, "reason", [StrMinLen(1)]),
    fn (w :: Str, r :: Str) -> Event { Goodbye({ who: w, reason: r }) }
  )
}

fn branches() -> List[(Str, (jv.Json) -> Result[Event, e.Errors])] {
  [("hello", make_hello), ("goodbye", make_goodbye)]
}

# ---- Tests --------------------------------------------------------

fn dispatches_hello() -> Result[Unit, Str] {
  match jv.parse("{\"kind\":\"hello\",\"who\":\"alice\"}") {
    Err(_) => Err("parse"),
    Ok(j)  => match u.discriminate("", j, "kind", branches()) {
      Ok(_)  => Ok(()),
      Err(_) => Err("expected Ok"),
    },
  }
}

fn dispatches_goodbye() -> Result[Unit, Str] {
  match jv.parse("{\"kind\":\"goodbye\",\"who\":\"alice\",\"reason\":\"sleepy\"}") {
    Err(_) => Err("parse"),
    Ok(j)  => match u.discriminate("", j, "kind", branches()) {
      Ok(_)  => Ok(()),
      Err(_) => Err("expected Ok"),
    },
  }
}

fn missing_tag() -> Result[Unit, Str] {
  match jv.parse("{\"who\":\"alice\"}") {
    Err(_) => Err("parse"),
    Ok(j)  => match u.discriminate("", j, "kind", branches()) {
      Ok(_)   => Err("expected Err"),
      Err(es) => match list.head(es) {
        None     => Err("empty"),
        Some(er) => if er.code == "missing" { Ok(()) } else {
          Err(str.concat("wrong code: ", er.code))
        },
      },
    },
  }
}

fn unknown_tag() -> Result[Unit, Str] {
  match jv.parse("{\"kind\":\"farewell\",\"who\":\"alice\"}") {
    Err(_) => Err("parse"),
    Ok(j)  => match u.discriminate("", j, "kind", branches()) {
      Ok(_)   => Err("expected Err"),
      Err(es) => match list.head(es) {
        None     => Err("empty"),
        Some(er) => if er.code == "one_of" { Ok(()) } else {
          Err(str.concat("wrong code: ", er.code))
        },
      },
    },
  }
}

fn unknown_tag_message_lists_known() -> Result[Unit, Str] {
  match jv.parse("{\"kind\":\"x\"}") {
    Err(_) => Err("parse"),
    Ok(j)  => match u.discriminate("", j, "kind", branches()) {
      Ok(_)   => Err("expected Err"),
      Err(es) => match list.head(es) {
        None     => Err("empty"),
        Some(er) => if str.contains(er.message, "hello") and str.contains(er.message, "goodbye") {
          Ok(())
        } else {
          Err(str.concat("message missing known tags: ", er.message))
        },
      },
    },
  }
}

fn branch_errors_propagate() -> Result[Unit, Str] {
  # "goodbye" needs both who and reason; we send neither.
  match jv.parse("{\"kind\":\"goodbye\"}") {
    Err(_) => Err("parse"),
    Ok(j)  => match u.discriminate("", j, "kind", branches()) {
      Ok(_)   => Err("expected Err"),
      Err(es) => if list.len(es) == 2 { Ok(()) } else {
        Err("expected 2 errors from the branch validator")
      },
    },
  }
}

# ---- Suite --------------------------------------------------------

fn suite() -> List[Result[Unit, Str]] {
  [
    dispatches_hello(),
    dispatches_goodbye(),
    missing_tag(),
    unknown_tag(),
    unknown_tag_message_lists_known(),
    branch_errors_propagate(),
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
