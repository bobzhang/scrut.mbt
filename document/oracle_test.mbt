///|
fn render(doc : @document.Document) -> String {
  let parts = [doc.config.to_json().to_string()]
  for t in doc.testcases {
    parts.push(t.to_json().to_string())
  }
  parts.join("\n")
}

///|
test "parsers match upstream" {
  let failures = []
  for c in parse_cases {
    let (cram, doc, want) = c
    if want == "PANIC" {
      continue
    }
    let got = render(
      if cram {
        @document.parse_cram(doc)
      } else {
        @document.parse_markdown(doc)
      },
    ) catch {
      _ => "ERR"
    }
    if got != want {
      failures.push(
        "---- document:\n\{doc}\n---- want:\n\{want}\n---- got:\n\{got}",
      )
    }
  }
  if failures.length() > 0 {
    fail(
      "\{failures.length()} differ:\n" +
      failures[:failures.length().min(4)].join("\n"),
    )
  }
}
