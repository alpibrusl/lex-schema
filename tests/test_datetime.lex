# Tests for `src/datetime.lex` — ISO 8601 parsing + ordered bounds.

import "std.list" as list

import "std.str" as str

import "../src/error" as e

import "../src/datetime" as dt

# ---- Parse-only ---------------------------------------------------
fn parse_canonical_form() -> Result[Unit, Str] {
  match dt.check_iso_datetime("d", "2026-05-12T14:30:00Z", []) {
    Ok(_) => Ok(()),
    Err(_) => Err("expected Ok"),
  }
}

fn parse_with_offset() -> Result[Unit, Str] {
  match dt.check_iso_datetime("d", "2026-05-12T14:30:00+05:30", []) {
    Ok(_) => Ok(()),
    Err(_) => Err("expected Ok"),
  }
}

fn parse_invalid() -> Result[Unit, Str] {
  match dt.check_iso_datetime("d", "not-a-date", []) {
    Ok(_) => Err("should fail"),
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

# ---- DateBefore / DateAfter --------------------------------------
fn before_passes_when_earlier() -> Result[Unit, Str] {
  match dt.check_iso_datetime("d", "2026-01-01T00:00:00Z", [DateBefore("2026-12-31T23:59:59Z")]) {
    Ok(_) => Ok(()),
    Err(_) => Err("expected Ok"),
  }
}

fn before_fails_when_later() -> Result[Unit, Str] {
  match dt.check_iso_datetime("d", "2027-01-01T00:00:00Z", [DateBefore("2026-12-31T23:59:59Z")]) {
    Ok(_) => Err("should fail"),
    Err(es) => match list.head(es) {
      None => Err("empty"),
      Some(er) => if er.code == "max" {
        Ok(())
      } else {
        Err(str.concat("wrong code: ", er.code))
      },
    },
  }
}

fn after_passes_when_later() -> Result[Unit, Str] {
  match dt.check_iso_datetime("d", "2026-06-15T12:00:00Z", [DateAfter("2026-01-01T00:00:00Z")]) {
    Ok(_) => Ok(()),
    Err(_) => Err("expected Ok"),
  }
}

fn after_fails_when_equal() -> Result[Unit, Str] {
  match dt.check_iso_datetime("d", "2026-01-01T00:00:00Z", [DateAfter("2026-01-01T00:00:00Z")]) {
    Ok(_) => Err("should fail"),
    Err(_) => Ok(()),
  }
}

fn at_or_after_passes_when_equal() -> Result[Unit, Str] {
  match dt.check_iso_datetime("d", "2026-01-01T00:00:00Z", [DateAtOrAfter("2026-01-01T00:00:00Z")]) {
    Ok(_) => Ok(()),
    Err(_) => Err("expected Ok"),
  }
}

# ---- DateInRange --------------------------------------------------
fn in_range_inside() -> Result[Unit, Str] {
  match dt.check_iso_datetime("d", "2026-06-15T12:00:00Z", [DateInRange("2026-01-01T00:00:00Z", "2026-12-31T23:59:59Z")]) {
    Ok(_) => Ok(()),
    Err(_) => Err("expected Ok"),
  }
}

fn in_range_below() -> Result[Unit, Str] {
  match dt.check_iso_datetime("d", "2025-12-31T00:00:00Z", [DateInRange("2026-01-01T00:00:00Z", "2026-12-31T23:59:59Z")]) {
    Ok(_) => Err("should fail"),
    Err(_) => Ok(()),
  }
}

fn in_range_above() -> Result[Unit, Str] {
  match dt.check_iso_datetime("d", "2027-01-01T00:00:00Z", [DateInRange("2026-01-01T00:00:00Z", "2026-12-31T23:59:59Z")]) {
    Ok(_) => Err("should fail"),
    Err(_) => Ok(()),
  }
}

# ---- Accumulation ------------------------------------------------
fn accumulates_multiple_checks() -> Result[Unit, Str] {
  match dt.check_iso_datetime("d", "2030-01-01T00:00:00Z", [DateBefore("2026-12-31T23:59:59Z"), DateAtOrBefore("2025-06-01T00:00:00Z")]) {
    Ok(_) => Err("should fail"),
    Err(es) => if list.len(es) == 2 {
      Ok(())
    } else {
      Err("expected 2 errors")
    },
  }
}

# ---- Returns canonical form --------------------------------------
fn returns_canonical_form() -> Result[Unit, Str] {
  match dt.check_iso_datetime("d", "2026-05-12T17:30:00+03:00", []) {
    Ok(canonical) => if str.contains(canonical, "2026-05-12") {
      Ok(())
    } else {
      Err(str.concat("got: ", canonical))
    },
    Err(_) => Err("expected Ok"),
  }
}

# ---- Suite --------------------------------------------------------
fn suite() -> List[Result[Unit, Str]] {
  [parse_canonical_form(), parse_with_offset(), parse_invalid(), before_passes_when_earlier(), before_fails_when_later(), after_passes_when_later(), after_fails_when_equal(), at_or_after_passes_when_equal(), in_range_inside(), in_range_below(), in_range_above(), accumulates_multiple_checks(), returns_canonical_form()]
}

fn run_all() -> Int {
  list.fold(suite(), 0, fn (acc :: Int, v :: Result[Unit, Str]) -> Int {
    match v {
      Ok(_) => acc,
      Err(_) => acc + 1,
    }
  })
}

