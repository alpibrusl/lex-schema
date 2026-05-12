# lex-pydantic — list-of-records validation
#
# A purchase order with a list of line items. Each item is its own
# validated record; the parent list gets shape constraints (at least
# one item, no more than 50). Element-level errors carry the index
# in the path — `items[3].quantity` — so the caller can pinpoint
# the offending row.
#
# Run:
#   lex run examples/03_list_of_items.lex validate_good
#   lex run examples/03_list_of_items.lex validate_bad

import "std.int"  as int
import "std.str"  as str
import "std.list" as list

import "../src/error"       as e
import "../src/constraints" as c
import "../src/field"       as f
import "../src/combine"     as cm
import "../src/parse"       as p

# ---- Types --------------------------------------------------------

type LineItem = {
  sku :: Str,
  quantity :: Int,
  price_cents :: Int,
}

type Order = {
  customer :: Str,
  items :: List[LineItem],
}

type RawItem = {
  sku :: Str,
  quantity :: Int,
  price_cents :: Int,
}

type RawOrder = {
  customer :: Str,
  items :: List[RawItem],
}

# ---- Builders -----------------------------------------------------

fn mk_item(s :: Str, q :: Int, pc :: Int) -> LineItem {
  { sku: s, quantity: q, price_cents: pc }
}

fn mk_order(c :: Str, items :: List[LineItem]) -> Order {
  { customer: c, items: items }
}

# ---- Element validator --------------------------------------------

fn sku_pattern() -> Str { "^[A-Z]{3}-[0-9]{4}$" }

fn validate_item(path :: Str, raw :: RawItem) -> Result[LineItem, e.Errors] {
  cm.with_path(path, cm.combine3(
    f.check_str("sku",         raw.sku,         [StrPattern(sku_pattern())]),
    f.check_int("quantity",    raw.quantity,    [IntPositive, IntMax(1000)]),
    f.check_int("price_cents", raw.price_cents, [IntMin(0), IntMax(1000000)]),
    mk_item
  ))
}

# ---- List validator -----------------------------------------------
# `check_list_of` runs shape checks (length-style) then applies the
# per-item validator with a path-aware label.

fn validate_items(raws :: List[RawItem]) -> Result[List[LineItem], e.Errors] {
  # First check the shape of the list, then convert each row.
  # We do the conversion via `traverse` so the validated values
  # carry the correct element type (`LineItem`, not `RawItem`).
  match f.check_list_shape("items", raws, [ListNonEmpty, ListMaxLen(50)]) {
    Err(es) => Err(es),
    Ok(_)   => cm.traverse(list.enumerate(raws), fn (p :: (Int, RawItem)) -> Result[LineItem, e.Errors] {
      let i := match p { (a, _) => a }
      let v := match p { (_, b) => b }
      validate_item(item_label(i), v)
    }),
  }
}

# ---- Outer validator ----------------------------------------------

fn validate_order(raw :: RawOrder) -> Result[Order, e.Errors] {
  cm.combine2(
    f.check_str("customer", raw.customer, [StrMinLen(1), StrMaxLen(80)]),
    validate_items(raw.items),
    mk_order
  )
}

fn parse_order(input :: Str) -> Result[Order, e.Errors] {
  cm.and_then(
    p.from_json(input, ["customer", "items"]),
    fn (raw :: RawOrder) -> Result[Order, e.Errors] { validate_order(raw) }
  )
}

# ---- Helpers ------------------------------------------------------

fn item_label(i :: Int) -> Str {
  str.concat(str.concat("items[", int.to_str(i)), "]")
}

# ---- Demo entrypoints ---------------------------------------------

fn validate_good() -> Result[Order, e.Errors] {
  parse_order(
    "{\"customer\":\"Acme\",\"items\":[{\"sku\":\"ABC-1234\",\"quantity\":2,\"price_cents\":2500},{\"sku\":\"XYZ-7777\",\"quantity\":1,\"price_cents\":499}]}"
  )
}

fn validate_bad() -> Result[Order, e.Errors] {
  # First item has a bad sku format; second item has negative qty
  # and price; third item has a sku that's too short.
  parse_order(
    "{\"customer\":\"\",\"items\":[{\"sku\":\"abc\",\"quantity\":1,\"price_cents\":100},{\"sku\":\"DEF-1111\",\"quantity\":-1,\"price_cents\":-50},{\"sku\":\"XX\",\"quantity\":0,\"price_cents\":10}]}"
  )
}

fn format_demo() -> Str {
  match validate_bad() {
    Ok(_)    => "no errors",
    Err(es)  => e.format(es),
  }
}
