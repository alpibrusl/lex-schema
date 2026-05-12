# lex-schema — HTTP form body decoders
#
# Two formats every API ends up taking:
#
#   1. `application/x-www-form-urlencoded` — `a=1&b=hello%20world`.
#      Legacy browsers, OAuth callbacks, simple POST forms.
#   2. `multipart/form-data` — file uploads + form fields. v1
#      surface deferred; the function stub here returns an Err
#      directing callers to use the upstream body for file uploads.
#
# Both decode into a `Map[Str, Str]` (which `coerce.lex` already
# knows how to walk through `require_*_from_map` /
# `optional_*_from_map`), so the validation pipeline is the same
# regardless of the body's wire format. The shape that lands in
# the handler is uniform.
#
# Effects: none.

import "std.str"  as str
import "std.int"  as int
import "std.list" as list
import "std.map"  as map

import "./error" as e

# ---- x-www-form-urlencoded ---------------------------------------

# Decode a `?a=1&b=hello%20world` body into a `Map[Str, Str]`.
# Empty body returns an empty map. Malformed pairs (`a` with no
# `=`) bind the key to the empty string — matching how
# `URLSearchParams` in JS / `urllib.parse_qs` in Python behave.
fn decode_urlencoded(body :: Str) -> Map[Str, Str] {
  if str.is_empty(body) { map.new() }
  else {
    let pairs := list.map(str.split(body, "&"),
      fn (kv :: Str) -> (Str, Str) { split_pair(kv) })
    map.from_list(pairs)
  }
}

# Decode one `key=value` segment. URL-unescapes both sides. A
# bare `key` (no `=`) binds to the empty string.
fn split_pair(kv :: Str) -> (Str, Str) {
  match find_eq(kv, 0) {
    None     => (url_decode(kv), ""),
    Some(i)  => (url_decode(str.slice(kv, 0, i)),
                 url_decode(str.slice(kv, i + 1, str.len(kv)))),
  }
}

fn find_eq(s :: Str, i :: Int) -> Option[Int] {
  if i >= str.len(s) { None }
  else {
    if str.slice(s, i, i + 1) == "=" { Some(i) }
    else { find_eq(s, i + 1) }
  }
}

# ---- URL decoding ------------------------------------------------

# Replace `+` with space and `%XX` with the byte XX. Unicode
# decoding follows from the byte sequence — UTF-8 sequences
# round-trip unchanged. Malformed `%` escapes pass through
# literally (defensive — matches Node's `querystring.unescape`
# behavior).
fn url_decode(s :: Str) -> Str { url_decode_at(s, 0, "") }

fn url_decode_at(s :: Str, i :: Int, acc :: Str) -> Str {
  let n := str.len(s)
  if i >= n { acc }
  else {
    let c := str.slice(s, i, i + 1)
    if c == "+" {
      url_decode_at(s, i + 1, str.concat(acc, " "))
    } else {
      if c == "%" and i + 2 < n {
        let hex := str.slice(s, i + 1, i + 3)
        match hex_byte(hex) {
          Some(b) => url_decode_at(s, i + 3, str.concat(acc, b)),
          None    => url_decode_at(s, i + 1, str.concat(acc, c)),
        }
      } else {
        url_decode_at(s, i + 1, str.concat(acc, c))
      }
    }
  }
}

# Convert a two-char hex string to its single-byte string form.
# Returns None on non-hex input. Uses a 256-entry table built
# from the ASCII range — fast enough for HTTP form decoding.
fn hex_byte(h :: Str) -> Option[Str] {
  let hi := hex_digit(str.slice(h, 0, 1))
  let lo := hex_digit(str.slice(h, 1, 2))
  match hi {
    None      => None,
    Some(hv)  => match lo {
      None      => None,
      Some(lv)  => Some(byte_to_char(hv * 16 + lv)),
    },
  }
}

