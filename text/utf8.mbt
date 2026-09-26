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
  try @utf8.decode(data) catch {
    _ => None
  } noraise {
    s => Some(s)
  }
}

///|
/// Length of the valid UTF-8 sequence starting at `i` (0 if there is none).
fn utf8_sequence_length(data : BytesView, i : Int) -> Int {
  let n = data.length()
  let b0 = data[i].to_int()
  let cont = (k : Int) => i + k < n && (data[i + k].to_int() & 0xC0) == 0x80
  if b0 < 0x80 {
    1
  } else if b0 >= 0xC2 && b0 <= 0xDF {
    if cont(1) {
      2
    } else {
      0
    }
  } else if b0 >= 0xE0 && b0 <= 0xEF {
    guard cont(1) && cont(2) else { return 0 }
    let b1 = data[i + 1].to_int()
    if (b0 == 0xE0 && b1 < 0xA0) || (b0 == 0xED && b1 >= 0xA0) {
      0
    } else {
      3
    }
  } else if b0 >= 0xF0 && b0 <= 0xF4 {
    guard cont(1) && cont(2) && cont(3) else { return 0 }
    let b1 = data[i + 1].to_int()
    if (b0 == 0xF0 && b1 < 0x90) || (b0 == 0xF4 && b1 >= 0x90) {
      0
    } else {
      4
    }
  } else {
    0
  }
}

///|
/// The valid UTF-8 parts of `data` between bytes that are not part of a
/// valid sequence, as (start, text, end) byte positions; parts may be
/// empty.
pub fn utf8_segments(data : BytesView) -> Array[(Int, String, Int)] {
  let out = []
  let mut start = 0
  let mut i = 0
  let close = (from : Int, to : Int) => {
    let text = utf8_string(data[from:to]).unwrap_or("")
    out.push((from, text, to))
  }
  while i < data.length() {
    let len = utf8_sequence_length(data, i)
    if len == 0 {
      close(start, i)
      i += 1
      start = i
    } else {
      i += len
    }
  }
  close(start, data.length())
  out
}
