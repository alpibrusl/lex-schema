# lex-pydantic — HTTP API request body validation
#
# A small REST endpoint that uses lex-pydantic to validate the
# incoming JSON body, returning 200 + the typed result or 400 +
# the full error list.
#
# Demonstrates the production shape: the handler does
#
#   parse → validate → business logic → respond
#
# with each phase a Result that's threaded via lex's `match`.
# Validation failures never leak as 500s; they always come back
# as structured 400 JSON the client can render field-by-field.
#
# Run:
#   lex run --allow-effects net examples/04_api_request.lex main
# Then:
#   curl -X POST http://127.0.0.1:8123/signup \
#     -H 'content-type: application/json' \
#     -d '{"email":"alice@example.com","username":"alice","age":29}'
#
#   curl -X POST http://127.0.0.1:8123/signup \
#     -H 'content-type: application/json' \
#     -d '{"email":"nope","username":"x","age":-5}'

import "std.net"  as net
import "std.str"  as str
import "std.list" as list

import "../src/error"       as e
import "../src/constraints" as c
import "../src/field"       as f
import "../src/combine"     as cm
import "../src/parse"       as p

# ---- HTTP types (per net.serve handler contract) ------------------

type Request = { body :: Str, method :: Str, path :: Str, query :: Str }
type Response = { body :: Str, status :: Int }

# ---- Business types -----------------------------------------------

type Signup = {
  email :: Str,
  username :: Str,
  age :: Int,
}

type RawSignup = {
  email :: Str,
  username :: Str,
  age :: Int,
}

fn mk_signup(em :: Str, un :: Str, ag :: Int) -> Signup {
  { email: em, username: un, age: ag }
}

# ---- Validator ----------------------------------------------------

fn validate_signup(raw :: RawSignup) -> Result[Signup, List[e.Error]] {
  cm.combine3(
    f.check_str("email",    raw.email,    [StrEmail]),
    f.check_str("username", raw.username, [StrMinLen(3), StrMaxLen(32),
                                           StrPattern("^[a-zA-Z0-9_]+$")]),
    f.check_int("age",      raw.age,      [IntInRange(13, 130)]),
    mk_signup
  )
}

fn parse_signup(body :: Str) -> Result[Signup, List[e.Error]] {
  cm.and_then(
    p.from_json(body, ["email", "username", "age"]),
    fn (raw :: RawSignup) -> Result[Signup, List[e.Error]] { validate_signup(raw) }
  )
}

# ---- Render errors as a JSON-ish body -----------------------------
# Hand-rolled rather than going through json.stringify so the output
# shape is explicit and stable. The library doesn't take a hard
# dependency on a specific output format.

fn render_error(err :: e.Error) -> Str {
  let q := "\""
  let pieces := str.concat(str.concat(q, "path"), str.concat(q, ":"))
  let pp := str.concat(pieces, str.concat(q, str.concat(err.path, str.concat(q, ","))))
  let cc := str.concat(pp, str.concat(str.concat(q, "code"), str.concat(q, ":")))
  let ccv := str.concat(cc, str.concat(q, str.concat(err.code, str.concat(q, ","))))
  let mm := str.concat(ccv, str.concat(str.concat(q, "message"), str.concat(q, ":")))
  let mmv := str.concat(mm, str.concat(q, str.concat(err.message, q)))
  str.concat("{", str.concat(mmv, "}"))
}

fn render_errors(errs :: List[e.Error]) -> Str {
  let items := list.map(errs, fn (er :: e.Error) -> Str { render_error(er) })
  let inner := str.join(items, ",")
  str.concat("{\"errors\":[", str.concat(inner, "]}"))
}

# ---- Handler ------------------------------------------------------

fn handle(req :: Request) -> Response {
  match req.method {
    "POST" => match req.path {
      "/signup" => match parse_signup(req.body) {
        Ok(s)   => {
          status: 200,
          body: str.concat("{\"ok\":true,\"username\":\"",
                           str.concat(s.username, "\"}")),
        },
        Err(es) => { status: 400, body: render_errors(es) },
      },
      _ => { status: 404, body: "{\"error\":\"not found\"}" },
    },
    _ => { status: 405, body: "{\"error\":\"method not allowed\"}" },
  }
}

fn main() -> [net] Nil {
  net.serve(8123, "handle")
}