fn hex_digit(c :: Str) -> Option[Int] {
  match c {
    "0" => Some(0),  "1" => Some(1),  "2" => Some(2),  "3" => Some(3),
    "4" => Some(4),  "5" => Some(5),  "6" => Some(6),  "7" => Some(7),
    "8" => Some(8),  "9" => Some(9),
    "a" => Some(10), "b" => Some(11), "c" => Some(12), "d" => Some(13),
    "e" => Some(14), "f" => Some(15),
    "A" => Some(10), "B" => Some(11), "C" => Some(12), "D" => Some(13),
    "E" => Some(14), "F" => Some(15),
    _   => None,
  }
}

# Byte value (0-255) to a single-char `Str`. Implemented as a
# match against the printable ASCII range plus the common
# whitespace bytes; bytes outside that range pass back as
# `%XX`-encoded so the round-trip is information-preserving even
# without a `Char.from_code` primitive (which lex doesn't have).
fn byte_to_char(b :: Int) -> Str {
  match b {
    32 => " ",  33 => "!",  34 => "\"", 35 => "#",  36 => "$",
    37 => "%",  38 => "&",  39 => "'",  40 => "(",  41 => ")",
    42 => "*",  43 => "+",  44 => ",",  45 => "-",  46 => ".",
    47 => "/",
    48 => "0",  49 => "1",  50 => "2",  51 => "3",  52 => "4",
    53 => "5",  54 => "6",  55 => "7",  56 => "8",  57 => "9",
    58 => ":",  59 => ";",  60 => "<",  61 => "=",  62 => ">",
    63 => "?",  64 => "@",
    65 => "A",  66 => "B",  67 => "C",  68 => "D",  69 => "E",
    70 => "F",  71 => "G",  72 => "H",  73 => "I",  74 => "J",
    75 => "K",  76 => "L",  77 => "M",  78 => "N",  79 => "O",
    80 => "P",  81 => "Q",  82 => "R",  83 => "S",  84 => "T",
    85 => "U",  86 => "V",  87 => "W",  88 => "X",  89 => "Y",
    90 => "Z",
    91 => "[",  92 => "\\", 93 => "]",  94 => "^",  95 => "_",
    96 => "`",
    97 => "a",  98 => "b",  99 => "c",  100 => "d", 101 => "e",
    102 => "f", 103 => "g", 104 => "h", 105 => "i", 106 => "j",
    107 => "k", 108 => "l", 109 => "m", 110 => "n", 111 => "o",
    112 => "p", 113 => "q", 114 => "r", 115 => "s", 116 => "t",
    117 => "u", 118 => "v", 119 => "w", 120 => "x", 121 => "y",
    122 => "z",
    123 => "{", 124 => "|", 125 => "}", 126 => "~",
    10  => "\n", 9 => "\t", 13 => "\r",
    _   => fallback_pct(b),
  }
}

# For bytes lex can't materialize as a single-char Str, preserve
# the `%XX` form. Better lossy than silently corrupting.
fn fallback_pct(b :: Int) -> Str {
  let hi := b / 16
  let lo := b % 16
  str.concat("%", str.concat(hex_char(hi), hex_char(lo)))
}

fn hex_char(n :: Int) -> Str {
  match n {
    0 => "0", 1 => "1", 2 => "2", 3 => "3",
    4 => "4", 5 => "5", 6 => "6", 7 => "7",
    8 => "8", 9 => "9",
    10 => "A", 11 => "B", 12 => "C", 13 => "D",
    14 => "E", 15 => "F",
    _  => "?",
  }
}

# ---- multipart/form-data -----------------------------------------
#
# RFC 7578 (RFC 2046) multipart body shape:
#
#   --BOUNDARY\r\n
#   Content-Disposition: form-data; name="field"\r\n
#   \r\n
#   value\r\n
#   --BOUNDARY\r\n
#   Content-Disposition: form-data; name="upload"; filename="x.txt"\r\n
#   Content-Type: text/plain\r\n
#   \r\n
#   <part body>\r\n
#   --BOUNDARY--\r\n
#
# We split the body on `--BOUNDARY`, which gives:
#   [preamble, part_1, part_2, ..., part_N, closing_trailer]
# Each `part_k` reads `\r\n<headers>\r\n\r\n<body>\r\n`. The
# trailer starts with `--` followed by optional CRLF + epilogue.

