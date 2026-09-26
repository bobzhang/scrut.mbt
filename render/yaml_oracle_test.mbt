// Checks the YAML emitter against a table generated from serde_yaml
// (scripts/oracle, mode `yaml`).

///|
/// A minimal JSON parser for the table's compact JSON, keeping key order.
priv struct JsonReader {
  chars : Array[Char]
  mut pos : Int
}

///|
fn JsonReader::peek(self : JsonReader) -> Char {
  self.chars[self.pos]
}

///|
fn JsonReader::expect(self : JsonReader, c : Char) -> Unit {
  guard self.peek() == c else { abort("expected \{c} at \{self.pos}") }
  self.pos += 1
}

///|
fn JsonReader::hex4(self : JsonReader) -> Int {
  let mut v = 0
  for _ in 0..<4 {
    let c = self.peek()
    let d = match c {
      '0'..='9' => c.to_int() - '0'.to_int()
      'a'..='f' => c.to_int() - 'a'.to_int() + 10
      'A'..='F' => c.to_int() - 'A'.to_int() + 10
      _ => abort("bad hex digit")
    }
    v = v * 16 + d
    self.pos += 1
  }
  v
}

///|
fn JsonReader::string(self : JsonReader) -> String {
  self.expect('"')
  let buf = StringBuilder()
  for ;; {
    let c = self.peek()
    self.pos += 1
    match c {
      '"' => break
      '\\' => {
        let e = self.peek()
        self.pos += 1
        match e {
          'n' => buf.write_char('\n')
          'r' => buf.write_char('\r')
          't' => buf.write_char('\t')
          'b' => buf.write_char('\u{8}')
          'f' => buf.write_char('\u{c}')
          'u' => {
            let hi = self.hex4()
            if hi >= 0xD800 && hi < 0xDC00 {
              self.expect('\\')
              self.expect('u')
              let lo = self.hex4()
              buf.write_char(
                Int::unsafe_to_char(
                  0x10000 + ((hi - 0xD800) << 10) + (lo - 0xDC00),
                ),
              )
            } else {
              buf.write_char(Int::unsafe_to_char(hi))
            }
          }
          _ => buf.write_char(e)
        }
      }
      _ => buf.write_char(c)
    }
  }
  buf.to_string()
}

///|
fn JsonReader::value(self : JsonReader) -> @text.JsonValue {
  match self.peek() {
    '"' => JString(self.string())
    '[' => {
      self.pos += 1
      let items = []
      if self.peek() == ']' {
        self.pos += 1
        return JArray(items)
      }
      for ;; {
        items.push(self.value())
        if self.peek() == ',' {
          self.pos += 1
        } else {
          self.expect(']')
          break
        }
      }
      JArray(items)
    }
    '{' => {
      self.pos += 1
      let entries = []
      if self.peek() == '}' {
        self.pos += 1
        return JObject(entries)
      }
      for ;; {
        let key = self.string()
        self.expect(':')
        entries.push((key, self.value()))
        if self.peek() == ',' {
          self.pos += 1
        } else {
          self.expect('}')
          break
        }
      }
      JObject(entries)
    }
    't' => {
      self.pos += 4
      JBool(true)
    }
    'f' => {
      self.pos += 5
      JBool(false)
    }
    'n' => {
      self.pos += 4
      JNull
    }
    _ => {
      let start = self.pos
      while self.pos < self.chars.length() &&
            (
              self.peek() is ('-' | '+' | '.' | 'e' | 'E') ||
              (self.peek() >= '0' && self.peek() <= '9')
            ) {
        self.pos += 1
      }
      JNumber(String::from_array(self.chars[start:self.pos]))
    }
  }
}

///|
fn parse_json(s : String) -> @text.JsonValue {
  let reader = { chars: s.iter().collect(), pos: 0, }
  let v = reader.value()
  guard reader.pos == reader.chars.length() else { abort("trailing input") }
  v
}

///|
test "json parser round-trips the table" {
  for case in yaml_cases {
    assert_eq(parse_json(case.0).to_string(), case.0)
  }
}

///|
test "yaml emitter matches serde_yaml" {
  let failures = []
  for case in yaml_cases {
    let (json, want) = case
    let got = @render.json_to_yaml(parse_json(json))
    if got != want {
      failures.push("\{json}:\n want \{want.escape()}\n  got \{got.escape()}")
    }
  }
  if !failures.is_empty() {
    fail(
      "\{failures.length()} of \{yaml_cases.length()} differ:\n" +
      failures[:failures.length().min(20)].to_owned().join("\n"),
    )
  }
}

///|
test "empty outcome list" {
  assert_eq(@render.render_yaml([]), "[]\n")
}
