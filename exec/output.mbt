// Execution results (upstream src/output.rs).

///|
pub(all) enum ExitStatus {
  Code(Int)
  Timeout(@config.Duration)
  Skipped
  Detached
  Unknown
} derive(Eq, Debug)

///|
pub fn ExitStatus::to_string(self : ExitStatus) -> String {
  match self {
    Code(c) => c.to_string()
    Timeout(d) => "timeout[\{d.as_millis()}ms]"
    Skipped => "skipped"
    Detached => "detached"
    Unknown => "unknown"
  }
}

///|
pub fn ExitStatus::as_code(self : ExitStatus) -> Int {
  match self {
    Code(c) => c
    Skipped => @config.default_skip_document_code
    Timeout(_) => -1
    Detached => -100
    Unknown => -255
  }
}

///|
/// The result of running one test case.
pub(all) struct Output {
  stdout : Bytes
  stderr : Bytes
  exit_code : ExitStatus
  /// The environment the program ran with (for interpolation).
  env : Array[(String, String)]
  duration_ms : Int64?
} derive(Debug)

///|
pub fn Output::new(exit_code : ExitStatus) -> Output {
  { stdout: b"", stderr: b"", exit_code, env: [], duration_ms: None, }
}

///|
/// Output lines as expectations, each prefixed (upstream
/// `OutputStream::to_output_string`).
pub fn output_string(
  bytes : BytesView,
  prefix : String,
  escaper : @text.Escaper,
) -> String {
  let buf = StringBuilder()
  let lines = @text.split_at_newline(bytes)
  let ends_in_newline = @text.ends_in_newline(bytes)
  for idx, line in lines {
    let expectation = escaper.escaped_expectation(line)
    let suffix = if !ends_in_newline &&
      !expectation.has_suffix(" (escaped)") &&
      idx + 1 == lines.length() {
      " (no-eol)"
    } else {
      ""
    }
    buf.write_string("\{prefix}\{expectation}\{suffix}\n")
  }
  buf.to_string()
}

///|
/// `## STDOUT` / `## STDERR` blocks for error messages.
pub fn Output::to_error_string(
  self : Output,
  escaper : @text.Escaper,
) -> String {
  "## STDOUT\n" +
  output_string(self.stdout, "#> ", escaper) +
  "## STDERR\n" +
  output_string(self.stderr, "#> ", escaper)
}
