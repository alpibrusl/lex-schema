# lex-pydantic — SDK code generation
#
# Walk a `ModelSchema` and emit type definitions for downstream
# languages. The output is plain `Str` text the caller can write
# to a file, drop into a build pipeline, or commit alongside the
# Lex source.
#
# Two backends today:
#
#   to_typescript(schema) — emits a TypeScript `export interface`
#     (or a `type` alias for variants of arrays). JSDoc carries
#     each field's `description`. Constraint metadata is left in
#     comments; runtime validation is the user's choice (zod, ajv,
#     manual checks, …).
#
#   to_python(schema) — emits a pydantic v2 `BaseModel`. Constraints
#     map to pydantic field args (`min_length`, `pattern`, `ge`/`le`,
#     `Literal[...]`). The output is drop-in pydantic source —
#     `from pydantic import BaseModel, Field` and you're done.
#
# Two more (Rust struct, Go struct) are a follow-up — same shape,
# different leaves. Adding one is ~40 lines.
#
# Effects: none.

import "std.str"   as str
import "std.int"   as int
import "std.float" as float
import "std.list"  as list

import "./constraints" as c
import "./schema"      as s

# ============================================================
# TypeScript
# ============================================================
#
# Emits a single top-level `interface` plus any nested-record
# interfaces it transitively references. Recursive references are
# resolved by name; the user gets one `.ts` block they can paste
# verbatim into a project.

fn to_typescript(schema :: s.ModelSchema) -> Str {
  let nested := collect_nested(schema)
  let head := ts_interface(schema)
  let rest := list.map(nested, fn (m :: s.ModelSchema) -> Str { ts_interface(m) })
  str.join(list.concat([head], rest), "\n\n")
}

fn ts_interface(schema :: s.ModelSchema) -> Str {
  let header := if str.is_empty(schema.description) {
    str.concat("export interface ", str.concat(schema.title, " {"))
  } else {
    str.concat("/** ", str.concat(schema.description,
      str.concat(" */\nexport interface ", str.concat(schema.title, " {"))))
  }
  let body := list.fold(schema.fields, "",
    fn (acc :: Str, field :: s.Field) -> Str {
      str.concat(acc, str.concat("\n", ts_field_line(field)))
    })
  str.concat(header, str.concat(body, "\n}"))
}

fn ts_field_line(field :: s.Field) -> Str {
  let doc := if str.is_empty(field.description) { "" }
    else {
      str.concat("  /** ", str.concat(field.description, " */\n"))
    }
  let opt := if field.required { "" } else { "?" }
  let ty := ts_type(field.kind)
  let constraint_hint := ts_constraint_hint(field.kind)
  let main := str.concat("  ", str.concat(field.name,
    str.concat(opt, str.concat(": ", str.concat(ty, ";")))))
  if str.is_empty(constraint_hint) {
    str.concat(doc, main)
  } else {
    str.concat(doc, str.concat(main, str.concat("  // ", constraint_hint)))
  }
}

fn ts_type(kind :: s.FieldKind) -> Str {
  match kind {
    KStr(checks)   => match ts_enum_str(checks) {
      Some(union) => union,
      None        => "string",
    },
    KInt(checks)   => match ts_enum_int(checks) {
      Some(union) => union,
      None        => "number",
    },
    KFloat(_)      => "number",
    KBool          => "boolean",
    KArray(elem,_) => str.concat(ts_type(elem), "[]"),
    KObject(sub)   => sub.title,
  }
}

# `StrOneOf(["a","b"])` → `"a" | "b"`. Nicer than `string`
# when the schema knows the closed set.
fn ts_enum_str(checks :: List[c.StrCheck]) -> Option[Str] {
  let opts := list.fold(checks, [],
    fn (acc :: List[Str], chk :: c.StrCheck) -> List[Str] {
      match chk {
        StrOneOf(opts) => if list.is_empty(acc) { opts } else { acc },
        _ => acc,
      }
    })
  if list.is_empty(opts) { None }
  else {
    let quoted := list.map(opts, fn (s :: Str) -> Str {
      str.concat("\"", str.concat(s, "\""))
    })
    Some(str.join(quoted, " | "))
  }
}

