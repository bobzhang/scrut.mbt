// Durations as in the `humantime` 2.4 crate: parsing (`10s`, `1m 30s`,
// `1.5h`) and formatting (`1m 30s`).

///|
/// A non-negative duration.
pub struct Duration {
  secs : UInt64
  nanos : Int
} derive(Eq, Compare, Debug)

///|
pub fn Duration::zero() -> Duration {
  { secs: 0, nanos: 0, }
}

///|
pub fn Duration::from_secs(secs : UInt64) -> Duration {
  { secs, nanos: 0, }
}

///|
/// Milliseconds, saturating.
pub fn Duration::as_millis(self : Duration) -> Int64 {
  let max = 9223372036854775807UL
  if self.secs > max / 1000 {
    return 9223372036854775807L
  }
  (self.secs * 1000 + (self.nanos / 1_000_000).to_uint64()).reinterpret_as_int64()
}

///|
/// A duration parsing error (humantime's messages).
pub(all) suberror DurationError {
  DurationError(String)
} derive(Debug)

///|
pub impl Show for DurationError with fn output(self, logger) {
  let DurationError(msg) = self
  logger.write_string(msg)
}

///|
let overflow_message : String = "number is too large or cannot be represented without a lack of precision (values below 1ns are not supported)"

///|
fn checked_mul(a : UInt64, b : UInt64) -> UInt64 raise DurationError {
  if a != 0 && b > 18446744073709551615UL / a {
    raise DurationError(overflow_message)
  }
  a * b
}

///|
fn checked_add(a : UInt64, b : UInt64) -> UInt64 raise DurationError {
  if a > 18446744073709551615UL - b {
    raise DurationError(overflow_message)
  }
  a + b
}

///|
fn exact_div(a : UInt64, b : UInt64) -> UInt64 raise DurationError {
  if a % b != 0 {
    raise DurationError(overflow_message)
  }
  a / b
}

///|
/// Unicode `White_Space` (Rust's `char::is_whitespace`).
fn is_space(c : Char) -> Bool {
  match c.to_int() {
    0x09..=0x0D
    | 0x20
    | 0x85
    | 0xA0
    | 0x1680
    | 0x2000..=0x200A
    | 0x2028
    | 0x2029
    | 0x202F
    | 0x205F
    | 0x3000 => true
    _ => false
  }
}

