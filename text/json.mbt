// JSON values written exactly like serde_json's compact and pretty
// serializers (keys in the given order).

///|
pub(all) enum JsonValue {
  JNull
  JBool(Bool)
  /// A number, already formatted.
  JNumber(String)
  JString(String)
  JArray(Array[JsonValue])
  JObject(Array[(String, JsonValue)])
} derive(Eq, Debug)

///|
/// A JSON string literal (serde_json's escaping).
pub fn json_quote(s : String) -> String {
  let buf = StringBuilder()
  write_json_string(buf, s)
  buf.to_string()
}

///|
fn write_json_string(buf : StringBuilder, s : String) -> Unit {
  buf.write_char('"')
  for c in s {
    match c {
      '"' => buf.write_string("\\\"")
      '\\' => buf.write_string("\\\\")
      '\n' => buf.write_string("\\n")
      '\r' => buf.write_string("\\r")
      '\t' => buf.write_string("\\t")
      '\u{08}' => buf.write_string("\\b")
      '\u{0c}' => buf.write_string("\\f")
      _ =>
        if c.to_int() < 0x20 {
          let v = c.to_int()
          buf.write_string("\\u00")
          buf.write_char(hex_digit(v >> 4))
          buf.write_char(hex_digit(v & 15))
        } else {
          buf.write_char(c)
        }
    }
  }
  buf.write_char('"')
}

///|
/// Compact JSON (`serde_json::to_string`).
pub fn JsonValue::to_string(self : JsonValue) -> String {
  let buf = StringBuilder()
  fn go(v : JsonValue) -> Unit {
    match v {
      JNull => buf.write_string("null")
      JBool(b) => buf.write_string(if b { "true" } else { "false" })
      JNumber(n) => buf.write_string(n)
      JString(s) => write_json_string(buf, s)
      JArray(xs) => {
        buf.write_char('[')
        for i, x in xs {
          if i > 0 {
            buf.write_char(',')
          }
          go(x)
        }
        buf.write_char(']')
      }
      JObject(entries) => {
        buf.write_char('{')
        for i, e in entries {
          if i > 0 {
            buf.write_char(',')
          }
          write_json_string(buf, e.0)
          buf.write_char(':')
          go(e.1)
        }
        buf.write_char('}')
      }
    }
  }
  go(self)
  buf.to_string()
}

///|
/// Pretty JSON (`serde_json::to_string_pretty`, two-space indent).
pub fn JsonValue::to_string_pretty(self : JsonValue) -> String {
  let buf = StringBuilder()
  fn indent(n : Int) -> Unit {
    for _ in 0..<n {
      buf.write_string("  ")
    }
  }
  fn go(v : JsonValue, depth : Int) -> Unit {
    match v {
      JArray([]) => buf.write_string("[]")
      JObject([]) => buf.write_string("{}")
      JArray(xs) => {
        buf.write_string("[\n")
        for i, x in xs {
          if i > 0 {
            buf.write_string(",\n")
          }
          indent(depth + 1)
          go(x, depth + 1)
        }
        buf.write_char('\n')
        indent(depth)
        buf.write_char(']')
      }
      JObject(entries) => {
        buf.write_string("{\n")
        for i, e in entries {
          if i > 0 {
            buf.write_string(",\n")
          }
          indent(depth + 1)
          write_json_string(buf, e.0)
          buf.write_string(": ")
          go(e.1, depth + 1)
        }
        buf.write_char('\n')
        indent(depth)
        buf.write_char('}')
      }
      _ => buf.write_string(v.to_string())
    }
  }
  go(self, 0)
  buf.to_string()
}

///|
/// The object with its keys sorted (a serde_json `Map` without
/// `preserve_order`), recursively.
pub fn JsonValue::sorted(self : JsonValue) -> JsonValue {
  match self {
    JArray(xs) => JArray(xs.map(x => x.sorted()))
    JObject(entries) => {
      let sorted = entries.map(e => (e.0, e.1.sorted()))
      sorted.sort_by((a, b) => compare_utf8(a.0, b.0))
      JObject(sorted)
    }
    _ => self
  }
}

///|
/// Compare strings by their UTF-8 bytes (Rust's `String` order).
pub fn compare_utf8(a : String, b : String) -> Int {
  let x = to_bytes(a)
  let y = to_bytes(b)
  let n = x.length().min(y.length())
  for i in 0..<n {
    if x[i] != y[i] {
      return x[i].compare(y[i])
    }
  }
  x.length().compare(y.length())
}
