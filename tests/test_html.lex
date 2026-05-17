# Tests for `src/html.lex` — HTML entity escaping.

import "std.list" as list
import "std.str"  as str

import "../src/html" as html

fn empty_passes_through() -> Result[Unit, Str] {
  if html.escape("") == "" { Ok(()) } else { Err("empty did not pass through") }
}

fn plain_passes_through() -> Result[Unit, Str] {
  if html.escape("hello world") == "hello world" { Ok(()) }
  else { Err("plain text did not pass through") }
}

fn ampersand_escapes() -> Result[Unit, Str] {
  if html.escape("a & b") == "a &amp; b" { Ok(()) }
  else { Err(str.concat("amp: got ", html.escape("a & b"))) }
}

fn lt_gt_escapes() -> Result[Unit, Str] {
  if html.escape("<script>") == "&lt;script&gt;" { Ok(()) }
  else { Err("<script> did not escape to &lt;script&gt;") }
}

fn double_quote_escapes() -> Result[Unit, Str] {
  if html.escape("\"q\"") == "&quot;q&quot;" { Ok(()) }
  else { Err("double quotes did not escape to &quot;") }
}

fn apostrophe_uses_numeric_entity() -> Result[Unit, Str] {
  # Numeric `&#39;` rather than `&apos;` — `&apos;` is not in HTML
  # 4.01 and some legacy parsers don't recognise it.
  if html.escape("it's") == "it&#39;s" { Ok(()) }
  else { Err(str.concat("apos: got ", html.escape("it's"))) }
}

fn ampersand_replaced_first() -> Result[Unit, Str] {
  # If `<` were replaced before `&`, the `&` of `&lt;` would be
  # re-escaped, giving `&amp;lt;` instead of `&lt;`.
  if html.escape("<") == "&lt;" { Ok(()) }
  else { Err(str.concat("ordering: got ", html.escape("<"))) }
}

fn attribute_payload() -> Result[Unit, Str] {
  # Classic attribute-context XSS payload: break out of value="..."
  # and inject an event handler. After escaping it must be inert.
  let input  := "\" onerror=\"alert(1)"
  let output := "&quot; onerror=&quot;alert(1)"
  if html.escape(input) == output { Ok(()) }
  else { Err(str.concat("attr: got ", html.escape(input))) }
}

fn not_idempotent() -> Result[Unit, Str] {
  # Intentional: feeding already-escaped HTML in re-escapes the `&`
  # of every entity. The correct usage is to call `escape` exactly
  # once at the outermost interpolation boundary.
  if html.escape("&amp;") == "&amp;amp;" { Ok(()) }
  else { Err("idempotency check unexpectedly passed") }
}

fn suite() -> List[Result[Unit, Str]] {
  [
    empty_passes_through(),
    plain_passes_through(),
    ampersand_escapes(),
    lt_gt_escapes(),
    double_quote_escapes(),
    apostrophe_uses_numeric_entity(),
    ampersand_replaced_first(),
    attribute_payload(),
    not_idempotent(),
  ]
}

fn run_all() -> Int {
  list.fold(suite(), 0, fn (acc :: Int, v :: Result[Unit, Str]) -> Int {
    match v { Ok(_) => acc, Err(_) => acc + 1 }
  })
}
