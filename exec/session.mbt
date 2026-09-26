// Running a document's test cases in order (upstream
// executors/stateful_executor.rs).

///|
pub(all) enum ExecutionResult {
  /// One output per test case.
  Completed(Array[Output])
  /// A test case exited with the skip code: the whole document is skipped.
  SkippedAt(Int)
  /// Execution stopped at a timeout (per test case, or the document's total).
  TimedOut(index~ : Int, total~ : Bool, outputs~ : Array[Output])
  /// A `fail_fast` test case failed.
  FailedAt(index~ : Int, outputs~ : Array[Output])
}

///|
let default_total_timeout : @config.Duration = @config.Duration::from_secs(
  @config.default_document_timeout_secs,
)

///|
async fn wait_for(wait : @config.Wait, temp_directory : String) -> Unit {
  match wait.path {
    None => @async.sleep(wait.timeout.as_millis().to_int())
    Some(path) => {
      let full = join_path(temp_directory, path)
      let end = @async.now() + wait.timeout.as_millis()
      while @async.now() < end {
        let exists = @fs.exists(full) catch { _ => false }
        if exists {
          return
        }
        @async.sleep(50)
      }
    }
  }
}

///|
/// Run the test cases of one document (prepended and appended ones
/// included) with upstream's semantics: the first skip code skips the
/// document, a timeout stops execution, `fail_fast` stops at a failure.
/// Detached processes are signalled when the document is done.
pub async fn execute_document(
  testcases : Array[@document.TestCase],
  context : Context,
) -> ExecutionResult {
  let total_timeout = context.config.total_timeout.unwrap_or(default_total_timeout)
  let timeout_at = if total_timeout == @config.Duration::zero() {
    None
  } else {
    Some(@async.now() + total_timeout.as_millis())
  }
  let outputs : Array[Output] = []
  let result = @async.with_task_group(group => {
    for index, testcase in testcases {
      let mut config = testcase.config.with_defaults_from(context.config.defaults)
      // The test case's own timeout wins over the remaining total (upstream
      // orders timeouts by `is_global` first).
      let left = timeout_at.map(at => {
        @config.Duration::from_millis((at - @async.now()).max(0L))
      })
      let (is_global, timeout) : (Bool, @config.Duration?) = match (config.timeout, left) {
        (Some(t), _) => (false, Some(t))
        (None, Some(l)) => (true, Some(l))
        (None, None) => (false, None)
      }
      if config.wait is Some(w) {
        wait_for(w, context.temp_directory)
      }
      config = { ..config, timeout, }
      config = config.with_environment([
        ("SCRUT_TEST", "\{context.file}:\{testcase.line_number}"),
      ])
      let tc = { ..testcase, config, }
      let output = if config.detached is Some(true) {
        run_detached(group, tc, context)
      } else {
        run_testcase(tc, context)
      }
      match output.exit_code {
        Code(code) => {
          if code == config.skip_document_code_or_default() {
            return SkippedAt(index)
          }
          outputs.push(output)
          if config.fail_fast is Some(true) && validate(tc, output) is Err(_) {
            return FailedAt(index~, outputs~)
          }
        }
        Timeout(_) =>
          if is_global {
            outputs.push({ ..output, exit_code: Timeout(total_timeout) })
            return TimedOut(index~, total=true, outputs~)
          } else {
            outputs.push(output)
            return TimedOut(index~, total=false, outputs~)
          }
        Skipped => return SkippedAt(index)
        Detached => outputs.push(Output::new(Detached))
        Unknown => {
          outputs.push(output)
          while outputs.length() < testcases.length() {
            outputs.push(Output::new(Unknown))
          }
          break
        }
      }
    }
    Completed(outputs)
  }) catch {
    e => Completed(outputs + [{ ..Output::new(Unknown), stderr: @text.to_bytes(e.to_string()) }])
  }
  result
}
