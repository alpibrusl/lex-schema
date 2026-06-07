# Tests for `src/form.lex` multipart/form-data parsing.
#
# Each fixture is the literal HTTP body a browser would send, with
# CRLF line terminators (`\r\n`). The boundary is whatever the
# `Content-Type` header advertised; here we hard-code "B".

import "std.list" as list

import "std.str" as str

import "std.map" as map

import "../src/error" as e

import "../src/form" as form

fn b() -> Str {
  "B"
}

# ---- Simple text-only part --------------------------------------
fn body_one_text() -> Str {
  str.concat("--B\r\n", str.concat("Content-Disposition: form-data; name=\"field\"\r\n\r\n", str.concat("hello\r\n", "--B--\r\n")))
}

fn one_text_parses() -> Result[Unit, Str] {
  match form.decode_multipart(body_one_text(), b()) {
    Err(_) => Err("rejected one_text"),
    Ok(parts) => if list.len(parts) == 1 {
      Ok(())
    } else {
      Err("wrong part count")
    },
  }
}

fn one_text_body() -> Result[Unit, Str] {
  match form.decode_multipart(body_one_text(), b()) {
    Err(_) => Err("rejected"),
    Ok(parts) => match list.head(parts) {
      None => Err("no head"),
      Some(p) => if p.body == "hello" {
        Ok(())
      } else {
        Err(str.concat("body was: ", p.body))
      },
    },
  }
}

fn one_text_name() -> Result[Unit, Str] {
  match form.decode_multipart(body_one_text(), b()) {
    Err(_) => Err("rejected"),
    Ok(parts) => match list.head(parts) {
      None => Err("no head"),
      Some(p) => if p.name == "field" {
        Ok(())
      } else {
        Err(str.concat("name was: ", p.name))
      },
    },
  }
}

# Text fields without an explicit Content-Type default to text/plain.
fn one_text_default_ct() -> Result[Unit, Str] {
  match form.decode_multipart(body_one_text(), b()) {
    Err(_) => Err("rejected"),
    Ok(parts) => match list.head(parts) {
      None => Err("no head"),
      Some(p) => if p.content_type == "text/plain" {
        Ok(())
      } else {
        Err(str.concat("ct: ", p.content_type))
      },
    },
  }
}

# ---- File part with filename + content-type ---------------------
fn body_file_upload() -> Str {
  str.concat("--B\r\n", str.concat("Content-Disposition: form-data; name=\"upload\"; filename=\"notes.txt\"\r\n", str.concat("Content-Type: text/markdown\r\n\r\n", str.concat("# title\nline1\nline2\r\n", "--B--\r\n"))))
}

fn file_filename() -> Result[Unit, Str] {
  match form.decode_multipart(body_file_upload(), b()) {
    Err(_) => Err("rejected file"),
    Ok(parts) => match list.head(parts) {
      None => Err("no head"),
      Some(p) => match p.filename {
        None => Err("filename missing"),
        Some(f) => if f == "notes.txt" {
          Ok(())
        } else {
          Err(str.concat("filename was: ", f))
        },
      },
    },
  }
}

fn file_content_type() -> Result[Unit, Str] {
  match form.decode_multipart(body_file_upload(), b()) {
    Err(_) => Err("rejected"),
    Ok(parts) => match list.head(parts) {
      None => Err("no head"),
      Some(p) => if p.content_type == "text/markdown" {
        Ok(())
      } else {
        Err(str.concat("ct: ", p.content_type))
      },
    },
  }
}

fn file_body_preserved() -> Result[Unit, Str] {
  match form.decode_multipart(body_file_upload(), b()) {
    Err(_) => Err("rejected"),
    Ok(parts) => match list.head(parts) {
      None => Err("no head"),
      Some(p) => if str.contains(p.body, "# title") and str.contains(p.body, "line2") {
        Ok(())
      } else {
        Err(str.concat("body: ", p.body))
      },
    },
  }
}

# ---- Mixed parts ------------------------------------------------
fn body_mixed() -> Str {
  str.concat("--B\r\n", str.concat("Content-Disposition: form-data; name=\"user\"\r\n\r\n", str.concat("alice\r\n", str.concat("--B\r\n", str.concat("Content-Disposition: form-data; name=\"avatar\"; filename=\"a.png\"\r\n", str.concat("Content-Type: image/png\r\n\r\n", str.concat("PNGDATA\r\n", str.concat("--B\r\n", str.concat("Content-Disposition: form-data; name=\"remember\"\r\n\r\n", str.concat("true\r\n", "--B--\r\n"))))))))))
}

fn mixed_count() -> Result[Unit, Str] {
  match form.decode_multipart(body_mixed(), b()) {
    Err(_) => Err("rejected"),
    Ok(parts) => if list.len(parts) == 3 {
      Ok(())
    } else {
      Err("wrong count")
    },
  }
}

