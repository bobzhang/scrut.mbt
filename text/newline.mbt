// Byte-level newline helpers (upstream src/newline.rs).

///|
/// Whether the bytes end in a line feed.
pub fn ends_in_newline(data : BytesView) -> Bool {
  data.length() > 0 && data[data.length() - 1] == b'\n'
}

///|
/// The bytes without any trailing line feeds.
pub fn trim_newlines(data : BytesView) -> BytesView {
  let mut end = data.length()
  while end > 0 && data[end - 1] == b'\n' {
    end -= 1
  }
  data[0:end]
}

///|
/// The bytes, ending in a line feed.
pub fn assure_newline(data : BytesView) -> Bytes {
  if ends_in_newline(data) {
    data.to_owned()
  } else {
    let buf = Buffer(size_hint=data.length() + 1)
    buf.write_bytesview(data)
    buf.write_byte(b'\n')
    buf.to_bytes()
  }
}

///|
/// A string without any trailing line feeds.
pub fn trim_newlines_str(s : String) -> String {
  let mut t = s
  while t.has_suffix("\n") {
    t = t[:t.length() - 1].to_owned()
  }
  t
}

///|
/// A string, ending in a line feed.
pub fn assure_newline_str(s : String) -> String {
  if s.has_suffix("\n") {
    s
  } else {
    s + "\n"
  }
}

///|
/// Split at line feeds, keeping each line's line feed. A last line without a
/// line feed is kept as is.
pub fn split_at_newline(text : BytesView) -> Array[BytesView] {
  let lines = []
  let mut start = 0
  for i in 0..<text.length() {
    if text[i] == b'\n' {
      lines.push(text[start:i + 1])
      start = i + 1
    }
  }
  if start < text.length() {
    lines.push(text[start:])
  }
  lines
}

///|
/// Replace every CRLF with LF.
pub fn replace_crlf(data : BytesView) -> Bytes {
  let buf = Buffer(size_hint=data.length())
  let n = data.length()
  for i in 0..<n {
    if data[i] == b'\r' && i + 1 < n && data[i + 1] == b'\n' {
      continue
    }
    buf.write_byte(data[i])
  }
  buf.to_bytes()
}
