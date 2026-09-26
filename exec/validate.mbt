// Validating output against a test case (upstream TestCase::validate and
// src/interpolation.rs).

///|
pub(all) enum TestCaseError {
  /// Output did not match the expectations.
  MalformedOutput(@diff.Diff)
  /// JSON Schema validation failed: (kind, errors).
  JsonSchemaFailed(String, Array[String])
  InvalidExitCode(actual~ : Int, expected~ : Int)
  InternalError(String)
  Timeout
  Skipped
}

///|
/// Replace `$VAR`, `${VAR}` and `$$` (unknown variables are kept).
pub fn interpolate_str(text : String, env : Array[(String, String)]) -> String {
  let lookup = (name : String) => {
    for e in env {
      if e.0 == name {
        return Some(e.1)
      }
    }
    None
  }
  let chars = text.to_array()
  let buf = StringBuilder()
  let mut i = 0
  let alnum = (c : Char) => {
    (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9')
  }
  while i < chars.length() {
    let c = chars[i]
    if c == '$' && i + 1 < chars.length() {
      let d = chars[i + 1]
      if d == '$' {
        buf.write_char('$')
        i += 2
        continue
      }
      if d == '{' {
        let mut j = i + 2
        while j < chars.length() && alnum(chars[j]) {
          j += 1
        }
        if j > i + 2 && j < chars.length() && chars[j] == '}' {
          let name = String::from_array(chars[i + 2:j])
          match lookup(name) {
            Some(v) => buf.write_string(v)
            None => buf.write_string(String::from_array(chars[i:j + 1]))
          }
          i = j + 1
          continue
        }
      }
      let mut j = i + 1
      while j < chars.length() && (alnum(chars[j]) || chars[j] == '_') {
        j += 1
      }
      if j > i + 1 {
        let name = String::from_array(chars[i + 1:j])
        match lookup(name) {
          Some(v) => buf.write_string(v)
          None => buf.write_string(String::from_array(chars[i:j]))
        }
        i = j
        continue
      }
    }
    buf.write_char(c)
    i += 1
  }
  buf.to_string()
}

///|
fn interpolate_expectation(
  e : @rules.Expectation,
  env : Array[(String, String)],
) -> @rules.Expectation raise @rules.RuleError {
  let (kind, bytes, optional, multiline) = e.unmake()
  let expression = @text.lossy_string(bytes)
  let interpolated = interpolate_str(expression, env)
  if interpolated == expression {
    return e
  }
  @rules.ExpectationMaker::new().make(
    kind,
    interpolated,
    optional,
    multiline,
    e.original,
  )
}

///|
/// Output with the test case's transformations: CRLF to LF (unless
/// `keep_crlf`), ANSI escapes removed (with `strip_ansi_escaping`).
pub fn render_output(
  config : @config.TestCaseConfig,
  output : BytesView,
) -> Bytes {
  let processed = if config.keep_crlf is Some(true) {
    output.to_owned()
  } else {
    @text.replace_crlf(output)
  }
  if config.strip_ansi_escaping is Some(true) {
    @text.strip_ansi(processed)
  } else {
    processed
  }
}

///|
/// Whether the output satisfies the test case: exit code first, then the
/// output expectations.
pub fn validate(
  tc : @document.TestCase,
  output : Output,
) -> Result[Unit, TestCaseError] {
  if output.exit_code is Code(code) {
    let expected = tc.exit_code.unwrap_or(0)
    if code != expected {
      return Err(InvalidExitCode(actual=code, expected~))
    }
  }
  let stream = if tc.config.output_stream is Some(Stderr) {
    output.stderr
  } else {
    output.stdout
  }
  match tc.body {
    Output(expectations) => {
      let expectations = if tc.config.interpolated is Some(true) {
        try
          expectations.map(e => interpolate_expectation(e, output.env))
        catch {
          e => return Err(InternalError(e.to_string()))
        } noraise {
          es => es
        }
      } else {
        expectations
      }
      let diff = @diff.diff(expectations, stream)
      if diff.has_differences() {
        Err(MalformedOutput(diff))
      } else {
        Ok(())
      }
    }
    JsonSchema(_) =>
      Err(
        JsonSchemaFailed("InvalidSchema", [
          "JSON Schema validation is not supported yet",
        ]),
      )
  }
}
