// Rendering output with non-printable characters escaped
// (upstream src/escaping.rs).

///|
/// How non-printable output is escaped.
pub(all) enum Escaper {
  /// All non-ASCII and all non-printable ASCII characters are escaped.
  Ascii
  /// All non-printable Unicode characters are escaped.
  Unicode
} derive(Eq, Debug)

///|
/// Unicode general category C (control, format, private use), per the
/// `unicode_categories` crate upstream uses (`char::is_other`).
pub fn is_other(c : Char) -> Bool {
  let cp = c.to_int()
  let mut lo = 0
  let mut hi = other_ranges.length()
  while lo < hi {
    let mid = (lo + hi) / 2
    let (a, b) = other_ranges[mid]
    if cp < a {
      hi = mid
    } else if cp > b {
      lo = mid + 1
    } else {
      return true
    }
  }
  false
}

///|
/// The bytes with every non-printable character escaped.
pub fn Escaper::escaped_printable(self : Escaper, raw : BytesView) -> String {
  match self {
    Ascii => escaped_printable_ascii(raw)
    Unicode => escaped_printable_unicode(raw)
  }
}

///|
/// A line of output as an expectation: escaped and marked ` (escaped)` when
/// it contains non-printable characters, as is otherwise.
pub fn Escaper::escaped_expectation(self : Escaper, raw : BytesView) -> String {
  let line = trim_newlines(raw)
  let escaped = self.escaped_printable(line)
  let encoded = lossy_string(line)
  if encoded == escaped {
    encoded
  } else {
    "\{escaped} (escaped)"
  }
}

///|
/// Whether the bytes contain characters that would be escaped.
pub fn Escaper::has_unprintable(self : Escaper, raw : BytesView) -> Bool {
  match self {
    Ascii => has_unprintable_ascii(raw)
    Unicode =>
      match utf8_string(raw) {
        Some(s) => s.iter().any(is_other)
        None => true
      }
  }
}

///|
fn has_unprintable_ascii(bytes : BytesView) -> Bool {
  bytes.iter().any(b => !(b >= b'\x20' && b <= b'\x7e'))
}

///|
fn escaped_printable_ascii(bytes : BytesView) -> String {
  if !has_unprintable_ascii(bytes) {
    return lossy_string(bytes)
  }
  let buf = StringBuilder()
  for b in bytes {
    match b {
      b'\n' => buf.write_string("\\n")
      b'\r' => buf.write_string("\\r")
      b'\t' => buf.write_string("\\t")
      b'\x07' => buf.write_string("\\a")
      b'\x08' => buf.write_string("\\b")
      b'\x0c' => buf.write_string("\\f")
      b'\x0b' => buf.write_string("\\v")
      b'\\' => buf.write_string("\\\\")
      _ =>
        if b >= b'\x20' && b <= b'\x7e' {
          buf.write_char(b.to_char())
        } else {
          buf.write_string("\\x")
          let v = b.to_int()
          buf.write_char(hex_digit(v >> 4))
          buf.write_char(hex_digit(v & 15))
        }
    }
  }
  buf.to_string()
}

///|
fn hex_digit(v : Int) -> Char {
  if v < 10 {
    Int::unsafe_to_char(0x30 + v)
  } else {
    Int::unsafe_to_char(0x61 + v - 10)
  }
}

///|
fn escaped_printable_unicode(bytes : BytesView) -> String {
  guard utf8_string(bytes) is Some(s) else {
    return escaped_printable_ascii(bytes)
  }
  let buf = StringBuilder()
  for c in s {
    if is_other(c) {
      buf.write_string(escaped_printable_ascii(to_bytes(c.to_string())))
    } else {
      buf.write_char(c)
    }
  }
  buf.to_string()
}

///|
/// Like `escaped_expectation`, but an `(escaped)` expectation always reads
/// back as the line: upstream's Unicode escaper leaves backslashes as they
/// are when it escapes other characters, which makes such expectations
/// ambiguous. Used where expectations are written (`scrut update`).
pub fn Escaper::exact_expectation(self : Escaper, raw : BytesView) -> String {
  let expectation = self.escaped_expectation(raw)
  guard self is Unicode &&
    expectation.has_suffix(" (escaped)") &&
    utf8_string(trim_newlines(raw)) is Some(s) &&
    s.contains("\\") else {
    return expectation
  }
  let buf = StringBuilder()
  for c in s {
    if c == '\\' {
      buf.write_string("\\\\")
    } else if is_other(c) {
      buf.write_string(escaped_printable_ascii(to_bytes(c.to_string())))
    } else {
      buf.write_char(c)
    }
  }
  "\{buf} (escaped)"
}

///|
/// An `(escaped)` expectation for a line that cannot be written any other
/// way: printable characters are kept (per the escaper), backslashes
/// doubled, the first character hex-escaped (so the line cannot look like a
/// command, continuation or exit code), and trailing whitespace and a
/// trailing `)` too (so no rule suffix can be read from the expression).
pub fn Escaper::forced_expectation(self : Escaper, raw : BytesView) -> String {
  let line = trim_newlines(raw)
  let buf = StringBuilder()
  let text = match (self, utf8_string(line)) {
    (Unicode, Some(s)) => Some(s)
    _ => None
  }
  // Characters from here on are hex-escaped when they are whitespace or `)`.
  let tail_start = (items : Array[Int]) => {
    let mut k = items.length()
    while k > 0 &&
          (
            items[k - 1] == ' '.to_int() ||
            items[k - 1] == '\t'.to_int() ||
            items[k - 1] == ')'.to_int()
          ) {
      k -= 1
    }
    k
  }
  match text {
    Some(s) => {
      let chars = s.to_array()
      let tail = tail_start(chars.map(c => c.to_int()))
      for i, c in chars {
        if i == 0 ||
          i >= tail ||
          is_other(c) ||
          c.to_int() < 0x20 ||
          c.to_int() == 0x7f {
          for b in to_bytes(c.to_string()) {
            write_hex_byte(buf, b)
          }
        } else if c == '\\' {
          buf.write_string("\\\\")
        } else {
          buf.write_char(c)
        }
      }
    }
    None => {
      let tail = tail_start(line.iter().map(b => b.to_int()).collect())
      for i, b in line {
        if i == 0 || i >= tail || b < b'\x20' || b > b'\x7e' {
          write_hex_byte(buf, b)
        } else if b == b'\\' {
          buf.write_string("\\\\")
        } else {
          buf.write_char(b.to_char())
        }
      }
    }
  }
  "\{buf} (escaped)"
}

///|
fn write_hex_byte(buf : StringBuilder, b : Byte) -> Unit {
  let v = b.to_int()
  buf.write_string("\\x")
  buf.write_char(hex_digit(v >> 4))
  buf.write_char(hex_digit(v & 15))
}