fn ts_enum_int(checks :: List[c.IntCheck]) -> Option[Str] {
  let opts := list.fold(checks, [],
    fn (acc :: List[Int], chk :: c.IntCheck) -> List[Int] {
      match chk {
        IntOneOf(opts) => if list.is_empty(acc) { opts } else { acc },
        _ => acc,
      }
    })
  if list.is_empty(opts) { None }
  else {
    Some(str.join(list.map(opts, fn (n :: Int) -> Str { int.to_str(n) }), " | "))
  }
}

# Inline `// minLength: 1, maxLength: 80` style hint. Helpful in
# editors that don't render the JSDoc.
fn ts_constraint_hint(kind :: s.FieldKind) -> Str {
  match kind {
    KStr(checks)   => str_hint(checks),
    KInt(checks)   => int_hint(checks),
    KFloat(checks) => float_hint(checks),
    _              => "",
  }
}

fn str_hint(checks :: List[c.StrCheck]) -> Str {
  let parts := list.fold(checks, [],
    fn (acc :: List[Str], chk :: c.StrCheck) -> List[Str] {
      match str_hint_one(chk) {
        Some(s) => list.concat(acc, [s]),
        None    => acc,
      }
    })
  str.join(parts, ", ")
}

fn str_hint_one(chk :: c.StrCheck) -> Option[Str] {
  match chk {
    StrMinLen(n)   => Some(str.concat("minLength: ", int.to_str(n))),
    StrMaxLen(n)   => Some(str.concat("maxLength: ", int.to_str(n))),
    StrPattern(p)  => Some(str.concat("pattern: ", p)),
    StrEmail       => Some("format: email"),
    StrUrl         => Some("format: uri"),
    StrUuid        => Some("format: uuid"),
    StrNonEmpty    => Some("minLength: 1"),
    _              => None,
  }
}

fn int_hint(checks :: List[c.IntCheck]) -> Str {
  let parts := list.fold(checks, [],
    fn (acc :: List[Str], chk :: c.IntCheck) -> List[Str] {
      match int_hint_one(chk) {
        Some(s) => list.concat(acc, [s]),
        None    => acc,
      }
    })
  str.join(parts, ", ")
}

fn int_hint_one(chk :: c.IntCheck) -> Option[Str] {
  match chk {
    IntMin(n)        => Some(str.concat("min: ", int.to_str(n))),
    IntMax(n)        => Some(str.concat("max: ", int.to_str(n))),
    IntInRange(a, b) => Some(str.concat("min: ", str.concat(int.to_str(a),
                              str.concat(", max: ", int.to_str(b))))),
    IntPositive      => Some("> 0"),
    IntNonNegative   => Some(">= 0"),
    _                => None,
  }
}

fn float_hint(checks :: List[c.FloatCheck]) -> Str {
  let parts := list.fold(checks, [],
    fn (acc :: List[Str], chk :: c.FloatCheck) -> List[Str] {
      match float_hint_one(chk) {
        Some(s) => list.concat(acc, [s]),
        None    => acc,
      }
    })
  str.join(parts, ", ")
}

fn float_hint_one(chk :: c.FloatCheck) -> Option[Str] {
  match chk {
    FloatMin(x)        => Some(str.concat("min: ", float.to_str(x))),
    FloatMax(x)        => Some(str.concat("max: ", float.to_str(x))),
    FloatInRange(a, b) => Some(str.concat("min: ", str.concat(float.to_str(a),
                              str.concat(", max: ", float.to_str(b))))),
    FloatPositive      => Some("> 0"),
    FloatNonNegative   => Some(">= 0"),
    _                  => None,
  }
}

# ============================================================
# Python (pydantic v2)
# ============================================================
#
# Emits a `BaseModel` per schema. Constraints become pydantic
# field arguments; the result is plain Python that pydantic v2
# accepts without modification:
#
#   from pydantic import BaseModel, Field
#   from typing  import Optional, Literal
#
#   class User(BaseModel):
#       name: str = Field(min_length=1, max_length=80)
#       email: str = Field(pattern=r"^[a-zA-Z0-9._%+-]+@…")
#       age: int = Field(ge=13, le=130)
#       nickname: Optional[str] = Field(default=None, max_length=40)

