# lex-schema -- schema-as-source-of-truth: SQL DDL codegen
#
# SQLModel (Sébastien Ramírez's python package) collapses pydantic
# + SQLAlchemy into one class. lex-schema gets there from the
# other direction: `ModelSchema` is already the single source of
# truth (TS / Python / Zod / Rust / Go / JSON Schema / Mermaid ER
# all derive from it). v0.8.2 adds SQL DDL as the seventh target.
#
# A future `lex-orm` package would compose on top — issuing
# typed queries, managing transactions over the `sql` effect.
# That's not in this library; the DDL emitter is.
#
# Run:
#   lex run examples/23_sql_ddl.lex demo_postgres
#   lex run examples/23_sql_ddl.lex demo_sqlite
#   lex run examples/23_sql_ddl.lex demo_nested_postgres

import "../src/schema" as s
import "../src/sdk"    as sdk

# ---- A "blog post" model with format + range constraints --------

fn post_schema() -> s.ModelSchema {
  {
    title: "Post",
    description: "A blog post backed by a relational row",
    fields: [
      s.required_str("id", [StrUuid]),
      s.required_str("slug", [StrMinLen(3), StrMaxLen(80),
                              StrPattern("^[a-z0-9-]+$")]),
      s.required_str("title", [StrMinLen(1), StrMaxLen(200)]),
      s.required_str("body", []),
      s.required_str("status",
        [StrOneOf(["draft", "published", "archived"])]),
      s.required_int("read_minutes", [IntInRange(1, 600)]),
      s.required_bool("featured"),
      s.optional(s.required_str("og_image", [StrUrl])),
    ],
  }
}

# ---- A nested model: Order -> Buyer (FK relationship) -----------

fn order_schema() -> s.ModelSchema {
  {
    title: "Order",
    description: "Order with embedded buyer record",
    fields: [
      s.required_str("id", [StrUuid]),
      s.required_str("status",
        [StrOneOf(["pending", "paid", "shipped", "delivered", "cancelled"])]),
      s.required_int("total_cents", [IntPositive]),
      s.required_object("buyer", {
        title: "Buyer",
        description: "Person placing the order",
        fields: [
          s.required_str("id", [StrUuid]),
          s.required_str("email", [StrEmail]),
          s.required_str("phone", [StrPhoneE164]),
        ],
      }),
    ],
  }
}

# ---- Demos ------------------------------------------------------

fn demo_postgres() -> Str {
  sdk.to_sql_ddl(post_schema(), DialectPostgres)
}

fn demo_sqlite() -> Str {
  sdk.to_sql_ddl(post_schema(), DialectSqlite)
}

fn demo_nested_postgres() -> Str {
  sdk.to_sql_ddl(order_schema(), DialectPostgres)
}

fn demo_nested_sqlite() -> Str {
  sdk.to_sql_ddl(order_schema(), DialectSqlite)
}
