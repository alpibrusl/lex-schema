# lex-schema — password hashing and verification
#
# Wraps the std.crypto KDF primitives added in lex-lang 0.9.2:
#   - argon2id  (recommended for new applications)
#   - pbkdf2_sha256
#
# Provides a uniform `hash / verify` interface so callers don't need
# to know which KDF is in use — useful when migrating between
# algorithms over time.
#
# Usage pattern with lex-schema validation:
#
#   # 1. Validate the raw password field first:
#   match field.check_str("password", raw_pw, [StrMinLen(8), StrMaxLen(128)]) {
#     Err(es) => Err(es),
#     Ok(pw)  =>
#       # 2. Hash it — requires [random] for salt generation, so keep
#       #    this at the effectful boundary of your handler.
#       match hashing.argon2id_hash(pw) {
#         Err(msg) => Err(msg),
#         Ok(hash) => store(hash),
#       }
#   }
#
#   # 3. Verify on login:
#   match hashing.argon2id_verify(stored_hash, candidate_pw) {
#     Ok(true)  => allow_login(),
#     Ok(false) => Err("wrong password"),
#     Err(msg)  => Err(msg),
#   }
#
# Effects:
#   *_hash       — [random] (random salt generation)
#   *_verify     — none (pure; re-derives from stored salt)
#   derive_key   — none

import "std.str"    as str
import "std.list"   as list
import "std.bytes"  as bytes
import "std.crypto" as crypto

# ---- Argon2id ---------------------------------------------------

# Recommended default parameters (OWASP 2023 guidance):
#   m_cost = 65536 (64 MiB), t_cost = 3, p_cost = 4
fn argon2id_m_cost() -> Int { 65536 }
fn argon2id_t_cost() -> Int { 3 }
fn argon2id_p_cost() -> Int { 4 }

# Hash `password` with argon2id using a fresh random salt.
# Returns an opaque `salt$hex_hash` string suitable for storage.
fn argon2id_hash(password :: Str) -> [random] Result[Str, Str] {
  let salt := crypto.random_str_hex(16)
  match crypto.argon2id(
    bytes.from_str(password), bytes.from_str(salt),
    argon2id_m_cost(), argon2id_t_cost(), argon2id_p_cost()) {
    Err(e) => Err(e),
    Ok(h)  => Ok(str.concat(salt, str.concat("$", crypto.hex_encode(h)))),
  }
}

# Verify `candidate` against a stored argon2id token produced by
# `argon2id_hash`. Returns Ok(true) on match, Ok(false) on mismatch,
# Err if the stored token is malformed.
fn argon2id_verify(stored :: Str, candidate :: Str) -> Result[Bool, Str] {
  let parts := str.split(stored, "$")
  if list.len(parts) != 2 {
    Err("malformed argon2id token")
  } else {
    let salt := match list.head(parts) {
      Some(s) => s,
      None    => "",
    }
    let expected_hex := match list.head(list.tail(parts)) {
      Some(s) => s,
      None    => "",
    }
    match crypto.argon2id(
      bytes.from_str(candidate), bytes.from_str(salt),
      argon2id_m_cost(), argon2id_t_cost(), argon2id_p_cost()) {
      Err(e)     => Err(e),
      Ok(actual) =>
        match crypto.hex_decode(expected_hex) {
          Err(e)         => Err(e),
          Ok(expected_b) => Ok(crypto.eq(actual, expected_b)),
        },
    }
  }
}

# ---- PBKDF2-SHA256 -----------------------------------------------

# Recommended defaults: 600 000 iterations (NIST SP 800-132 2023).
fn pbkdf2_iters()   -> Int { 600000 }
fn pbkdf2_key_len() -> Int { 32 }

# Hash `password` with PBKDF2-SHA256 using a fresh random salt.
# Returns an opaque `salt$hex_hash` string.
fn pbkdf2_hash(password :: Str) -> [random] Result[Str, Str] {
  let salt := crypto.random_str_hex(16)
  match crypto.pbkdf2_sha256(
    bytes.from_str(password), bytes.from_str(salt),
    pbkdf2_iters(), pbkdf2_key_len()) {
    Err(e) => Err(e),
    Ok(h)  => Ok(str.concat(salt, str.concat("$", crypto.hex_encode(h)))),
  }
}

# Verify `candidate` against a stored pbkdf2 token.
fn pbkdf2_verify(stored :: Str, candidate :: Str) -> Result[Bool, Str] {
  let parts := str.split(stored, "$")
  if list.len(parts) != 2 {
    Err("malformed pbkdf2 token")
  } else {
    let salt := match list.head(parts) {
      Some(s) => s,
      None    => "",
    }
    let expected_hex := match list.head(list.tail(parts)) {
      Some(s) => s,
      None    => "",
    }
    match crypto.pbkdf2_sha256(
      bytes.from_str(candidate), bytes.from_str(salt),
      pbkdf2_iters(), pbkdf2_key_len()) {
      Err(e)     => Err(e),
      Ok(actual) =>
        match crypto.hex_decode(expected_hex) {
          Err(e)         => Err(e),
          Ok(expected_b) => Ok(crypto.eq(actual, expected_b)),
        },
    }
  }
}

# ---- Generic interface -------------------------------------------

# Algorithm selector. Callers can pass this through their stack to
# swap algorithms without changing call sites.
type HashAlgo = Argon2id | Pbkdf2Sha256

# Hash using the selected algorithm.
fn hash(algo :: HashAlgo, password :: Str) -> [random] Result[Str, Str] {
  match algo {
    Argon2id     => argon2id_hash(password),
    Pbkdf2Sha256 => pbkdf2_hash(password),
  }
}

# Verify using the selected algorithm.
fn verify(algo :: HashAlgo, stored :: Str, candidate :: Str) -> Result[Bool, Str] {
  match algo {
    Argon2id     => argon2id_verify(stored, candidate),
    Pbkdf2Sha256 => pbkdf2_verify(stored, candidate),
  }
}

# ---- Key derivation (non-password) ------------------------------

# Derive a subkey from a master secret using HKDF-SHA256.
# Use for deriving per-purpose keys (signing, encryption) from one
# root key — do NOT use for password storage.
fn derive_key(master :: Str, salt :: Str, info :: Str) -> Result[Str, Str] {
  match crypto.hkdf_sha256(
    bytes.from_str(master), bytes.from_str(salt), bytes.from_str(info), 32) {
    Err(e) => Err(e),
    Ok(k)  => Ok(crypto.hex_encode(k)),
  }
}
