# lex-schema — multipart/form-data upload pipeline
#
# Closes the one functional gap from v0.8.1: file uploads. The
# multipart parser in `src/form.lex` now produces a real
# `List[MultipartPart]` with name + filename + content_type + body,
# and `decode_body` flattens it to a `Map[Str, Str]` so the same
# `coerce.require_*_from_map` pipeline works for both
# `application/x-www-form-urlencoded` and `multipart/form-data`.
#
# Run:
#   lex run examples/22_multipart_upload.lex demo_parse_ok
#   lex run examples/22_multipart_upload.lex demo_part_count
#   lex run examples/22_multipart_upload.lex demo_validate_avatar_ok
#   lex run examples/22_multipart_upload.lex format_validate_avatar_bad

import "std.list" as list

import "std.str" as str

import "../src/error" as e

import "../src/coerce" as coerce

import "../src/combine" as cm

import "../src/form" as form

# ---- Avatar-upload schema -----------------------------------------
type AvatarSubmission = { user_id :: Str, caption :: Str, filename :: Str, content_type :: Str, size :: Int }

# ---- Fixtures (browser-style HTTP body) ---------------------------
fn boundary() -> Str {
  "WebKitFormBoundary7MA4YWxkTrZu0gW"
}

fn content_type_header() -> Str {
  str.concat("multipart/form-data; boundary=", boundary())
}

fn bdry() -> Str {
  str.concat("--", boundary())
}

fn sep() -> Str {
  str.concat(bdry(), "\r\n")
}

fn close() -> Str {
  str.concat(bdry(), "--\r\n")
}

fn sample_body() -> Str {
  str.join([sep(), "Content-Disposition: form-data; name=\"user_id\"\r\n\r\n", "u-42\r\n", sep(), "Content-Disposition: form-data; name=\"caption\"\r\n\r\n", "Working from the coffee shop\r\n", sep(), "Content-Disposition: form-data; name=\"avatar\"; filename=\"selfie.png\"\r\n", "Content-Type: image/png\r\n\r\n", "PNGfakebytes\r\n", close()], "")
}

# ---- Demos --------------------------------------------------------
fn demo_parse_ok() -> Result[List[form.MultipartPart], e.Errors] {
  form.decode_multipart(sample_body(), boundary())
}

fn demo_part_count() -> Int {
  match demo_parse_ok() {
    Err(_) => -1,
    Ok(parts) => list.len(parts),
  }
}

# ---- Validation pipeline ------------------------------------------
fn find_part(parts :: List[form.MultipartPart], name :: Str) -> Option[form.MultipartPart] {
  match list.head(parts) {
    None => None,
    Some(p) => if p.name == name {
      Some(p)
    } else {
      find_part(list.tail(parts), name)
    },
  }
}

fn build_submission(uid :: Str, cap :: Str, fname :: Str, ct :: Str, sz :: Int) -> AvatarSubmission {
  { user_id: uid, caption: cap, filename: fname, content_type: ct, size: sz }
}

# Walk the parts, validate text fields via `coerce.require_str_from_map`
# (the flat-map view), and pull file-part metadata directly off the
# `MultipartPart` record.
fn validate_avatar(parts :: List[form.MultipartPart]) -> Result[AvatarSubmission, e.Errors] {
  match find_part(parts, "avatar") {
    None => Err(e.single("avatar", e.code_missing(), "avatar file part missing")),
    Some(p) => match p.filename {
      None => Err(e.single("avatar", "format", "avatar part must carry a filename")),
      Some(fnm) => {
        let m := form.parts_to_map(parts)
        cm.combine5(coerce.require_str_from_map(m, "user_id", [StrMinLen(1), StrMaxLen(64), StrPattern("^[a-zA-Z0-9_-]+$")]), coerce.require_str_from_map(m, "caption", [StrMaxLen(280)]), Ok(fnm), Ok(p.content_type), Ok(str.len(p.body)), build_submission)
      },
    },
  }
}

fn demo_validate_avatar_ok() -> Result[AvatarSubmission, e.Errors] {
  match demo_parse_ok() {
    Err(es) => Err(es),
    Ok(parts) => validate_avatar(parts),
  }
}

fn demo_validate_avatar_bad() -> Result[AvatarSubmission, e.Errors] {
  let body := str.join([sep(), "Content-Disposition: form-data; name=\"user_id\"\r\n\r\n", "not a valid id!\r\n", sep(), "Content-Disposition: form-data; name=\"caption\"\r\n\r\n", "hi\r\n", sep(), "Content-Disposition: form-data; name=\"avatar\"; filename=\"a.png\"\r\n", "Content-Type: image/png\r\n\r\n", "PNG\r\n", close()], "")
  match form.decode_multipart(body, boundary()) {
    Err(es) => Err(es),
    Ok(parts) => validate_avatar(parts),
  }
}

fn format_validate_avatar_bad() -> Str {
  match demo_validate_avatar_bad() {
    Ok(_) => "(no errors)",
    Err(es) => e.format(es),
  }
}