///|
fn is_unit_char(c : Char) -> Bool {
  (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || c == 'µ'
}

///|
/// The (seconds, nanoseconds) multiplier of a unit.
fn unit_scale(unit : String) -> (UInt64, UInt64)? {
  match unit {
    "nanos" | "nsec" | "ns" => Some((0, 1))
    "usec" | "us" | "µs" => Some((0, 1000))
    "millis" | "msec" | "ms" => Some((0, 1_000_000))
    "seconds" | "second" | "secs" | "sec" | "s" => Some((1, 0))
    "minutes" | "minute" | "min" | "mins" | "m" => Some((60, 0))
    "hours" | "hour" | "hr" | "hrs" | "h" => Some((3600, 0))
    "days" | "day" | "d" => Some((86400, 0))
    "weeks" | "week" | "wk" | "wks" | "w" => Some((86400 * 7, 0))
    "months" | "month" | "M" => Some((2_630_016, 0))
    "years" | "year" | "yr" | "yrs" | "y" => Some((31_557_600, 0))
    _ => None
  }
}

///|
/// `humantime::parse_duration`.
pub fn parse_duration(s : String) -> Duration raise DurationError {
  if s == "0" {
    return Duration::zero()
  }
  let chars = s.to_array()
  // Byte offsets (humantime reports them in error messages).
  let offsets = Array::make(chars.length() + 1, 0)
  for i, c in chars {
    let w = if c.to_int() < 0x80 {
      1
    } else if c.to_int() < 0x800 {
      2
    } else if c.to_int() < 0x10000 {
      3
    } else {
      4
    }
    offsets[i + 1] = offsets[i] + w
  }
  let mut pos = 0
  let mut secs : UInt64 = 0
  let mut nanos : UInt64 = 0
  let add_current = (sec : UInt64, nsec : UInt64) => {
    let mut sec = sec
    let mut nsec = checked_add(nanos, nsec)
    if nsec > 1_000_000_000 {
      sec = checked_add(sec, nsec / 1_000_000_000)
      nsec = nsec % 1_000_000_000
    }
    secs = checked_add(secs, sec)
    // `Duration::new` carries whole seconds.
    secs = checked_add(secs, nsec / 1_000_000_000)
    nanos = nsec % 1_000_000_000
  }
  let parse_first_char = () => {
    let off = offsets[pos]
    while pos < chars.length() {
      let c = chars[pos]
      pos += 1
      if c >= '0' && c <= '9' {
        return Some((c.to_int() - '0'.to_int()).to_uint64())
      } else if is_space(c) {
        continue
      } else {
        raise DurationError("expected number at \{off}")
      }
    }
    None
  }
  let parse_unit = (
    n : UInt64,
    frac : (UInt64, UInt64)?,
    start : Int,
    end : Int,
  ) => {
    let unit = String::from_array(chars[start:end])
    guard unit_scale(unit) is Some((sec_scale, nsec_scale)) else {
      if unit.is_empty() {
        raise DurationError("time unit needed, for example \{n}sec or \{n}ms")
      }
      raise DurationError(
        "unknown time unit \{Repr(unit)}, supported units: ns, us/µs, ms, sec, min, hours, days, weeks, months, years (and few variations)",
      )
    }
    add_current(checked_mul(n, sec_scale), checked_mul(n, nsec_scale))
    if frac is Some((num, den)) {
      let (fs, fns) = match unit_scale(unit) {
        Some((0, 1)) => raise DurationError(overflow_message)
        Some((0, 1000)) => (0UL, exact_div(checked_mul(num, 1000), den))
        Some((0, 1_000_000)) =>
          (0UL, exact_div(checked_mul(num, 1_000_000), den))
        Some((1, 0)) => (0UL, exact_div(checked_mul(num, 1_000_000_000), den))
        Some((60, 0)) => (0UL, exact_div(checked_mul(num, 60_000_000_000), den))
        Some((scale, _)) => (exact_div(checked_mul(num, scale), den), 0UL)
        None => (0UL, 0UL)
      }
      add_current(fs, fns)
    }
  }
  let mut n = match parse_first_char() {
    Some(n) => n
    None => raise DurationError("value was empty")
  }
  while true {
    let mut frac : (UInt64, UInt64)? = None
    let mut off = pos
    let mut stopped = false
    while pos < chars.length() {
      let c = chars[pos]
      pos += 1
      if c >= '0' && c <= '9' {
        n = checked_add(
          checked_mul(n, 10),
          (c.to_int() - '0'.to_int()).to_uint64(),
        )
      } else if is_space(c) {
        ()
      } else if is_unit_char(c) {
        stopped = true
        break
      } else if c == '.' {
        // The fractional part.
        let mut num : UInt64 = 0
        let mut den : UInt64 = 1
        let mut zeros = true
        // Errors before the first fractional digit point at the `.`.
        let mut frac_off = pos - 1
        while pos < chars.length() {
          let d = chars[pos]
          pos += 1
          if d == '0' {
            den = checked_mul(den, 10)
            if !zeros {
              num = checked_mul(num, 10)
            }
          } else if d >= '1' && d <= '9' {
            zeros = false
            den = checked_mul(den, 10)
            num = checked_add(
              checked_mul(num, 10),
              (d.to_int() - '0'.to_int()).to_uint64(),
            )
          } else if is_space(d) {
            ()
          } else if is_unit_char(d) {
            break
          } else {
            raise DurationError("invalid character at \{offsets[frac_off]}")
          }
          frac_off = pos
        }
        if den == 1 {
          raise DurationError("invalid character at \{offsets[frac_off]}")
        }
        frac = Some((num, den))
        off = frac_off
        stopped = true
        break
      } else {
        raise DurationError("invalid character at \{offsets[off]}")
      }
      off = pos
    }
    ignore(stopped)
    // The unit starts at the character that ended the number.
    let start = off
    let mut unit_end = pos
    let mut next_number = false
    while pos < chars.length() {
      let c = chars[pos]
      pos += 1
      if c >= '0' && c <= '9' {
        parse_unit(n, frac, start, unit_end)
        n = (c.to_int() - '0'.to_int()).to_uint64()
        next_number = true
        break
      } else if is_space(c) {
        break
      } else if is_unit_char(c) {
        ()
      } else {
        raise DurationError("invalid character at \{offsets[unit_end]}")
      }
      unit_end = pos
    }
    if next_number {
      continue
    }
    parse_unit(n, frac, start, unit_end)
    match parse_first_char() {
      Some(v) => n = v
      None => break
    }
  }
  { secs, nanos: nanos.to_int(), }
}

///|
/// `humantime::format_duration`.
pub fn Duration::to_string(self : Duration) -> String {
  if self.secs == 0 && self.nanos == 0 {
    return "0s"
  }
  let secs = self.secs
  let years = secs / 31_557_600
  let ydays = secs % 31_557_600
  let months = ydays / 2_630_016
  let mdays = ydays % 2_630_016
  let days = mdays / 86400
  let day_secs = mdays % 86400
  let hours = day_secs / 3600
  let minutes = day_secs % 3600 / 60
  let seconds = day_secs % 60
  let millis = self.nanos / 1_000_000
  let micros = self.nanos / 1000 % 1000
  let nanosec = self.nanos % 1000
  let parts = []
  let plural = (name : String, v : UInt64) => {
    if v > 0 {
      parts.push("\{v}\{name}\{if v > 1 { "s" } else { "" }}")
    }
  }
  let item = (name : String, v : UInt64) => {
    if v > 0 {
      parts.push("\{v}\{name}")
    }
  }
  plural("year", years)
  plural("month", months)
  plural("day", days)
  item("h", hours)
  item("m", minutes)
  item("s", seconds)
  item("ms", millis.to_uint64())
  item("us", micros.to_uint64())
  item("ns", nanosec.to_uint64())
  parts.join(" ")
}

///|
pub impl Show for Duration with fn output(self, logger) {
  logger.write_string(self.to_string())
}
