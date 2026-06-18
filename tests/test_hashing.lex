# tests/test_hashing.lex — password hashing test suite

import "std.list" as list

import "../src/hashing" as h

# ---- Argon2id round-trip -----------------------------------------
fn test_argon2id_round_trip() -> [random] Bool {
  match h.argon2id_hash("correct-horse-battery-staple") {
    Err(_) => false,
    Ok(stored) => match h.argon2id_verify(stored, "correct-horse-battery-staple") {
      Ok(v) => v,
      Err(_) => false,
    },
  }
}

fn test_argon2id_wrong_password() -> [random] Bool {
  match h.argon2id_hash("correct-horse-battery-staple") {
    Err(_) => false,
    Ok(stored) => match h.argon2id_verify(stored, "wrong-password") {
      Ok(v) => not v,
      Err(_) => false,
    },
  }
}

fn test_argon2id_two_hashes_differ() -> [random] Bool {
  match h.argon2id_hash("password") {
    Err(_) => false,
    Ok(a) => match h.argon2id_hash("password") {
      Err(_) => false,
      Ok(b) => a != b,
    },
  }
}

fn test_argon2id_malformed_token() -> Bool {
  match h.argon2id_verify("no-dollar-sign", "pw") {
    Err(_) => true,
    Ok(_) => false,
  }
}

# ---- PBKDF2 round-trip -------------------------------------------
fn test_pbkdf2_round_trip() -> [random] Bool {
  match h.pbkdf2_hash("hunter2") {
    Err(_) => false,
    Ok(stored) => match h.pbkdf2_verify(stored, "hunter2") {
      Ok(v) => v,
      Err(_) => false,
    },
  }
}

fn test_pbkdf2_wrong_password() -> [random] Bool {
  match h.pbkdf2_hash("hunter2") {
    Err(_) => false,
    Ok(stored) => match h.pbkdf2_verify(stored, "hunter3") {
      Ok(v) => not v,
      Err(_) => false,
    },
  }
}

fn test_pbkdf2_malformed_token() -> Bool {
  match h.pbkdf2_verify("nodollar", "pw") {
    Err(_) => true,
    Ok(_) => false,
  }
}

# ---- Generic interface -------------------------------------------
fn test_generic_argon2id() -> [random] Bool {
  match h.hash(Argon2id, "passw0rd") {
    Err(_) => false,
    Ok(stored) => match h.verify(Argon2id, stored, "passw0rd") {
      Ok(v) => v,
      Err(_) => false,
    },
  }
}

fn test_generic_pbkdf2() -> [random] Bool {
  match h.hash(Pbkdf2Sha256, "passw0rd") {
    Err(_) => false,
    Ok(stored) => match h.verify(Pbkdf2Sha256, stored, "passw0rd") {
      Ok(v) => v,
      Err(_) => false,
    },
  }
}

# ---- Key derivation ---------------------------------------------
fn test_derive_key_deterministic() -> Bool {
  match h.derive_key("master", "salt", "signing") {
    Err(_) => false,
    Ok(k1) => match h.derive_key("master", "salt", "signing") {
      Err(_) => false,
      Ok(k2) => k1 == k2,
    },
  }
}

fn test_derive_key_different_info() -> Bool {
  match h.derive_key("master", "salt", "signing") {
    Err(_) => false,
    Ok(k1) => match h.derive_key("master", "salt", "encryption") {
      Err(_) => false,
      Ok(k2) => k1 != k2,
    },
  }
}

# ---- Runner ------------------------------------------------------
fn run_all() -> [random] Int {
  let cases := [test_argon2id_round_trip(), test_argon2id_wrong_password(), test_argon2id_two_hashes_differ(), test_argon2id_malformed_token(), test_pbkdf2_round_trip(), test_pbkdf2_wrong_password(), test_pbkdf2_malformed_token(), test_generic_argon2id(), test_generic_pbkdf2(), test_derive_key_deterministic(), test_derive_key_different_info()]
  list.fold(cases, 0, fn (n :: Int, ok :: Bool) -> Int {
    if ok {
      n
    } else {
      n + 1
    }
  })
}

