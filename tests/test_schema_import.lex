# Tests for `src/schema_import.lex` — JSON Schema → ModelSchema.

import "std.list" as list
import "std.str"  as str

import "../src/error"         as e
import "../src/json_value"    as jv
import "../src/schema"        as s
import "../src/schema_import" as si
import "../src/constraints"   as c

# ---- Round-trip with an emitted schema ----------------------------

fn original() -> s.ModelSchema {
  {
    title: "Original", description: "",
    fields: [
      s.required_str("a", [StrMinLen(1), StrMaxLen(10)]),
      s.required_int("b", [IntInRange(0, 100)]),
      s.optional(s.required_str("c", [StrEmail])),
    ],
  }
}

fn round_trip_preserves_fields() -> Result[Unit, Str] {
  let text := jv.stringify(s.to_json_schema(original()))
  match si.from_str(text) {
    Err(_)       => Err("import failed"),
    Ok(imported) => if list.len(imported.fields) == list.len(original().fields) {
      Ok(())
    } else { Err("field count differs") },
  }
}

fn round_trip_preserves_required() -> Result[Unit, Str] {
  let text := jv.stringify(s.to_json_schema(original()))
  match si.from_str(text) {
    Err(_)       => Err("import failed"),
    Ok(imported) => {
      # Find field `c`, check it stayed optional.
      let c_required := list.fold(imported.fields, true,
        fn (acc :: Bool, f :: s.Field) -> Bool {
          if f.name == "c" { f.required } else { acc }
        })
      if c_required { Err("c should be optional") } else { Ok(()) }
    },
  }
}

# ---- Direct parses -----------------------------------------------

fn parses_minimal_schema() -> Result[Unit, Str] {
  match si.from_str(
    "{\"type\":\"object\",\"properties\":{\"x\":{\"type\":\"string\"}},\"required\":[\"x\"]}"
  ) {
    Ok(m)  => if list.len(m.fields) == 1 { Ok(()) } else { Err("wrong count") },
    Err(_) => Err("parse failed"),
  }
}

fn parses_int_min_max() -> Result[Unit, Str] {
  match si.from_str(
    "{\"type\":\"object\",\"properties\":{\"n\":{\"type\":\"integer\",\"minimum\":0,\"maximum\":99}},\"required\":[\"n\"]}"
  ) {
    Err(_) => Err("parse failed"),
    Ok(m)  => match list.head(m.fields) {
      None       => Err("no fields"),
      Some(f)    => match f.kind {
        KInt(checks) => if list.len(checks) == 2 { Ok(()) } else {
          Err("expected 2 int checks")
        },
        _ => Err("not KInt"),
      },
    },
  }
}

fn parses_email_format() -> Result[Unit, Str] {
  match si.from_str(
    "{\"type\":\"object\",\"properties\":{\"e\":{\"type\":\"string\",\"format\":\"email\"}},\"required\":[\"e\"]}"
  ) {
    Err(_) => Err("parse failed"),
    Ok(m)  => match list.head(m.fields) {
      None    => Err("no fields"),
      Some(f) => match f.kind {
        KStr(checks) => {
          let has_email := list.fold(checks, false,
            fn (acc :: Bool, chk :: c.StrCheck) -> Bool {
              acc or match chk { StrEmail => true, _ => false }
            })
          if has_email { Ok(()) } else { Err("StrEmail missing") }
        },
        _ => Err("not KStr"),
      },
    },
  }
}

# ---- Imported schema validates correctly --------------------------

fn imported_schema_accepts_valid() -> Result[Unit, Str] {
  let text := jv.stringify(s.to_json_schema(original()))
  match si.from_str(text) {
    Err(_)       => Err("import"),
    Ok(imported) => match jv.parse("{\"a\":\"hi\",\"b\":42}") {
      Err(_) => Err("parse"),
      Ok(payload) => match s.validate(imported, payload) {
        Ok(_)  => Ok(()),
        Err(_) => Err("imported schema rejected a valid payload"),
      },
    },
  }
}

fn imported_schema_rejects_invalid() -> Result[Unit, Str] {
  let text := jv.stringify(s.to_json_schema(original()))
  match si.from_str(text) {
    Err(_)       => Err("import"),
    Ok(imported) => match jv.parse("{\"a\":\"toolongstring!!!\",\"b\":42}") {
      Err(_) => Err("parse"),
      Ok(payload) => match s.validate(imported, payload) {
        Ok(_)   => Err("should have rejected"),
        Err(_)  => Ok(()),
      },
    },
  }
}

# ---- Suite --------------------------------------------------------

fn suite() -> List[Result[Unit, Str]] {
  [
    round_trip_preserves_fields(),
    round_trip_preserves_required(),
    parses_minimal_schema(),
    parses_int_min_max(),
    parses_email_format(),
    imported_schema_accepts_valid(),
    imported_schema_rejects_invalid(),
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
