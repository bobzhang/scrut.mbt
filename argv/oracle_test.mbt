///|
test "accepted commands split like bash" {
  let failures = []
  let mut accepted = 0
  for c in argv_cases {
    let (cmd, bash) = c
    let ours = try @argv.tokenize(cmd, env=argv_env) catch {
      _ => continue
    } noraise {
      w => w
    }
    accepted += 1
    match bash {
      Some(words) =>
        if words != ours {
          failures.push("\{Repr(cmd)}: bash \{Repr(words)}, ours \{Repr(ours)}")
        }
      None => failures.push("\{Repr(cmd)}: bash fails, ours \{Repr(ours)}")
    }
  }
  if failures.length() > 0 {
    fail(
      "\{failures.length()} differ:\n" +
      failures[:failures.length().min(20)].join("\n"),
    )
  }
  inspect(accepted > 1000, content="true")
}
