# lex-pydantic — JSON Schema → ModelSchema
#
# Reads a JSON Schema document (Draft 2020-12 shape, the same form
# `schema.to_json_schema` emits) and produces a `ModelSchema`.
# The round-trip
#
#   ModelSchema -- to_json_schema -> Json -- stringify
#                                          | parse
#                                          v
#                                          Json -- from_json_schema -> ModelSchema
#
# is structural-equality preserving for the subset of JSON Schema
# we emit (object/string/integer/number/boolean/array/nested-
# object + the constraint catalog). External documents using
# `$ref`, `oneOf`, `allOf`, `const`-only-without-type, etc. fall
# back to a permissive `KStr([])` for unrecognized leaves rather
# than erroring — that keeps the parser useful as a "best effort"
# pass for community schemas without growing the constraint
# catalog beyond what the library can actually enforce.
#
# Effects: none.

import "std.str"   as str
import "std.int"   as int
import "std.list"  as list

import "./error"       as e
import "./constraints" as c
import "./json_value"  as jv
import "./schema"      as s

# ---- Entry points -------------------------------------------------

fn from_json_schema(j :: jv.Json) -> Result[s.ModelSchema, List[e.Error]] {
  parse_model_at("", j)
}

# Convenience: take a serialized JSON document and run the pair
# `jv.parse_into_errors` + `from_json_schema` in one call.
fn from_str(src :: Str) -> Result[s.ModelSchema, List[e.Error]] {
  match jv.parse_into_errors(src) {
    Err(es) => Err(es),
    Ok(j)   => from_json_schema(j),
  }
}

# ---- Recursive walker --------------------------------------------

fn parse_model_at(
  path :: Str,
  j :: jv.Json
) -> Result[s.ModelSchema, List[e.Error]] {
  let title       := str_field_or(j, "title", "")
  let description := str_field_or(j, "description", "")
  let required_set := required_names(j)
  match jv.get_field(j, "properties") {
    None    => Ok(s.mk_model(title, description, [])),
    Some(p) => match jv.as_obj(p) {
      None       => Err(e.single(join_path(path, "properties"),
                                  e.code_type(),
                                  "expected object")),
      Some(entries) => {
        let walked := list.fold(entries, walk_init(),
          fn (
            acc :: (List[s.Field], List[e.Error]),
            pair :: (Str, jv.Json)
          ) -> (List[s.Field], List[e.Error]) {
            let fields := match acc { (f, _) => f }
            let errs   := match acc { (_, e) => e }
            let name := match pair { (n, _) => n }
            let v    := match pair { (_, vv) => vv }
            match parse_field(join_path(path, name), name, v,
                              contains_str(required_set, name)) {
              Ok(field) => (list.concat(fields, [field]), errs),
              Err(es)   => (fields, list.concat(errs, es)),
            }
          })
        let fields := match walked { (f, _) => f }
        let errs   := match walked { (_, e) => e }
        if e.is_ok(errs) {
          Ok(s.mk_model(title, description, fields))
        } else { Err(errs) }
      },
    },
  }
}

fn walk_init() -> (List[s.Field], List[e.Error]) { ([], []) }

fn parse_field(
  path :: Str,
  name :: Str,
  j :: jv.Json,
  required :: Bool
) -> Result[s.Field, List[e.Error]] {
  let desc := str_field_or(j, "description", "")
  match parse_kind(path, j) {
    Err(es)   => Err(es),
    Ok(kind)  => Ok(s.mk_field(name, required, desc, kind)),
  }
}

fn parse_kind(path :: Str, j :: jv.Json) -> Result[s.FieldKind, List[e.Error]] {
  match jv.get_field(j, "type") {
    None    => Ok(KStr([])),     # permissive fallback for $ref / oneOf etc.
    Some(t) => match jv.as_str(t) {
      None    => Err(e.single(join_path(path, "type"),
                              e.code_type(),
                              "expected string for `type`")),
      Some(name) => match name {
        "string"  => Ok(KStr(parse_str_checks(j))),
        "integer" => Ok(KInt(parse_int_checks(j))),
        "number"  => Ok(KFloat(parse_float_checks(j))),
        "boolean" => Ok(KBool),
        "array"   => parse_array_kind(path, j),
        "object"  => match parse_model_at(path, j) {
          Ok(m)   => Ok(KObject(m)),
          Err(es) => Err(es),
        },
        other     => Err(e.single(join_path(path, "type"),
                                  e.code_one_of(),
                                  str.concat("unknown type: ", other))),
      },
    },
  }
}

fn parse_array_kind(
  path :: Str,
  j :: jv.Json
) -> Result[s.FieldKind, List[e.Error]] {
  let shape := parse_list_checks(j)
  match jv.get_field(j, "items") {
    None        => Ok(KArray(KStr([]), shape)),
    Some(items) => match parse_kind(join_path(path, "items"), items) {
      Ok(elem) => Ok(KArray(elem, shape)),
      Err(es)  => Err(es),
    },
  }
}

# ---- Constraint extractors ---------------------------------------