type MultipartPart = {
  name :: Str,
  filename :: Option[Str],
  content_type :: Str,
  body :: Str,
}

# Accumulator while folding header lines.
type PartHeaders = {
  name :: Option[Str],
  filename :: Option[Str],
  content_type :: Option[Str],
}

fn mk_hdrs() -> PartHeaders {
  { name: None, filename: None, content_type: None }
}

fn decode_multipart(
  body :: Str,
  boundary :: Str
) -> Result[List[MultipartPart], e.Errors] {
  if str.is_empty(boundary) {
    Err(e.single("", "format", "empty multipart boundary"))
  } else {
    let delim := str.concat("--", boundary)
    let pieces := str.split(body, delim)
    if list.len(pieces) < 2 {
      Err(e.single("", "format",
        str.concat("no multipart boundary found: ", boundary)))
    } else {
      let trailer := last_piece(pieces)
      if str.starts_with(trailer, "--") {
        walk_middle(middle_pieces(pieces), 0, [])
      } else {
        Err(e.single("", "format",
          "multipart missing closing boundary (--BOUNDARY--)"))
      }
    }
  }
}

fn last_piece(xs :: List[Str]) -> Str {
  match list.head(list.reverse(xs)) {
    Some(s) => s,
    None    => "",
  }
}

# pieces[1 .. n-1) — drop preamble and closing trailer.
fn middle_pieces(xs :: List[Str]) -> List[Str] {
  list.reverse(list.tail(list.reverse(list.tail(xs))))
}

fn walk_middle(
  ps :: List[Str],
  idx :: Int,
  acc :: List[MultipartPart]
) -> Result[List[MultipartPart], e.Errors] {
  match list.head(ps) {
    None        => Ok(list.reverse(acc)),
    Some(piece) => match parse_one_part(piece, idx) {
      Err(es) => Err(es),
      Ok(p)   => walk_middle(list.tail(ps), idx + 1, list.cons(p, acc)),
    },
  }
}

fn parse_one_part(
  piece :: Str,
  idx :: Int
) -> Result[MultipartPart, e.Errors] {
  let p1 := strip_leading_crlf(piece)
  let chunks := str.split(p1, "\r\n\r\n")
  if list.len(chunks) < 2 {
    Err(e.single(part_path(idx), "format",
      "missing CRLFCRLF header/body separator"))
  } else {
    match list.head(chunks) {
      None              => Err(e.single(part_path(idx), "format", "empty part")),
      Some(headers_str) => {
        let body_raw   := str.join(list.tail(chunks), "\r\n\r\n")
        let body_clean := strip_trailing_crlf(body_raw)
        parse_part_headers(headers_str, body_clean, idx)
      },
    }
  }
}

fn strip_leading_crlf(s :: Str) -> Str {
  match str.strip_prefix(s, "\r\n") {
    Some(t) => t,
    None    => s,
  }
}

fn strip_trailing_crlf(s :: Str) -> Str {
  match str.strip_suffix(s, "\r\n") {
    Some(t) => t,
    None    => s,
  }
}

fn part_path(idx :: Int) -> Str {
  str.concat("parts[", str.concat(int.to_str(idx), "]"))
}

fn parse_part_headers(
  headers_str :: Str,
  body :: Str,
  idx :: Int
) -> Result[MultipartPart, e.Errors] {
  let lines := str.split(headers_str, "\r\n")
  let h := list.fold(lines, mk_hdrs(),
    fn (acc :: PartHeaders, line :: Str) -> PartHeaders {
      parse_header_line(acc, line)
    })
  match h.name {
    None    => Err(e.single(part_path(idx), "format",
      "Content-Disposition name missing")),
    Some(n) => Ok({
      name: n,
      filename: h.filename,
      content_type: match h.content_type {
        Some(ct) => ct,
        None     => default_part_ct(h.filename),
      },
      body: body,
    }),
  }
}

# Default per RFC 7578 §4.4: file fields default to
# application/octet-stream; text fields default to text/plain.
fn default_part_ct(filename :: Option[Str]) -> Str {
  match filename {
    Some(_) => "application/octet-stream",
    None    => "text/plain",
  }
}

