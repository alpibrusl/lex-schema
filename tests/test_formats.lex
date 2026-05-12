# Tests for the new format validators in src/constraints.lex —
# IP, hostname, ISO date/time, base64, hex, phone E.164, Luhn.

import "std.list" as list
import "std.str"  as str

import "../src/error"       as e
import "../src/constraints" as c

# ---- IPv4 ---------------------------------------------------------

fn ipv4_ok() -> Result[Unit, Str] {
  match c.eval_str(StrIPv4, "192.168.1.1") {
    None    => Ok(()),
    Some(m) => Err(str.concat("rejected: ", m)),
  }
}

fn ipv4_bad_octet() -> Result[Unit, Str] {
  match c.eval_str(StrIPv4, "256.1.1.1") {
    Some(_) => Ok(()),
    None    => Err("256 should fail"),
  }
}

fn ipv4_truncated() -> Result[Unit, Str] {
  match c.eval_str(StrIPv4, "1.1.1") {
    Some(_) => Ok(()),
    None    => Err("3-octet should fail"),
  }
}

# ---- IPv6 ---------------------------------------------------------

fn ipv6_full() -> Result[Unit, Str] {
  match c.eval_str(StrIPv6, "2001:0db8:85a3:0000:0000:8a2e:0370:7334") {
    None    => Ok(()),
    Some(_) => Err("rejected"),
  }
}

fn ipv6_shortened() -> Result[Unit, Str] {
  match c.eval_str(StrIPv6, "2001:db8::1") {
    None    => Ok(()),
    Some(_) => Err("rejected"),
  }
}

fn ipv6_bad() -> Result[Unit, Str] {
  match c.eval_str(StrIPv6, "not-an-ip") {
    Some(_) => Ok(()),
    None    => Err("should fail"),
  }
}

# ---- Hostname -----------------------------------------------------

fn hostname_ok() -> Result[Unit, Str] {
  match c.eval_str(StrHostname, "api.example.com") {
    None    => Ok(()),
    Some(_) => Err("rejected"),
  }
}

fn hostname_bad_chars() -> Result[Unit, Str] {
  match c.eval_str(StrHostname, "bad host!") {
    Some(_) => Ok(()),
    None    => Err("should fail"),
  }
}

# ---- ISO date / time ---------------------------------------------

fn iso_date_ok() -> Result[Unit, Str] {
  match c.eval_str(StrIsoDate, "2026-05-12") {
    None    => Ok(()),
    Some(_) => Err("rejected"),
  }
}

fn iso_date_bad_month() -> Result[Unit, Str] {
  match c.eval_str(StrIsoDate, "2026-13-01") {
    Some(_) => Ok(()),
    None    => Err("month 13 should fail"),
  }
}

fn iso_time_ok() -> Result[Unit, Str] {
  match c.eval_str(StrIsoTime, "14:30:00") {
    None    => Ok(()),
    Some(_) => Err("rejected"),
  }
}

fn iso_time_with_frac() -> Result[Unit, Str] {
  match c.eval_str(StrIsoTime, "14:30:00.123") {
    None    => Ok(()),
    Some(_) => Err("fractional seconds should pass"),
  }
}

# ---- Base64 / Hex ------------------------------------------------

fn base64_ok() -> Result[Unit, Str] {
  match c.eval_str(StrBase64, "SGVsbG8=") {
    None    => Ok(()),
    Some(_) => Err("rejected"),
  }
}

fn base64_bad_padding() -> Result[Unit, Str] {
  # Length not divisible by 4.
  match c.eval_str(StrBase64, "SGVsb=") {
    Some(_) => Ok(()),
    None    => Err("should fail"),
  }
}

fn hex_ok() -> Result[Unit, Str] {
  match c.eval_str(StrHex, "deadbeef") {
    None    => Ok(()),
    Some(_) => Err("rejected"),
  }
}

fn hex_bad() -> Result[Unit, Str] {
  match c.eval_str(StrHex, "xyz") {
    Some(_) => Ok(()),
    None    => Err("should fail"),
  }
}

# ---- Phone E.164 -------------------------------------------------

fn phone_ok() -> Result[Unit, Str] {
  match c.eval_str(StrPhoneE164, "+14155551234") {
    None    => Ok(()),
    Some(_) => Err("rejected"),
  }
}

fn phone_no_plus() -> Result[Unit, Str] {
  match c.eval_str(StrPhoneE164, "14155551234") {
    Some(_) => Ok(()),
    None    => Err("should fail"),
  }
}

# ---- Luhn / Credit card ------------------------------------------

fn luhn_valid_visa() -> Result[Unit, Str] {
  # Standard Visa test number that passes Luhn.
  match c.eval_str(StrCreditCardLuhn, "4111111111111111") {
    None    => Ok(()),
    Some(m) => Err(str.concat("rejected: ", m)),
  }
}

fn luhn_invalid() -> Result[Unit, Str] {
  match c.eval_str(StrCreditCardLuhn, "4111111111111112") {
    Some(_) => Ok(()),
    None    => Err("should fail"),
  }
}

fn luhn_too_short() -> Result[Unit, Str] {
  match c.eval_str(StrCreditCardLuhn, "411111") {
    Some(_) => Ok(()),
    None    => Err("short numbers should fail"),
  }
}

# ---- Suite --------------------------------------------------------

fn suite() -> List[Result[Unit, Str]] {
  [
    ipv4_ok(), ipv4_bad_octet(), ipv4_truncated(),
    ipv6_full(), ipv6_shortened(), ipv6_bad(),
    hostname_ok(), hostname_bad_chars(),
    iso_date_ok(), iso_date_bad_month(),
    iso_time_ok(), iso_time_with_frac(),
    base64_ok(), base64_bad_padding(),
    hex_ok(), hex_bad(),
    phone_ok(), phone_no_plus(),
    luhn_valid_visa(), luhn_invalid(), luhn_too_short(),
  ]
}

fn run_all() -> Int {
  list.fold(suite(), 0, fn (acc :: Int, v :: Result[Unit, Str]) -> Int {
    match v { Ok(_) => acc, Err(_) => acc + 1 }
  })
}
