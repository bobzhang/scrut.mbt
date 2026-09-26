///|
fn unhex(s : String) -> Bytes {
  let chars = s.to_array()
  let out = Buffer()
  let digit = (c : Char) => {
    if c >= 'a' {
      c.to_int() - 'a'.to_int() + 10
    } else {
      c.to_int() - '0'.to_int()
    }
  }
  for i = 0; i + 1 < chars.length(); i = i + 2 {
    out.write_byte((digit(chars[i]) * 16 + digit(chars[i + 1])).to_byte())
  }
  out.to_bytes()
}

///|
fn hex(b : BytesView) -> String {
  let digits = "0123456789abcdef".to_array()
  let buf = StringBuilder()
  for x in b {
    buf.write_char(digits[x.to_int() >> 4])
    buf.write_char(digits[x.to_int() & 15])
  }
  buf.to_string()
}

///|
test "expectations match upstream" {
  let failures = []
  let mut regex_unsupported = 0
  for c in rule_cases {
    let (cram, line, want, matches) = c
    let maker = @rules.ExpectationMaker::new(cram_compat=cram)
    let got = try maker.parse(line) catch {
      e => {
        if want != "ERR" && e.to_string().contains("not supported") {
          regex_unsupported += 1
          continue
        }
        if want != "ERR" {
          failures.push("\{line}: want \{want}, got error \{e}")
        }
        continue
      }
    } noraise {
      e => e
    }
    if want == "ERR" {
      failures.push("\{line}: want an error, got \{got}")
      continue
    }
    let (kind, expr, optional, multiline) = got.unmake()
    let result = "\{kind}|\{hex(expr)}|\{optional}|\{multiline}|\{got.original}|\{got.to_expression_string(@text.Escaper::Ascii)}|\{got.to_expression_string(@text.Escaper::Unicode)}"
    if result != want {
      failures.push("\{line}:\n  want \{want}\n  got  \{result}")
      continue
    }
    for m in matches {
      let (output, expected) = m
      if got.matches(unhex(output)) != expected {
        failures.push("\{line} on \{output}: want \{expected}")
      }
    }
  }
  if failures.length() > 0 {
    fail(
      "\{failures.length()} differ (\{regex_unsupported} unsupported regex):\n" +
      failures[:failures.length().min(15)].join("\n"),
    )
  }
  println("unsupported regex constructs: \{regex_unsupported}")
}
