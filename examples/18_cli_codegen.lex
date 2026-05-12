# lex-pydantic — command-line codegen
#
# Read a JSON Schema file from disk, build a `Validator`, emit
# downstream artifacts to stdout. Acts as a thin shim so the
# library is usable from a Makefile / CI pipeline / git pre-commit
# hook with no Lex knowledge required at the calling end.
#
# Usage:
#
#   $ cat > user.json <<EOF
#   {
#     "title": "User",
#     "type": "object",
#     "properties": {
#       "name":  {"type":"string","minLength":1,"maxLength":80},
#       "email": {"type":"string","format":"email"},
#       "age":   {"type":"integer","minimum":13,"maximum":130}
#     },
#     "required": ["name","email","age"]
#   }
#   EOF
#
#   $ lex run --allow-effects io --allow-fs-read user.json \
#       examples/18_cli_codegen.lex emit_typescript '"user.json"'
#   # → export interface User { ... }
#
#   $ lex run --allow-effects io --allow-fs-read user.json \
#       examples/18_cli_codegen.lex emit_python '"user.json"'
#   # → class User(BaseModel): ...
#
#   $ lex run --allow-effects io --allow-fs-read user.json \
#       examples/18_cli_codegen.lex emit_summary '"user.json"'
#   # → Validator{title="User", fields=3}
#
# Validation also works the same shape:
#
#   $ lex run --allow-effects io --allow-fs-read schema.json --allow-fs-read body.json \
#       examples/18_cli_codegen.lex validate_file '"schema.json"' '"body.json"'
#
# Effects: [io] for `io.read`; nothing else.

import "std.io"   as io
import "std.str"  as str
import "std.list" as list

import "../src/error"         as e
import "../src/json_value"    as jv
import "../src/schema"        as s
import "../src/schema_import" as si
import "../src/validator"     as v

# ---- File-level glue ---------------------------------------------

# Load a Validator off a JSON Schema file path. Returns a flat
# `Result[Validator, List[Error]]` so the caller can pipeline.
fn load_validator(path :: Str) -> [io] Result[v.Validator, List[e.Error]] {
  match io.read(path) {
    Err(m) => Err(e.single(path, "io_read", m)),
    Ok(text) => match si.from_str(text) {
      Err(es) => Err(es),
      Ok(schema) => Ok(v.make(schema)),
    },
  }
}

# ---- Subcommand entry points -------------------------------------
# Each takes the schema path and returns a Str ready to print.

fn emit_typescript(path :: Str) -> [io] Str {
  match load_validator(path) {
    Err(es) => e.format(es),
    Ok(val) => v.export_typescript(val),
  }
}

fn emit_python(path :: Str) -> [io] Str {
  match load_validator(path) {
    Err(es) => e.format(es),
    Ok(val) => v.export_python(val),
  }
}

fn emit_json_schema(path :: Str) -> [io] Str {
  match load_validator(path) {
    Err(es) => e.format(es),
    Ok(val) => v.export_json_schema_str(val),
  }
}

fn emit_openapi(path :: Str) -> [io] Str {
  match load_validator(path) {
    Err(es) => e.format(es),
    Ok(val) => v.export_openapi_str(val),
  }
}

fn emit_summary(path :: Str) -> [io] Str {
  match load_validator(path) {
    Err(es) => e.format(es),
    Ok(val) => v.summary(val),
  }
}

# ---- Validate a payload file against a schema file ---------------

fn validate_file(schema_path :: Str, body_path :: Str) -> [io] Str {
  match load_validator(schema_path) {
    Err(es) => e.format(es),
    Ok(val) => match io.read(body_path) {
      Err(m) => str.concat("io_read: ", m),
      Ok(body_text) => match v.validate_str(val, body_text) {
        Ok(j)   => str.concat("ok: ", jv.stringify(j)),
        Err(es) => e.format(es),
      },
    },
  }
}
