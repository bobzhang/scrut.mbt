///|
/// The class a pattern compiles to, if it is a single class.
fn compiled_class(pattern : String) -> CharSet? raise RuleError {
  for hir = compile_rust_regex(pattern) {
    match hir {
      HSet(set) => break Some(set)
      HConcat([h]) | HGroup(h) => continue h
      _ => break None
    }
  }
}

///|
fn parse_hex(s : StringView) -> Int {
  s.fold(init=0, (acc, c) => {
    acc * 16 +
    (if c >= 'a' {
      c.to_int() - 'a'.to_int() + 10
    } else {
      c.to_int() - '0'.to_int()
    })
  })
}

///|
test "classes match the regex crate" {
  let failures = []
  let mut unsupported = 0
  let mut samples = 0
  for case in class_cases {
    let (pattern, members, others) = case
    let set = try compiled_class(pattern) catch {
      e => {
        if members == "ERR" {
          continue
        }
        if Show::to_string(e).contains("not supported") {
          unsupported += 1
          continue
        }
        failures.push("\{pattern}: \{e}")
        continue
      }
    } noraise {
      Some(set) => set
      None => {
        failures.push("\{pattern}: not a single class")
        continue
      }
    }
    if members == "ERR" {
      failures.push("\{pattern}: want an error")
      continue
    }
    // The class itself, and the whole pattern through the core engine.
    let regex = @string.Regex(translate_rust_regex("^(?:" + pattern + ")$"))
    for list in [(members, true), (others, false)] {
      let (hexes, want) = list
      for h in hexes.split(" ") {
        if h == "" {
          continue
        }
        samples += 1
        let c = parse_hex(h)
        let text = c.unsafe_to_char().to_string()
        if set.contains(c) != want || (regex.execute(text) is Some(_)) != want {
          failures.push("\{pattern} on U+\{h}: want \{want}")
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
    "classes: \{class_cases.length()} patterns, \{samples} samples, \{unsupported} unsupported",
  )
}
