# lex-schema — HTML entity escaping for XSS-safe interpolation
#
# Maps the five OWASP-recommended characters to their HTML5
# entities. Use this whenever you interpolate untrusted text into
# an HTML body or attribute value:
#
#   <p>Hello, {{escape(user_name)}}.</p>
#   <input value="{{escape(default_value)}}">
#
# Scope: HTML *text* and *attribute* contexts only. CSS,
# JavaScript, and URL contexts have different escaping rules —
# using HTML escapes in a `<script>`, `style=`, or `href=`
# payload is a real XSS bug. Each of those deserves its own
# module so the type system can stop callers from grabbing the
# wrong one.
#
# Idempotency: intentionally not idempotent. Feeding already-
# escaped HTML in re-escapes the `&` of every entity (`&lt;` ->
# `&amp;lt;`). That's the correct behaviour — re-interpolating
# already-escaped markup into another HTML context is the bug
# this function exists to prevent, and double-escape is the safe
# response. Call `escape` exactly once, at the outermost
# interpolation boundary.
#
# Effects: none.

import "std.str" as str

# Replace the five OWASP-recommended HTML special chars with their
# HTML5 entities. `&` is replaced first — otherwise the `&` of
# every other entity (`&lt;`, `&gt;`, ...) would be re-escaped on
# subsequent passes (`<` -> `&lt;` -> `&amp;lt;`).
#
# Uses `&#39;` (numeric) for the apostrophe rather than `&apos;`:
# the named entity is not in HTML 4.01 and some legacy parsers
# don't recognise it. Go's `html.EscapeString` makes the same
# call.
fn escape(s :: Str) -> Str
  examples {
    escape("") => "",
    escape("hello world") => "hello world",
    escape("a & b") => "a &amp; b",
    escape("<script>") => "&lt;script&gt;",
    escape("\"quoted\"") => "&quot;quoted&quot;",
    escape("it's") => "it&#39;s",
    escape("a<b>c&d\"e'f") => "a&lt;b&gt;c&amp;d&quot;e&#39;f",
    escape("&amp;") => "&amp;amp;"
  }
{
  let s1 := str.replace(s, "&", "&amp;")
  let s2 := str.replace(s1, "<", "&lt;")
  let s3 := str.replace(s2, ">", "&gt;")
  let s4 := str.replace(s3, "\"", "&quot;")
  str.replace(s4, "'", "&#39;")
}

