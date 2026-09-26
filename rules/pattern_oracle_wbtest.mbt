///|
fn hex_bytes(s : String) -> Bytes {
  let chars = s.to_array()
  Bytes::makei(chars.length() / 2, i => {
    (parse_hex(String::from_array(chars[2 * i:2 * i + 2])) & 0xFF).to_byte()
  })
}

///|
fn core_matches(pattern : String, input : String) -> Bool raise {
  @string.Regex(pattern).execute(input) is Some(_)
}

///|
test "patterns match the regex crate" {
  let failures = []
  let mut unsupported = 0
  let mut known = 0
  let mut samples = 0
  for case in pattern_cases {
    let (pattern, compiles, inputs) = case
    let compiled = (
      translate_rust_regex(pattern),
      translate_rust_regex("^(?:" + pattern + ")$"),
    ) catch {
      e => {
        if !compiles {
          continue
        }
        if Show::to_string(e).contains("not supported") {
          unsupported += 1
          continue
        }
        failures.push("\{pattern}: \{e}")
        continue
      }
    }
    if !compiles {
      failures.push("\{pattern}: want an error")
      continue
    }
    let (search, whole) = compiled
    for i in inputs {
      let (h, want_search, want_whole, ascii_search, ascii_whole) = i
      let input = @text.lossy_string(hex_bytes(h))
      samples += 1
      let got = (core_matches(search, input), core_matches(whole, input))
      if got != (want_search, want_whole) {
        if got == (ascii_search, ascii_whole) {
          // Rust's `\b` is Unicode-aware, the core engine's ASCII.
          known += 1
        } else {
          failures.push(
            "\{pattern} on \{h}: want \{want_search}/\{want_whole}, got \{got.0}/\{got.1}",
          )
        }
      }
    }
  }
  if failures.length() > 0 {
    fail(
      "\{failures.length()} differ:\n" +
      failures[:failures.length().min(20)].join("\n"),
    )
  }
  println(
    "patterns: \{pattern_cases.length()} patterns, \{samples} inputs, \{unsupported} unsupported, \{known} differ by Unicode \\b",
  )
}
