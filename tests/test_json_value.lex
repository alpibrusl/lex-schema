# Tests for `src/json_value.lex` — the Json ADT parser + extractors.

import "std.list" as list
import "std.str"  as str
import "std.int"  as int

import "../src/error"       as e
import "../src/constraints" as c
import "../src/json_value"  as jv

# ---- Parser: primitives -------------------------------------------

fn parse_null() -> Result[Unit, Str] {
  match jv.parse("null") {
    Ok(JNull) => Ok(()),
    Ok(_)     => Err("not JNull"),
    Err(_)    => Err("expected Ok"),
  }
}

fn parse_true() -> Result[Unit, Str] {
  match jv.parse("true") {
    Ok(JBool(true)) => Ok(()),
    _ => Err("not JBool(true)"),
  }
}

fn parse_false() -> Result[Unit, Str] {
  match jv.parse("false") {
    Ok(JBool(false)) => Ok(()),
    _ => Err("not JBool(false)"),
  }
}

fn parse_int_positive() -> Result[Unit, Str] {
  match jv.parse("42") {
    Ok(JInt(42)) => Ok(()),
    Ok(_)        => Err("wrong int"),
    Err(_)       => Err("expected Ok"),
  }
}

fn parse_int_negative() -> Result[Unit, Str] {
  # Negative-literal patterns aren't supported in Lex match (`Minus`
  # isn't a pattern token), so we bind and compare.
  match jv.parse("-17") {
    Ok(JInt(n)) => if n == -17 { Ok(()) } else { Err("wrong int") },
    _ => Err("not JInt"),
  }
}

fn parse_float() -> Result[Unit, Str] {
  match jv.parse("3.14") {
    Ok(JFloat(_)) => Ok(()),
    _ => Err("not a JFloat"),
  }
}

fn parse_string() -> Result[Unit, Str] {
  match jv.parse("\"hello\"") {
    Ok(JStr("hello")) => Ok(()),
    _ => Err("not JStr(\"hello\")"),
  }
}

fn parse_string_with_escape() -> Result[Unit, Str] {
  match jv.parse("\"a\\nb\"") {
    Ok(JStr("a\nb")) => Ok(()),
    _ => Err("escape not decoded"),
  }
}

# ---- Parser: containers -------------------------------------------

fn parse_empty_array() -> Result[Unit, Str] {
  match jv.parse("[]") {
    Ok(JList(xs)) => if list.len(xs) == 0 { Ok(()) } else { Err("nonempty") },
    _ => Err("not JList"),
  }
}

fn parse_array_mixed() -> Result[Unit, Str] {
  match jv.parse("[1, \"two\", true, null]") {
    Ok(JList(xs)) => if list.len(xs) == 4 { Ok(()) } else { Err("wrong len") },
    _ => Err("not JList"),
  }
}

fn parse_empty_object() -> Result[Unit, Str] {
  match jv.parse("{}") {
    Ok(JObj(xs)) => if list.len(xs) == 0 { Ok(()) } else { Err("nonempty") },
    _ => Err("not JObj"),
  }
}

fn parse_object_nested() -> Result[Unit, Str] {
  match jv.parse("{\"a\":{\"b\":1}}") {
    Ok(j)  => match jv.get_field(j, "a") {
      Some(inner) => match jv.get_field(inner, "b") {
        Some(JInt(1)) => Ok(()),
        _ => Err("nested b missing or wrong"),
      },
      None => Err("a missing"),
    },
    Err(_) => Err("parse failed"),
  }
}

fn parse_whitespace_tolerant() -> Result[Unit, Str] {
  match jv.parse("  { \"x\" : 1 ,\n  \"y\" : 2 }  ") {
    Ok(JObj(xs)) => if list.len(xs) == 2 { Ok(()) } else { Err("wrong len") },
    _ => Err("not JObj"),
  }
}

# ---- Parser: failures ---------------------------------------------

fn parse_unterminated_string() -> Result[Unit, Str] {
  match jv.parse("\"abc") {
    Err(_) => Ok(()),
    Ok(_)  => Err("should have failed"),
  }
}