fn to_python(schema :: s.ModelSchema) -> Str {
  let nested := collect_nested(schema)
  let head := py_class(schema)
  let rest := list.map(nested, fn (m :: s.ModelSchema) -> Str { py_class(m) })
  # Nested classes come first so the top-level class can reference
  # them by name without forward declarations.
  let blocks := list.concat(rest, [head])
  let body := str.join(blocks, "\n\n\n")
  str.concat(py_header(), str.concat("\n\n", body))
}

fn py_header() -> Str {
  "from pydantic import BaseModel, Field\nfrom typing  import Optional, List, Literal"
}

fn py_class(schema :: s.ModelSchema) -> Str {
  let docstr := if str.is_empty(schema.description) { "" }
    else {
      str.concat("    \"\"\"", str.concat(schema.description, "\"\"\"\n"))
    }
  let fields := list.fold(schema.fields, "",
    fn (acc :: Str, field :: s.Field) -> Str {
      str.concat(acc, str.concat("\n", py_field_line(field)))
    })
  str.concat("class ", str.concat(schema.title,
    str.concat("(BaseModel):\n", str.concat(docstr,
      if str.is_empty(fields) { "    pass" } else { fields }))))
}

fn py_field_line(field :: s.Field) -> Str {
  let ty := py_type(field.kind)
  let ty_wrapped := if field.required { ty }
    else { str.concat("Optional[", str.concat(ty, "]")) }
  let args := py_field_args(field)
  str.concat("    ", str.concat(field.name,
    str.concat(": ", str.concat(ty_wrapped,
      if str.is_empty(args) {
        if field.required { "" } else { " = None" }
      } else {
        str.concat(" = Field(", str.concat(args, ")"))
      }))))
}

fn py_type(kind :: s.FieldKind) -> Str {
  match kind {
    KStr(checks)   => match py_literal_str(checks) {
      Some(lit) => lit,
      None      => "str",
    },
    KInt(checks)   => match py_literal_int(checks) {
      Some(lit) => lit,
      None      => "int",
    },
    KFloat(_)      => "float",
    KBool          => "bool",
    KArray(elem,_) => str.concat("List[", str.concat(py_type(elem), "]")),
    KObject(sub)   => sub.title,
  }
}

fn py_literal_str(checks :: List[c.StrCheck]) -> Option[Str] {
  let opts := list.fold(checks, [],
    fn (acc :: List[Str], chk :: c.StrCheck) -> List[Str] {
      match chk {
        StrOneOf(opts) => if list.is_empty(acc) { opts } else { acc },
        _ => acc,
      }
    })
  if list.is_empty(opts) { None }
  else {
    let quoted := list.map(opts, fn (s :: Str) -> Str {
      str.concat("\"", str.concat(s, "\""))
    })
    Some(str.concat("Literal[", str.concat(str.join(quoted, ", "), "]")))
  }
}

fn py_literal_int(checks :: List[c.IntCheck]) -> Option[Str] {
  let opts := list.fold(checks, [],
    fn (acc :: List[Int], chk :: c.IntCheck) -> List[Int] {
      match chk {
        IntOneOf(opts) => if list.is_empty(acc) { opts } else { acc },
        _ => acc,
      }
    })
  if list.is_empty(opts) { None }
  else {
    Some(str.concat("Literal[",
      str.concat(str.join(list.map(opts, fn (n :: Int) -> Str {
        int.to_str(n)
      }), ", "), "]")))
  }
}

fn py_field_args(field :: s.Field) -> Str {
  let kind_args := match field.kind {
    KStr(checks)   => py_str_args(checks),
    KInt(checks)   => py_int_args(checks),
    KFloat(checks) => py_float_args(checks),
    KArray(_, shape) => py_list_args(shape),
    _              => "",
  }
  let desc_arg := if str.is_empty(field.description) { "" }
    else {
      str.concat("description=\"", str.concat(field.description, "\""))
    }
  let parts := list.fold([kind_args, desc_arg], [],
    fn (acc :: List[Str], part :: Str) -> List[Str] {
      if str.is_empty(part) { acc } else { list.concat(acc, [part]) }
    })
  str.join(parts, ", ")
}