fn parse_str_checks(j :: jv.Json) -> List[c.StrCheck] {
  let from_min := match int_field(j, "minLength") {
    None    => [],
    Some(n) => [StrMinLen(n)],
  }
  let from_max := match int_field(j, "maxLength") {
    None    => [],
    Some(n) => [StrMaxLen(n)],
  }
  let from_pattern := match str_field(j, "pattern") {
    None    => [],
    Some(p) => [StrPattern(p)],
  }
  let from_format := match str_field(j, "format") {
    None    => [],
    Some(f) => match f {
      "email" => [StrEmail],
      "uri"   => [StrUrl],
      "uuid"  => [StrUuid],
      _       => [],
    },
  }
  let from_enum := match jv.get_field(j, "enum") {
    None     => [],
    Some(en) => match jv.as_list(en) {
      None    => [],
      Some(xs) => {
        let strs := list.fold(xs, [], fn (acc :: List[Str], v :: jv.Json) -> List[Str] {
          match jv.as_str(v) {
            Some(s) => list.concat(acc, [s]),
            None    => acc,
          }
        })
        if list.is_empty(strs) { [] } else { [StrOneOf(strs)] }
      },
    },
  }
  list.concat(list.concat(list.concat(list.concat(
    from_min, from_max), from_pattern), from_format), from_enum)
}

fn parse_int_checks(j :: jv.Json) -> List[c.IntCheck] {
  let from_min := match int_field(j, "minimum") {
    None    => [],
    Some(n) => [IntMin(n)],
  }
  let from_max := match int_field(j, "maximum") {
    None    => [],
    Some(n) => [IntMax(n)],
  }
  let from_excl := match int_field(j, "exclusiveMinimum") {
    None    => [],
    Some(n) => if n == 0 { [IntPositive] } else { [IntMin(n + 1)] },
  }
  let from_const := match int_field(j, "const") {
    None    => [],
    Some(n) => [IntEq(n)],
  }
  let from_enum := match jv.get_field(j, "enum") {
    None     => [],
    Some(en) => match jv.as_list(en) {
      None    => [],
      Some(xs) => {
        let ints := list.fold(xs, [], fn (acc :: List[Int], v :: jv.Json) -> List[Int] {
          match jv.as_int(v) {
            Some(n) => list.concat(acc, [n]),
            None    => acc,
          }
        })
        if list.is_empty(ints) { [] } else { [IntOneOf(ints)] }
      },
    },
  }
  list.concat(list.concat(list.concat(list.concat(
    from_min, from_max), from_excl), from_const), from_enum)
}

fn parse_float_checks(j :: jv.Json) -> List[c.FloatCheck] {
  let from_min := match float_field(j, "minimum") {
    None    => [],
    Some(x) => [FloatMin(x)],
  }
  let from_max := match float_field(j, "maximum") {
    None    => [],
    Some(x) => [FloatMax(x)],
  }
  let from_excl := match float_field(j, "exclusiveMinimum") {
    None    => [],
    Some(x) => if x == 0.0 { [FloatPositive] } else { [FloatMin(x)] },
  }
  list.concat(list.concat(from_min, from_max), from_excl)
}

fn parse_list_checks(j :: jv.Json) -> List[c.ListCheck] {
  let from_min := match int_field(j, "minItems") {
    None    => [],
    Some(n) => if n == 1 { [ListNonEmpty] } else { [ListMinLen(n)] },
  }
  let from_max := match int_field(j, "maxItems") {
    None    => [],
    Some(n) => [ListMaxLen(n)],
  }
  list.concat(from_min, from_max)
}

# ---- Small helpers ------------------------------------------------

fn str_field(j :: jv.Json, name :: Str) -> Option[Str] {
  match jv.get_field(j, name) {
    None    => None,
    Some(v) => jv.as_str(v),
  }
}

fn str_field_or(j :: jv.Json, name :: Str, default :: Str) -> Str {
  match str_field(j, name) { Some(s) => s, None => default }
}

fn int_field(j :: jv.Json, name :: Str) -> Option[Int] {
  match jv.get_field(j, name) {
    None    => None,
    Some(v) => jv.as_int(v),
  }
}

fn float_field(j :: jv.Json, name :: Str) -> Option[Float] {
  match jv.get_field(j, name) {
    None    => None,
    Some(v) => jv.as_float(v),
  }
}

fn required_names(j :: jv.Json) -> List[Str] {
  match jv.get_field(j, "required") {
    None    => [],
    Some(v) => match jv.as_list(v) {
      None    => [],
      Some(xs) => list.fold(xs, [], fn (acc :: List[Str], item :: jv.Json) -> List[Str] {
        match jv.as_str(item) {
          Some(s) => list.concat(acc, [s]),
          None    => acc,
        }
      }),
    },
  }
}

fn contains_str(xs :: List[Str], needle :: Str) -> Bool {
  list.fold(xs, false, fn (acc :: Bool, x :: Str) -> Bool {
    acc or (x == needle)
  })
}

fn join_path(prefix :: Str, leaf :: Str) -> Str {
  if str.is_empty(prefix) { leaf }
  else { str.concat(prefix, str.concat(".", leaf)) }
}