fn parse_garbage() -> Result[Unit, Str] {
  match jv.parse("{not a key}") {
    Err(_) => Ok(()),
    Ok(_)  => Err("should have failed"),
  }
}

fn parse_trailing_garbage() -> Result[Unit, Str] {
  match jv.parse("42 hello") {
    Err(_) => Ok(()),
    Ok(_)  => Err("should have failed"),
  }
}

# ---- Extractors: j_str / j_int / j_bool / j_list / j_obj ---------

fn j_str_field_present() -> Result[Unit, Str] {
  match jv.parse("{\"name\":\"alice\"}") {
    Err(_) => Err("parse"),
    Ok(j)  => match jv.j_str("", j, "name", []) {
      Ok("alice") => Ok(()),
      Ok(_)       => Err("wrong str"),
      Err(_)      => Err("expected Ok"),
    },
  }
}

fn j_str_missing_field() -> Result[Unit, Str] {
  match jv.parse("{\"other\":\"x\"}") {
    Err(_) => Err("parse"),
    Ok(j)  => match jv.j_str("", j, "name", []) {
      Ok(_)   => Err("should be Err"),
      Err(es) => match list.head(es) {
        None      => Err("empty"),
        Some(er)  => if er.code == "missing" { Ok(()) } else {
          Err(str.concat("wrong code: ", er.code))
        },
      },
    },
  }
}

fn j_str_type_error() -> Result[Unit, Str] {
  match jv.parse("{\"name\":42}") {
    Err(_) => Err("parse"),
    Ok(j)  => match jv.j_str("", j, "name", []) {
      Ok(_)   => Err("should be Err"),
      Err(es) => match list.head(es) {
        None      => Err("empty"),
        Some(er)  => if er.code == "type" { Ok(()) } else {
          Err(str.concat("wrong code: ", er.code))
        },
      },
    },
  }
}

fn j_int_with_constraint() -> Result[Unit, Str] {
  match jv.parse("{\"age\":200}") {
    Err(_) => Err("parse"),
    Ok(j)  => match jv.j_int("", j, "age", [IntInRange(0, 130)]) {
      Ok(_)   => Err("should be Err"),
      Err(es) => if list.len(es) == 1 { Ok(()) } else { Err("wrong count") },
    },
  }
}

fn j_optional_absent_ok() -> Result[Unit, Str] {
  match jv.parse("{}") {
    Err(_) => Err("parse"),
    Ok(j)  => match jv.j_optional_str("", j, "nickname", []) {
      Ok(None) => Ok(()),
      _        => Err("expected Ok(None)"),
    },
  }
}

fn j_optional_null_ok() -> Result[Unit, Str] {
  # Explicit null in JSON should also map to None.
  match jv.parse("{\"nickname\":null}") {
    Err(_) => Err("parse"),
    Ok(j)  => match jv.j_optional_str("", j, "nickname", []) {
      Ok(None) => Ok(()),
      _        => Err("expected Ok(None)"),
    },
  }
}

fn j_optional_present_ok() -> Result[Unit, Str] {
  match jv.parse("{\"nickname\":\"Ally\"}") {
    Err(_) => Err("parse"),
    Ok(j)  => match jv.j_optional_str("", j, "nickname", [StrMaxLen(20)]) {
      Ok(Some("Ally")) => Ok(()),
      _ => Err("expected Ok(Some(\"Ally\"))"),
    },
  }
}

# ---- Suite --------------------------------------------------------

fn suite() -> List[Result[Unit, Str]] {
  [
    parse_null(),
    parse_true(),
    parse_false(),
    parse_int_positive(),
    parse_int_negative(),
    parse_float(),
    parse_string(),
    parse_string_with_escape(),
    parse_empty_array(),
    parse_array_mixed(),
    parse_empty_object(),
    parse_object_nested(),
    parse_whitespace_tolerant(),
    parse_unterminated_string(),
    parse_garbage(),
    parse_trailing_garbage(),
    j_str_field_present(),
    j_str_missing_field(),
    j_str_type_error(),
    j_int_with_constraint(),
    j_optional_absent_ok(),
    j_optional_null_ok(),
    j_optional_present_ok(),
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
