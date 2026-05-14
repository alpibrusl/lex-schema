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
#       # 2. Hash it — returns [crypto] so keep this at the effectful
#       #    boundary of your handler (e.g. after parsing the request).
#       let hash := hashing.argon2id_hash(pw)
#       store(hash)
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
#   argon2id_hash / pbkdf2_hash / random_salt — [crypto]
#   argon2id_verify / pbkdf2_verify           — none (pure; hash re-derives)

import "std.str"    as str
import "std.crypto" as crypto

# ---- Argon2id ---------------------------------------------------

# Recommended default parameters (OWASP 2023 guidance):
#   m_cost = 65536 (64 MiB), t_cost = 3, p_cost = 4
fn argon2id_m_cost() -> Int { 65536 }
fn argon2id_t_cost() -> Int { 3 }
fn argon2id_p_cost() -> Int { 4 }

# Hash `password` with argon2id using a fresh random salt.
# Returns an opaque `salt$hash` string suitable for storage.
fn argon2id_hash(password :: Str) -> [crypto] Str {
  let salt := crypto.random_str_hex(16)
  let h    := crypto.argon2id(
    password, salt,
    argon2id_m_cost(), argon2id_t_cost(), argon2id_p_cost())
  str.concat(salt, str.concat("$", h))
}

# Verify `candidate` against a stored argon2id token produced by
# `argon2id_hash`. Returns Ok(true) on match, Ok(false) on mismatch,
# Err if the stored token is malformed.
fn argon2id_verify(stored :: Str, candidate :: Str) -> Result[Bool, Str] {
  match str.find(stored, "$") {
    None      => Err("malformed argon2id token"),
    Some(sep) => {
      let salt     := str.slice(stored, 0, sep)
      let expected := str.slice(stored, sep + 1, str.len(stored))
      let actual   := crypto.argon2id(
        candidate, salt,
        argon2id_m_cost(), argon2id_t_cost(), argon2id_p_cost())
      Ok(crypto.eq(actual, expected))
    },
  }
}

# ---- PBKDF2-SHA256 -----------------------------------------------

# Recommended defaults: 600 000 iterations (NIST SP 800-132 2023).
fn pbkdf2_iters()   -> Int { 600000 }
fn pbkdf2_key_len() -> Int { 32 }

# Hash `password` with PBKDF2-SHA256 using a fresh random salt.
# Returns an opaque `salt$hash` string.
fn pbkdf2_hash(password :: Str) -> [crypto] Str {
  let salt := crypto.random_str_hex(16)
  let h    := crypto.pbkdf2_sha256(
    password, salt, pbkdf2_iters(), pbkdf2_key_len())
  str.concat(salt, str.concat("$", h))
}

# Verify `candidate` against a stored pbkdf2 token.
fn pbkdf2_verify(stored :: Str, candidate :: Str) -> Result[Bool, Str] {
  match str.find(stored, "$") {
    None      => Err("malformed pbkdf2 token"),
    Some(sep) => {
      let salt     := str.slice(stored, 0, sep)
      let expected := str.slice(stored, sep + 1, str.len(stored))
      let actual   := crypto.pbkdf2_sha256(
        candidate, salt, pbkdf2_iters(), pbkdf2_key_len())
      Ok(crypto.eq(actual, expected))
    },
  }
}

# ---- Generic interface -------------------------------------------

# Algorithm selector. Callers can pass this through their stack to
# swap algorithms without changing call sites.
type HashAlgo = Argon2id | Pbkdf2Sha256

# Hash using the selected algorithm.
fn hash(algo :: HashAlgo, password :: Str) -> [crypto] Str {
  match algo {
    Argon2id    => argon2id_hash(password),
    Pbkdf2Sha256 => pbkdf2_hash(password),
  }
}

# Verify using the selected algorithm.
fn verify(algo :: HashAlgo, stored :: Str, candidate :: Str) -> Result[Bool, Str] {
  match algo {
    Argon2id    => argon2id_verify(stored, candidate),
    Pbkdf2Sha256 => pbkdf2_verify(stored, candidate),
  }
}

# ---- Key derivation (non-password) ------------------------------

# Derive a subkey from a master secret using HKDF-SHA256.
# Use for deriving per-purpose keys (signing, encryption) from one
# root key — do NOT use for password storage.
fn derive_key(master :: Str, salt :: Str, info :: Str) -> Str {
  crypto.hkdf_sha256(master, salt, info, 32)
}
