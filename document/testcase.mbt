// Test cases (upstream src/testcase.rs, src/validation.rs).

///|
/// What a test case validates.
pub(all) enum ValidationBody {
  /// Output expectations.
  Output(Array[@rules.Expectation])
  /// A YAML JSON Schema the output must satisfy.
  JsonSchema(String)
}

///|
pub(all) struct TestCase {
  title : String
  /// The command (with continuation lines joined by `\n`).
  shell_expression : String
  body : ValidationBody
  exit_code : Int?
  /// Line of the `$` command in the document (1-based).
  line_number : Int
  config : @config.TestCaseConfig
}

///|
pub fn TestCase::expectations(self : TestCase) -> Array[@rules.Expectation] {
  match self.body {
    Output(e) => e
    JsonSchema(_) => []
  }
}

///|
/// Number of lines of the shell expression.
pub fn TestCase::shell_expression_lines(self : TestCase) -> Int {
  let mut n = 1
  for c in self.shell_expression {
    if c == '\n' {
      n += 1
    }
  }
  n
}

///|
/// Upstream's `Display` of a test case: sorted-key JSON.
pub fn TestCase::to_json(self : TestCase) -> @text.JsonValue {
  let expectations = self
    .expectations()
    .map(e => @text.JString(e.to_expression_string(@text.Escaper::Unicode)))
  @text.JObject([
    ("title", JString(self.title)),
    ("shell_expression", JString(self.shell_expression)),
    ("expectations", JArray(expectations)),
    ("exit_code", JNumber(self.exit_code.unwrap_or(0).to_string())),
    ("line_number", JNumber(self.line_number.to_string())),
    ("config", self.config.to_json()),
  ]).sorted()
}

///|
/// A parsed test document.
pub(all) struct Document {
  config : @config.DocumentConfig
  testcases : Array[TestCase]
}

///|
/// A document that cannot be parsed.
pub(all) suberror ParseError {
  ParseError(String)
} derive(Debug)

///|
pub impl Show for ParseError with fn output(self, logger) {
  let ParseError(msg) = self
  logger.write_string(msg)
}

///|
/// Rust's `str::lines`: split at `\n`, dropping a `\r` before it; no empty
/// line after a final line feed.
pub fn rust_lines(text : String) -> Array[String] {
  let lines = []
  let mut start = 0
  let n = text.length()
  for i in 0..<n {
    if text.code_unit_at(i) == '\n'.to_int().to_uint16() {
      let end = if i > start &&
        text.code_unit_at(i - 1) == '\r'.to_int().to_uint16() {
        i - 1
      } else {
        i
      }
      lines.push(text[start:end].to_owned())
      start = i + 1
    }
  }
  if start < n {
    lines.push(text[start:].to_owned())
  }
  lines
}