fn mixed_ordering() -> Result[Unit, Str] {
  match form.decode_multipart(body_mixed(), b()) {
    Err(_) => Err("rejected"),
    Ok(parts) => {
      let names := list.map(parts, fn (p :: form.MultipartPart) -> Str {
        p.name
      })
      let joined := str.join(names, ",")
      if joined == "user,avatar,remember" {
        Ok(())
      } else {
        Err(str.concat("got: ", joined))
      }
    },
  }
}

fn mixed_avatar_body() -> Result[Unit, Str] {
  match form.decode_multipart(body_mixed(), b()) {
    Err(_) => Err("rejected"),
    Ok(parts) => match list.head(list.tail(parts)) {
      None => Err("no 2nd part"),
      Some(p) => if p.body == "PNGDATA" and p.content_type == "image/png" {
        Ok(())
      } else {
        Err(str.concat("body: ", p.body))
      },
    },
  }
}

# ---- Body containing CRLFCRLF (blank line) ----------------------
fn body_with_blank_line() -> Str {
  str.concat("--B\r\n", str.concat("Content-Disposition: form-data; name=\"essay\"\r\n\r\n", str.concat("paragraph one\r\n\r\nparagraph two\r\n", "--B--\r\n")))
}

fn blank_line_in_body() -> Result[Unit, Str] {
  match form.decode_multipart(body_with_blank_line(), b()) {
    Err(_) => Err("rejected"),
    Ok(parts) => match list.head(parts) {
      None => Err("no head"),
      Some(p) => if str.contains(p.body, "paragraph one") and str.contains(p.body, "paragraph two") {
        Ok(())
      } else {
        Err(str.concat("body: ", p.body))
      },
    },
  }
}

# ---- Malformed inputs -------------------------------------------
fn missing_closing_boundary() -> Result[Unit, Str] {
  let body := str.concat("--B\r\n", str.concat("Content-Disposition: form-data; name=\"x\"\r\n\r\n", "value\r\n"))
  match form.decode_multipart(body, b()) {
    Ok(_) => Err("should reject (no closing)"),
    Err(es) => match list.head(es) {
      None => Err("empty errors"),
      Some(_) => Ok(()),
    },
  }
}

fn missing_name() -> Result[Unit, Str] {
  let body := str.concat("--B\r\n", str.concat("Content-Type: text/plain\r\n\r\n", str.concat("body\r\n", "--B--\r\n")))
  match form.decode_multipart(body, b()) {
    Ok(_) => Err("should reject (no name)"),
    Err(_) => Ok(()),
  }
}

fn wrong_boundary() -> Result[Unit, Str] {
  match form.decode_multipart(body_one_text(), "OTHER") {
    Ok(_) => Err("should reject"),
    Err(_) => Ok(()),
  }
}

fn empty_boundary() -> Result[Unit, Str] {
  match form.decode_multipart(body_one_text(), "") {
    Ok(_) => Err("should reject empty boundary"),
    Err(_) => Ok(()),
  }
}

# ---- decode_body dispatch ---------------------------------------
fn dispatch_multipart_ok() -> Result[Unit, Str] {
  let ct := "multipart/form-data; boundary=B"
  match form.decode_body(body_one_text(), ct) {
    Err(_) => Err("rejected"),
    Ok(m) => match map.get(m, "field") {
      Some("hello") => Ok(()),
      Some(other) => Err(str.concat("got: ", other)),
      None => Err("field missing"),
    },
  }
}

fn dispatch_multipart_quoted_boundary() -> Result[Unit, Str] {
  let ct := "multipart/form-data; boundary=\"B\""
  match form.decode_body(body_one_text(), ct) {
    Err(_) => Err("rejected quoted boundary"),
    Ok(_) => Ok(()),
  }
}

fn dispatch_multipart_missing_boundary() -> Result[Unit, Str] {
  match form.decode_body(body_one_text(), "multipart/form-data") {
    Ok(_) => Err("should reject"),
    Err(es) => match list.head(es) {
      None => Err("empty"),
      Some(_) => Ok(()),
    },
  }
}

fn dispatch_multipart_flattens_to_map() -> Result[Unit, Str] {
  let ct := "multipart/form-data; boundary=B"
  match form.decode_body(body_mixed(), ct) {
    Err(_) => Err("rejected"),
    Ok(m) => if map.size(m) == 3 {
      Ok(())
    } else {
      Err("map size")
    },
  }
}

# ---- Suite ------------------------------------------------------
fn suite() -> List[Result[Unit, Str]] {
  [one_text_parses(), one_text_body(), one_text_name(), one_text_default_ct(), file_filename(), file_content_type(), file_body_preserved(), mixed_count(), mixed_ordering(), mixed_avatar_body(), blank_line_in_body(), missing_closing_boundary(), missing_name(), wrong_boundary(), empty_boundary(), dispatch_multipart_ok(), dispatch_multipart_quoted_boundary(), dispatch_multipart_missing_boundary(), dispatch_multipart_flattens_to_map()]
}

fn run_all() -> Int {
  list.fold(suite(), 0, fn (acc :: Int, v :: Result[Unit, Str]) -> Int {
    match v {
      Ok(_) => acc,
      Err(_) => acc + 1,
    }
  })
}

