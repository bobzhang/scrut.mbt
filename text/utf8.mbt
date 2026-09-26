///|
/// UTF-8 bytes of a string.
pub fn to_bytes(s : StringView) -> Bytes {
  @utf8.encode(s)
}

///|
/// A string from UTF-8 bytes, replacing invalid sequences with U+FFFD
/// (Rust's `String::from_utf8_lossy`).
pub fn lossy_string(data : BytesView) -> String {
  @utf8.decode_lossy(data)
}

///|
/// A string from bytes that must be valid UTF-8.
pub fn utf8_string(data : BytesView) -> String? {
  @utf8.decode(data) catch {
    _ => None
  } noraise {
    s => Some(s)
  }
}
