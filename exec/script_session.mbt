// Running a Cram document (or any document with `--cram-compat`) with the
// semantics of upstream's executors/bash_script_executor.rs. Upstream runs
// all commands in one bash script; scrut still runs each program on its
// own, but keeps what is observable: the configuration must be the same
// for all test cases, there is only a total timeout, `fail_fast` and
// `strip_ansi_escaping` do not apply and no environment is captured for
// interpolation.

///|
/// Execution could not start or its results could not be assigned.
pub(all) suberror ExecutionError {
  ExecutionError(String)
} derive(Debug)

///|
pub impl Show for ExecutionError with fn output(self, logger) {
  let ExecutionError(msg) = self
  logger.write_string(msg)
}

///|
fn failed_at(index : Int, message : String) -> ExecutionError {
  ExecutionError("error in execution with index=\{index}: \{message}")
}

///|
/// The configuration shared by all test cases (upstream
/// `compile_testcase`): every value must be the same where set.
fn compile_config(
  testcases : Array[@document.TestCase],
) -> @config.TestCaseConfig raise ExecutionError {
  let mut config = @config.TestCaseConfig::empty()
  for index, tc in testcases {
    let c = tc.config
    fn consistent(name : String, same : Bool) raise ExecutionError {
      if !same {
        raise failed_at(index, "inconsistent configuration value for \{name}")
      }
    }

    if config.detached is None {
      config = { ..config, detached: c.detached, }
    } else {
      consistent("detached", config.detached == c.detached)
    }
    if config.keep_crlf is None {
      config = { ..config, keep_crlf: c.keep_crlf, }
    } else {
      consistent("keep_crlf", config.keep_crlf == c.keep_crlf)
    }
    if config.output_stream is None {
      config = { ..config, output_stream: c.output_stream, }
    } else {
      consistent("output_stream", config.output_stream == c.output_stream)
    }
    if config.skip_document_code is None {
      config = { ..config, skip_document_code: c.skip_document_code, }
    } else {
      consistent(
        "skip_document_code",
        config.skip_document_code == c.skip_document_code,
      )
    }
    if config.wait is None {
      config = { ..config, wait: c.wait, }
    } else {
      consistent("wait", config.wait == c.wait)
    }
    if !config.environment.is_empty() && config.environment != c.environment {
      raise failed_at(index, "inconsistent value for environment")
    }
    config = { ..config, environment: c.environment, }
  }
  for index, tc in testcases {
    if tc.config.timeout is Some(_) {
      raise failed_at(
        index, "timeout per execution not supported in bash-script execution",
      )
    }
  }
  config
}

///|
/// Output lines joined the way upstream reassembles a timed out script's
/// output (`remove_dividers_from_output`): each line keeps its newline and
/// lines are joined with another one.
fn script_output(parts : Array[Bytes]) -> Bytes {
  let lines : Array[Bytes] = []
  for i, part in parts {
    let part_lines = @text.split_at_newline(part)
    for j, line in part_lines {
      // Upstream's divider follows each completed output and ends its last
      // line (the divider text itself is left out here).
      if i + 1 < parts.length() &&
        j + 1 == part_lines.length() &&
        !@text.ends_in_newline(line) {
        lines.push(@text.assure_newline(line))
      } else {
        lines.push(line.to_owned())
      }
    }
  }
  let buf = Buffer()
  for i, line in lines {
    if i > 0 {
      buf.write_bytes(b"\n")
    }
    buf.write_bytes(line)
  }
  buf.to_bytes()
}

///|
/// Run a document's test cases like a Cram script.
pub async fn execute_script(
  testcases : Array[@document.TestCase],
  context : Context,
) -> ExecutionResult {
  let shared = compile_config(testcases)
  if shared.detached is Some(true) {
    // Upstream runs the whole script detached and finds no results.
    raise ExecutionError(
      "aborted executions with exit code=detached: expected \{testcases.length()} execution result(s) but found 0\n" +
      Output::new(Detached).to_error_string(Unicode) +
      "\n",
    )
  }
  let total_timeout = context.config.total_timeout.unwrap_or(
    default_total_timeout,
  )
  let timeout_at = if total_timeout == @config.Duration::zero() {
    None
  } else {
    Some(@async.now() + total_timeout.as_millis())
  }
  let skip_code = shared.skip_document_code_or_default()
  let outputs : Array[Output] = []
  for index, testcase in testcases {
    let timeout = timeout_at.map(at => {
      @config.Duration::from_millis((at - @async.now()).max(0L))
    })
    let config = {
      ..testcase.config,
      detached: None,
      keep_crlf: shared.keep_crlf,
      output_stream: shared.output_stream,
      environment: shared.environment,
      strip_ansi_escaping: None,
      timeout,
    }
    let output = run_testcase({ ..testcase, config, }, context)
    match output.exit_code {
      Timeout(_) => {
        let parts_out = outputs.map(o => o.stdout)
        parts_out.push(output.stdout)
        let parts_err = outputs.map(o => o.stderr)
        parts_err.push(output.stderr)
        return TimedOut(index=0, total=true, outputs=[
          {
            stdout: script_output(parts_out),
            stderr: script_output(parts_err),
            exit_code: Timeout(total_timeout),
            env: [],
            duration_ms: None,
          },
        ])
      }
      Code(code) => {
        if code == skip_code {
          return SkippedAt(index)
        }
        outputs.push({ ..output, env: [], duration_ms: None, })
      }
      _ => outputs.push({ ..output, env: [], duration_ms: None, })
    }
  }
  Completed(outputs)
}
