// The scalar style serde_yaml 0.9.34 asks for when serializing a string
// (`serialize_str` and its `InferScalarStyle` visitor): strings that would
// read back as null, a bool, an integer or a float are single-quoted.

///|
priv enum ScalarStyle {
  Any
  Plain
  SingleQuoted
  DoubleQuoted
  Literal
} derive(Eq)

///|
fn infer_scalar_style(value : String) -> ScalarStyle {
  if value.contains_char('\n') {
    Literal
  } else if resolves_as_non_string(value) {
    SingleQuoted
  } else {
    Any
  }
}

///|
/// serde_yaml's `visit_untagged_scalar` finds something other than a
/// string, or `digits_but_not_number` holds.
fn resolves_as_non_string(v : String) -> Bool {
  match v {
    "" | "null" | "Null" | "NULL" | "~" => true
    "true" | "True" | "TRUE" | "false" | "False" | "FALSE" => true
    _ =>
      parse_unsigned_int(v) ||
      parse_negative_int(v) ||
      digits_but_not_number(v) ||
      parse_f64(v)
  }
}

///|
/// Leading zeros followed by digits (a string in YAML 1.2).
fn digits_but_not_number(scalar : String) -> Bool {
  let s = strip_sign(scalar)
  s.length() > 1 &&
  s.has_prefix("0") &&
  s[1:].iter().all(c => c >= '0' && c <= '9')
}

///|
fn strip_sign(s : String) -> StringView {
  if s.has_prefix("-") || s.has_prefix("+") {
    s[1:]
  } else {
    s[:]
  }
}

///|
fn starts_with_sign(s : StringView) -> Bool {
  s.has_prefix("+") || s.has_prefix("-")
}

///|
let u128_max : @bigint.BigInt = (1N << 128) - 1N

///|
let i128_max : @bigint.BigInt = (1N << 127) - 1N

///|
let i128_min_magnitude : @bigint.BigInt = 1N << 127

///|
/// Rust's `from_str_radix` on unsigned digits (no sign) with a magnitude
/// limit.
fn radix_digits_fit(
  digits : StringView,
  radix : Int,
  limit : @bigint.BigInt,
) -> Bool {
  if digits.is_empty() {
    return false
  }
  let mut value = 0N
  let big_radix = @bigint.BigInt::from_int(radix)
  for c in digits {
    let d = match c {
      '0'..='9' => c.to_int() - '0'.to_int()
      'a'..='z' => c.to_int() - 'a'.to_int() + 10
      'A'..='Z' => c.to_int() - 'A'.to_int() + 10
      _ => return false
    }
    if d >= radix {
      return false
    }
    value = value * big_radix + @bigint.BigInt::from_int(d)
    if value > limit {
      return false
    }
  }
  true
}

///|
/// `parse_unsigned_int` for `u64` and `u128`.
fn parse_unsigned_int(scalar : String) -> Bool {
  let unpositive = if scalar.has_prefix("+") { scalar[1:] } else { scalar[:] }
  for prefix in [("0x", 16), ("0o", 8), ("0b", 2)] {
    if unpositive.has_prefix(prefix.0) {
      let rest = unpositive[2:]
      if starts_with_sign(rest) {
        return false
      }
      if radix_digits_fit(rest, prefix.1, u128_max) {
        return true
      }
    }
  }
  if starts_with_sign(unpositive) {
    return false
  }
  radix_digits_fit(unpositive, 10, u128_max)
}

///|
/// `parse_negative_int` for `i64` and `i128`.
fn parse_negative_int(scalar : String) -> Bool {
  for prefix in [("-0x", 16), ("-0o", 8), ("-0b", 2)] {
    if scalar.has_prefix(prefix.0) &&
      radix_digits_fit(scalar[3:], prefix.1, i128_min_magnitude) {
      return true
    }
  }
  // `i128::from_str_radix(scalar, 10)`
  if scalar.has_prefix("-") {
    radix_digits_fit(scalar[1:], 10, i128_min_magnitude)
  } else if scalar.has_prefix("+") {
    radix_digits_fit(scalar[1:], 10, i128_max)
  } else {
    radix_digits_fit(scalar[:], 10, i128_max)
  }
}

///|
/// serde_yaml's `parse_f64`: the YAML spellings of infinity and NaN, or a
/// finite number in Rust's `f64` syntax.
fn parse_f64(scalar : String) -> Bool {
  let unpositive = if scalar.has_prefix("+") {
    let rest = scalar[1:]
    if starts_with_sign(rest) {
      return false
    }
    rest
  } else {
    scalar[:]
  }
  match unpositive {
    ".inf" | ".Inf" | ".INF" => return true
    _ => ()
  }
  match scalar {
    "-.inf" | "-.Inf" | "-.INF" | ".nan" | ".NaN" | ".NAN" => return true
    _ => ()
  }
  rust_f64_is_finite(unpositive)
}

///|
/// `str::parse::<f64>()` succeeds with a finite value. Rust's grammar is
/// `[+-]? (digits [. digits?] | . digits) ([eE] [+-]? digits)?`; its
/// `inf`/`nan` spellings are never finite.
fn rust_f64_is_finite(s : StringView) -> Bool {
  let body = if starts_with_sign(s) { s[1:] } else { s }
  let cs : Array[Char] = body.iter().collect()
  let n = cs.length()
  let is_digit = (i : Int) => i < n && cs[i] >= '0' && cs[i] <= '9'
  let mut i = 0
  let mut mantissa_digits = 0
  let mut nonzero = false
  while is_digit(i) {
    nonzero = nonzero || cs[i] != '0'
    i += 1
    mantissa_digits += 1
  }
  if i < n && cs[i] == '.' {
    i += 1
    while is_digit(i) {
      nonzero = nonzero || cs[i] != '0'
      i += 1
      mantissa_digits += 1
    }
  }
  if mantissa_digits == 0 {
    return false
  }
  if i < n && (cs[i] == 'e' || cs[i] == 'E') {
    i += 1
    if i < n && (cs[i] == '+' || cs[i] == '-') {
      i += 1
    }
    let exponent_start = i
    while is_digit(i) {
      i += 1
    }
    if i == exponent_start {
      return false
    }
  }
  if i != n {
    return false
  }
  if !nonzero {
    return true
  }
  // Rust rounds correctly; so does `parse_double`.
  let value = @string.parse_double(body) catch { _ => return false }
  !value.is_inf()
}
