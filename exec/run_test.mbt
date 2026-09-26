///|
fn tc(
  cmd : String,
  config? : @config.TestCaseConfig = @config.TestCaseConfig::default_markdown(),
) -> @document.TestCase {
  {
    title: "",
    shell_expression: cmd,
    body: Output([]),
    exit_code: None,
    line_number: 1,
    config,
  }
}

///|
fn ctx() -> @exec.Context {
  {
    work_directory: "/tmp",
    temp_directory: "/tmp",
    file: "t.md",
    config: @config.DocumentConfig::default_markdown(),
  }
}

///|
fn show(o : @exec.Output) -> String {
  "exit=\{o.exit_code.to_string()} out=\{Repr(@text.lossy_string(o.stdout))} err=\{Repr(@text.lossy_string(o.stderr))}"
}

///|
#cfg(all(target="native", not(platform="windows")))
async test "run programs directly" {
  inspect(
    show(@exec.run_testcase(tc("printf 'a b\\n'"), ctx())),
    content="exit=0 out=\"a b\\n\" err=\"\"",
  )
  inspect(
    show(
      @exec.run_testcase(tc("sh -c 'echo out; echo err >&2; exit 3'"), ctx()),
    ),
    content="exit=3 out=\"out\\n\" err=\"err\\n\"",
  )
  let combined = {
    ..@config.TestCaseConfig::default_markdown(),
    output_stream: Some(Combined),
  }
  inspect(
    show(
      @exec.run_testcase(
        tc("sh -c 'echo out; echo err >&2'", config=combined),
        ctx(),
      ),
    ),
    content="exit=0 out=\"out\\nerr\\n\" err=\"\"",
  )
  inspect(
    show(@exec.run_testcase(tc("no-such-program-xyz"), ctx())),
    content="exit=127 out=\"\" err=\"no-such-program-xyz: command not found\\n\"",
  )
  inspect(
    show(@exec.run_testcase(tc("export FOO=1"), ctx())).contains(
      "shell built-in",
    ),
    content="true",
  )
  let with_stdin = {
    ..@config.TestCaseConfig::default_markdown(),
    stdin: Some("piped\n"),
  }
  inspect(
    show(@exec.run_testcase(tc("cat", config=with_stdin), ctx())),
    content="exit=0 out=\"piped\\n\" err=\"\"",
  )
  inspect(
    show(@exec.run_testcase(tc("FOO=bar sh -c 'printf %s \"$FOO\"'"), ctx())),
    content="exit=0 out=\"bar\" err=\"\"",
  )
  let timed = {
    ..@config.TestCaseConfig::default_markdown(),
    timeout: Some(@config.parse_duration("300ms")),
  }
  inspect(
    show(
      @exec.run_testcase(
        tc("sh -c 'echo partial; sleep 5'", config=timed),
        ctx(),
      ),
    ),
    content="exit=timeout[300ms] out=\"partial\\n\" err=\"\"",
  )
  inspect(
    show(@exec.run_testcase(tc("sh -c 'kill -9 $$'"), ctx())),
    content="exit=137 out=\"\" err=\"\"",
  )
  inspect(
    show(@exec.run_testcase(tc("echo $HOME"), ctx())).has_prefix("exit=2"),
    content="true",
  )
}
