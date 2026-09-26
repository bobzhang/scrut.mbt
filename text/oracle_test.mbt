///|
fn unhex(s : String) -> Bytes {
  let chars = s.to_array()
  let out = Buffer()
  let digit = (c : Char) => if c >= 'a' {
    c.to_int() - 'a'.to_int() + 10
  } else {
    c.to_int() - '0'.to_int()
  }
  for i = 0; i + 1 < chars.length(); i = i + 2 {
    out.write_byte((digit(chars[i]) * 16 + digit(chars[i + 1])).to_byte())
  }
  out.to_bytes()
}

///|
fn hex(b : BytesView) -> String {
  let buf = StringBuilder()
  for x in b {
    let v = x.to_int()
    buf.write_string("0123456789abcdef"[v >> 4:(v >> 4) + 1].to_owned())
    buf.write_string("0123456789abcdef"[v & 15:(v & 15) + 1].to_owned())
  }
  buf.to_string()
}

///|
test "escaping matches upstream" {
  let failures = []
  for c in escape_cases {
    let (input, pa, pu, ea, eu, ha, hu) = c
    let b = unhex(input)
    let got = (
      @text.Escaper::Ascii.escaped_printable(b),
      @text.Escaper::Unicode.escaped_printable(b),
      @text.Escaper::Ascii.escaped_expectation(b),
      @text.Escaper::Unicode.escaped_expectation(b),
      @text.Escaper::Ascii.has_unprintable(b),
      @text.Escaper::Unicode.has_unprintable(b),
    )
    if got != (pa, pu, ea, eu, ha, hu) {
      failures.push("\{input}: want \{(pa, pu, ea, eu, ha, hu)}, got \{got}")
    }
  }
  if failures.length() > 0 {
    fail("\{failures.length()} differ:\n" + failures[:failures.length().min(10)].join("\n"))
  }
}

///|
test "ANSI stripping matches upstream" {
  let failures = []
  for c in strip_cases {
    let (input, want) = c
    let got = hex(@text.strip_ansi(unhex(input)))
    if got != want {
      failures.push("\{input}: want \{want}, got \{got}")
    }
  }
  if failures.length() > 0 {
    fail("\{failures.length()} differ:\n" + failures[:failures.length().min(10)].join("\n"))
  }
}