fn parse_header_line(h :: PartHeaders, line :: Str) -> PartHeaders {
  if str.is_empty(str.trim(line)) { h }
  else {
    match find_char(line, ":") {
      None    => h,
      Some(i) => {
        let key := str.to_lower(str.trim(str.slice(line, 0, i)))
        let val := str.trim(str.slice(line, i + 1, str.len(line)))
        if key == "content-disposition" {
          parse_content_disposition(h, val)
        } else {
          if key == "content-type" {
            { name: h.name, filename: h.filename, content_type: Some(val) }
          } else { h }
        }
      },
    }
  }
}

fn find_char(s :: Str, c :: Str) -> Option[Int] {
  find_char_at(s, c, 0, str.len(s))
}

fn find_char_at(s :: Str, c :: Str, i :: Int, n :: Int) -> Option[Int] {
  if i >= n { None }
  else {
    if str.slice(s, i, i + 1) == c { Some(i) }
    else { find_char_at(s, c, i + 1, n) }
  }
}

# `form-data; name="field"; filename="x.txt"` — split on `;`,
# trim each, peel `name=` and `filename=` prefixes, unquote.
fn parse_content_disposition(h :: PartHeaders, val :: Str) -> PartHeaders {
  let segs := str.split(val, ";")
  list.fold(segs, h, fn (acc :: PartHeaders, seg :: Str) -> PartHeaders {
    let t := str.trim(seg)
    match str.strip_prefix(t, "name=") {
      Some(v) => { name: Some(unquote(v)),
                   filename: acc.filename,
                   content_type: acc.content_type },
      None    => match str.strip_prefix(t, "filename=") {
        Some(v) => { name: acc.name,
                     filename: Some(unquote(v)),
                     content_type: acc.content_type },
        None    => acc,
      },
    }
  })
}

fn unquote(s :: Str) -> Str {
  match str.strip_prefix(s, "\"") {
    Some(s2) => match str.strip_suffix(s2, "\"") {
      Some(s3) => s3,
      None     => s2,
    },
    None     => s,
  }
}

# ---- Validation wrapper ------------------------------------------

# Drop-in for `coerce.require_*_from_map` callers: takes an HTTP
# body string + Content-Type, decodes the appropriate format,
# returns a typed `Map[Str, Str]`. Multipart parts are flattened
# to `{ name -> body }`; callers that need filename + content_type
# metadata should call `decode_multipart` directly.
fn decode_body(
  body :: Str,
  content_type :: Str
) -> Result[Map[Str, Str], e.Errors] {
  if str.starts_with(content_type, "application/x-www-form-urlencoded") {
    Ok(decode_urlencoded(body))
  } else {
    if str.starts_with(content_type, "multipart/form-data") {
      match extract_boundary(content_type) {
        None    => Err(e.single("", "format",
          "multipart/form-data Content-Type missing boundary")),
        Some(b) => match decode_multipart(body, b) {
          Err(es)   => Err(es),
          Ok(parts) => Ok(parts_to_map(parts)),
        },
      }
    } else {
      Err(e.single("", e.code_type(),
        str.concat("unsupported content-type: ", content_type)))
    }
  }
}

# Pull `boundary=VALUE` out of a Content-Type header. Accepts
# optional quoting around the value and tolerates leading
# whitespace per RFC 2045.
fn extract_boundary(content_type :: Str) -> Option[Str] {
  let segs := str.split(content_type, ";")
  list.fold(segs, None,
    fn (acc :: Option[Str], seg :: Str) -> Option[Str] {
      match acc {
        Some(b) => Some(b),
        None    => {
          let t := str.trim(seg)
          match str.strip_prefix(t, "boundary=") {
            Some(v) => Some(unquote(v)),
            None    => None,
          }
        },
      }
    })
}

fn parts_to_map(parts :: List[MultipartPart]) -> Map[Str, Str] {
  let pairs := list.map(parts, fn (p :: MultipartPart) -> (Str, Str) {
    (p.name, p.body)
  })
  map.from_list(pairs)
}