fn py_str_args(checks :: List[c.StrCheck]) -> Str {
  let parts := list.fold(checks, [],
    fn (acc :: List[Str], chk :: c.StrCheck) -> List[Str] {
      match py_str_arg_one(chk) {
        Some(s) => list.concat(acc, [s]),
        None    => acc,
      }
    })
  str.join(parts, ", ")
}

fn py_str_arg_one(chk :: c.StrCheck) -> Option[Str] {
  match chk {
    StrMinLen(n)   => Some(str.concat("min_length=", int.to_str(n))),
    StrMaxLen(n)   => Some(str.concat("max_length=", int.to_str(n))),
    StrPattern(p)  => Some(str.concat("pattern=r\"", str.concat(p, "\""))),
    StrNonEmpty    => Some("min_length=1"),
    _              => None,
  }
}

fn py_int_args(checks :: List[c.IntCheck]) -> Str {
  let parts := list.fold(checks, [],
    fn (acc :: List[Str], chk :: c.IntCheck) -> List[Str] {
      match py_int_arg_one(chk) {
        Some(s) => list.concat(acc, [s]),
        None    => acc,
      }
    })
  str.join(parts, ", ")
}

fn py_int_arg_one(chk :: c.IntCheck) -> Option[Str] {
  match chk {
    IntMin(n)         => Some(str.concat("ge=", int.to_str(n))),
    IntMax(n)         => Some(str.concat("le=", int.to_str(n))),
    IntInRange(a, b)  => Some(str.concat("ge=",
      str.concat(int.to_str(a), str.concat(", le=", int.to_str(b))))),
    IntPositive       => Some("gt=0"),
    IntNonNegative    => Some("ge=0"),
    _                 => None,
  }
}

fn py_float_args(checks :: List[c.FloatCheck]) -> Str {
  let parts := list.fold(checks, [],
    fn (acc :: List[Str], chk :: c.FloatCheck) -> List[Str] {
      match py_float_arg_one(chk) {
        Some(s) => list.concat(acc, [s]),
        None    => acc,
      }
    })
  str.join(parts, ", ")
}

fn py_float_arg_one(chk :: c.FloatCheck) -> Option[Str] {
  match chk {
    FloatMin(x)         => Some(str.concat("ge=", float.to_str(x))),
    FloatMax(x)         => Some(str.concat("le=", float.to_str(x))),
    FloatInRange(a, b)  => Some(str.concat("ge=",
      str.concat(float.to_str(a), str.concat(", le=", float.to_str(b))))),
    FloatPositive       => Some("gt=0.0"),
    FloatNonNegative    => Some("ge=0.0"),
    _                   => None,
  }
}

fn py_list_args(checks :: List[c.ListCheck]) -> Str {
  let parts := list.fold(checks, [],
    fn (acc :: List[Str], chk :: c.ListCheck) -> List[Str] {
      match py_list_arg_one(chk) {
        Some(s) => list.concat(acc, [s]),
        None    => acc,
      }
    })
  str.join(parts, ", ")
}

fn py_list_arg_one(chk :: c.ListCheck) -> Option[Str] {
  match chk {
    ListMinLen(n)   => Some(str.concat("min_length=", int.to_str(n))),
    ListMaxLen(n)   => Some(str.concat("max_length=", int.to_str(n))),
    ListNonEmpty    => Some("min_length=1"),
    _               => None,
  }
}

# ============================================================
# Nested-record discovery
# ============================================================
#
# Walk the schema's field list, collect every `KObject(sub)`
# in pre-order. Used by both backends so nested classes /
# interfaces are emitted alongside the top-level one.

fn collect_nested(schema :: s.ModelSchema) -> List[s.ModelSchema] {
  list.fold(schema.fields, [],
    fn (acc :: List[s.ModelSchema], field :: s.Field) -> List[s.ModelSchema] {
      list.concat(acc, kind_nested(field.kind))
    })
}

fn kind_nested(kind :: s.FieldKind) -> List[s.ModelSchema] {
  match kind {
    KObject(sub)   => list.concat([sub], collect_nested(sub)),
    KArray(elem,_) => kind_nested(elem),
    _              => [],
  }
}
