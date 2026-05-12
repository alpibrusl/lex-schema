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

# ---- multipart/form-data (v1 stub) -------------------------------
#
# Multipart parsing means tracking a CRLF-delimited boundary,
# walking N parts each with `Content-Disposition` headers + an
# optional `Content-Type` + a body that may be binary. The full
# implementation is ~300-500 LoC — out of scope for this slice.
# The stub here exists so callers wire the same shape into their
# handler today and switch over when multipart lands.

type MultipartPart = {
  name :: Str,
  filename :: Option[Str],
  content_type :: Str,
  body :: Str,
}

fn decode_multipart(
  body :: Str,
  boundary :: Str
) -> Result[List[MultipartPart], e.Errors] {
  let _ := body
  let _ := boundary
  Err(e.single("", "unimplemented",
    "multipart/form-data parsing is not yet supported; see lex-schema CHANGELOG"))
}

# ---- Validation wrapper ------------------------------------------

# Drop-in for `coerce.require_*_from_map` callers: takes an HTTP
# body string + Content-Type, decodes the appropriate format,
# returns a typed `Map[Str, Str]`. Errors out on `multipart/`
# since that's the v1 stub; callers gating on that should
# inspect `content_type` themselves.
fn decode_body(
  body :: Str,
  content_type :: Str
) -> Result[Map[Str, Str], e.Errors] {
  if str.starts_with(content_type, "application/x-www-form-urlencoded") {
    Ok(decode_urlencoded(body))
  } else {
    if str.starts_with(content_type, "multipart/form-data") {
      Err(e.single("", "unimplemented",
        "multipart/form-data decoding is not yet supported"))
    } else {
      Err(e.single("", e.code_type(),
        str.concat("unsupported content-type: ", content_type)))
    }
  }
}
