# Tests for `src/form.lex` — HTTP form body decoders.

import "std.list" as list

import "std.str" as str

import "std.map" as map

import "../src/error" as e

import "../src/form" as form

# ---- decode_urlencoded -------------------------------------------
fn simple_kv() -> Result[Unit, Str] {
  let m := form.decode_urlencoded("a=1&b=2")
  match map.get(m, "a") {
    Some("1") => match map.get(m, "b") {
      Some("2") => Ok(()),
      _ => Err("b missing"),
    },
    _ => Err("a missing"),
  }
}

fn empty_body() -> Result[Unit, Str] {
  let m := form.decode_urlencoded("")
  if map.size(m) == 0 {
    Ok(())
  } else {
    Err("expected empty")
  }
}

fn bare_key() -> Result[Unit, Str] {
  let m := form.decode_urlencoded("flag&name=alice")
  match map.get(m, "flag") {
    Some("") => Ok(()),
    _ => Err("bare key not present"),
  }
}

fn plus_decodes_to_space() -> Result[Unit, Str] {
  let m := form.decode_urlencoded("greeting=hello+world")
  match map.get(m, "greeting") {
    Some("hello world") => Ok(()),
    _ => Err("plus didn't decode to space"),
  }
}

fn pct_decodes() -> Result[Unit, Str] {
  let m := form.decode_urlencoded("city=S%C3%A3o%20Paulo")
  match map.get(m, "city") {
    Some(s) => if str.contains(s, " ") and str.contains(s, "P") {
      Ok(())
    } else {
      Err(str.concat("decoded form: ", s))
    },
    _ => Err("city missing"),
  }
}

fn equals_in_value() -> Result[Unit, Str] {
  let m := form.decode_urlencoded("eq=a=b=c")
  match map.get(m, "eq") {
    Some("a=b=c") => Ok(()),
    Some(other) => Err(str.concat("got: ", other)),
    None => Err("missing"),
  }
}

# ---- decode_body content-type dispatch ---------------------------
fn dispatch_urlencoded_ok() -> Result[Unit, Str] {
  match form.decode_body("a=1", "application/x-www-form-urlencoded") {
    Ok(m) => if map.size(m) == 1 {
      Ok(())
    } else {
      Err("wrong size")
    },
    Err(_) => Err("rejected"),
  }
}

fn dispatch_with_charset_suffix() -> Result[Unit, Str] {
  match form.decode_body("a=1", "application/x-www-form-urlencoded; charset=UTF-8") {
    Ok(_) => Ok(()),
    Err(_) => Err("rejected charset-suffixed content-type"),
  }
}

fn dispatch_multipart_well_formed() -> Result[Unit, Str] {
  match form.decode_body("...", "multipart/form-data; boundary=X") {
    Ok(_) => Err("malformed body should not parse"),
    Err(es) => match list.head(es) {
      None => Err("empty"),
      Some(er) => if er.code == "format" {
        Ok(())
      } else {
        Err(str.concat("wrong code: ", er.code))
      },
    },
  }
}

fn dispatch_unsupported_ct() -> Result[Unit, Str] {
  match form.decode_body("body", "text/csv") {
    Ok(_) => Err("should reject"),
    Err(es) => match list.head(es) {
      None => Err("empty"),
      Some(er) => if er.code == "type" {
        Ok(())
      } else {
        Err(str.concat("wrong code: ", er.code))
      },
    },
  }
}

# ---- Suite -------------------------------------------------------
fn suite() -> List[Result[Unit, Str]] {
  [simple_kv(), empty_body(), bare_key(), plus_decodes_to_space(), pct_decodes(), equals_in_value(), dispatch_urlencoded_ok(), dispatch_with_charset_suffix(), dispatch_multipart_well_formed(), dispatch_unsupported_ct()]
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

