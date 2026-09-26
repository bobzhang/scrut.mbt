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
test "diff matches upstream" {
  let maker = @rules.ExpectationMaker::new()
  let failures = []
  for c in diff_cases {
    let (exps, output, want) = c
    let expectations = exps.map(e => maker.parse(e))
    let got = @diff.diff(expectations, unhex(output)).debug_string()
    if got != want {
      failures.push("\{exps} on \{output}:\nwant:\n\{want}\ngot:\n\{got}")
    }
  }
  if failures.length() > 0 {
    fail(
      "\{failures.length()} differ:\n" +
      failures[:failures.length().min(5)].join("\n"),
    )
  }
}
