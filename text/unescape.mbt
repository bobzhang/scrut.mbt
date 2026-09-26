// Resolving escape sequences in `(escaped)` expressions
// (upstream src/rules/escaped_filter.rs).

///|
/// An error in an escaped expression.
pub(all) suberror EscapeError {
  EscapeError(String)
} derive(Debug)

///|
pub impl Show for EscapeError with fn output(self, logger) {
  let EscapeError(msg) = self
  logger.write_string(msg)
}

///|
/// The expression without a trailing ` (escaped)` / ` (esc)` marker (also in
/// its regex-escaped spelling), or `None` without one.
pub fn expression_as_escaped(expression : String) -> String? {
  for sequence in [" (escaped)", " \\(escaped\\)", " (esc)", " \\(esc\\)"] {
    if expression.has_suffix(sequence) {
      return Some(
        expression[:expression.length() - sequence.length()].to_owned(),
      )
    }
  }
  None
}

///|
/// Resolve `\a \b \e \f \r \t \v` into their characters; other escapes are
/// kept.
pub fn unescape_tabs(escaped : String) -> String {
  let buf = StringBuilder()
  let chars = escaped.to_array()
  let mut i = 0
  while i < chars.length() {
    let c = chars[i]
    i += 1
    if c == '\\' && i < chars.length() {
      let c2 = chars[i]
      i += 1
      match c2 {
        'a' => buf.write_char('\u{07}')
        'b' => buf.write_char('\u{08}')
        'e' => buf.write_char('\u{1b}')
        'f' => buf.write_char('\u{0c}')
        'r' => buf.write_char('\r')
        't' => buf.write_char('\t')
        'v' => buf.write_char('\u{0b}')
        _ => {
          buf.write_char('\\')
          buf.write_char(c2)
        }
      }
      continue
    }
    buf.write_char(c)
  }
  buf.to_string()
}

///|
/// Rust's `u8::from_str_radix` on a two-character string.
fn byte_from_str_radix(s : String, radix : Int) -> Int? {
  let chars = s.to_array()
  let digits = if chars.length() > 0 && chars[0] == '+' {
    chars[1:]
  } else {
    chars[:]
  }
  if digits.length() == 0 {
    return None
  }
  let mut v = 0
  for c in digits {
    let d = if c >= '0' && c <= '9' {
      c.to_int() - '0'.to_int()
    } else if c >= 'a' && c <= 'z' {
      c.to_int() - 'a'.to_int() + 10
    } else if c >= 'A' && c <= 'Z' {
      c.to_int() - 'A'.to_int() + 10
    } else {
      return None
    }
    if d >= radix {
      return None
    }
    v = v * radix + d
    if v > 255 {
      return None
    }
  }
  Some(v)
}

///|
/// The bytes of an expression with `\0oo` (octal) and `\xhh` (hex) escapes
/// resolved; `\\` is a backslash, other escapes are kept verbatim.
fn resolve_escape_sequences_to_bytes(
  escaped : String,
) -> Bytes raise EscapeError {
  let chars = escaped.to_array()
  let out = Buffer()
  let mut i = 0
  let sequence = () => {
    if i >= chars.length() {
      raise EscapeError("missing first character in escape sequence")
    }
    if i + 1 >= chars.length() {
      raise EscapeError("missing second character in escape sequence")
    }
    let s = String::from_array([chars[i], chars[i + 1]])
    i += 2
    s
  }
  while i < chars.length() {
    let c = chars[i]
    i += 1
    if c != '\\' {
      out.write_bytes(to_bytes(c.to_string()))
      continue
    }
    if i >= chars.length() {
      raise EscapeError("unused tailing escape")
    }
    let c2 = chars[i]
    i += 1
    match c2 {
      '0' => {
        let octal = sequence()
        match byte_from_str_radix(octal, 8) {
          Some(v) => out.write_byte(v.to_byte())
          None => raise EscapeError("octal from `\{octal}`")
        }
      }
      'x' => {
        let hex = sequence()
        match byte_from_str_radix(hex, 16) {
          Some(v) => out.write_byte(v.to_byte())
          None => raise EscapeError("hex from `\{hex}`")
        }
      }
      '\\' => out.write_byte(b'\\')
      _ => {
        // Rust's `char as u8` keeps the low byte.
        out.write_byte(b'\\')
        out.write_byte((c2.to_int() & 0xFF).to_byte())
      }
    }
  }
  out.to_bytes()
}

///|
/// The raw bytes an escaped expression stands for.
pub fn apply_escaped_filter_bytes(
  expression : String,
) -> Bytes raise EscapeError {
  resolve_escape_sequences_to_bytes(unescape_tabs(expression)) catch {
    EscapeError(msg) =>
      raise EscapeError(
        "resolve escape sequences from escaped expression: \{msg}",
      )
  }
}

///|
/// Like `apply_escaped_filter_bytes`, decoded as UTF-8.
pub fn apply_escaped_filter_utf8(
  expression : String,
) -> String raise EscapeError {
  let bytes = apply_escaped_filter_bytes(expression)
  match utf8_string(bytes) {
    Some(s) => s
    None => raise EscapeError("encode escaped expression to utf-8")
  }
}
