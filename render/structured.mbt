// Machine readable outcomes (upstream src/renderers/structured.rs and the
// `Serialize` implementations it relies on).

///|
fn output_json(output : @exec.Output) -> @text.JsonValue {
  let e : Array[(String, @text.JsonValue)] = [
    ("exit_code", JString(output.exit_code.to_string())),
    ("stdout", JString(@text.lossy_string(output.stdout))),
    ("stderr", JString(@text.lossy_string(output.stderr))),
  ]
  if output.duration_ms is Some(ms) {
    e.push(("duration_ms", JNumber(ms.to_string())))
  }
  JObject(e)
}

///|
fn testcase_json(tc : @document.TestCase) -> @text.JsonValue {
  let e : Array[(String, @text.JsonValue)] = [
    ("title", JString(tc.title)),
    ("shell_expression", JString(tc.shell_expression)),
    (
      "expectations",
      match tc.body {
        Output(expectations) =>
          JArray(expectations.map(x => @text.JString(x.original)))
        JsonSchema(_) => JNull
      },
    ),
    // Upstream always serializes a number (0 when none is expected).
    ("exit_code", JNumber(tc.exit_code.unwrap_or(0).to_string())),
    ("line_number", JNumber(tc.line_number.to_string())),
  ]
  if !tc.config.is_empty() {
    e.push(("config", tc.config.to_json()))
  }
  JObject(e)
}

///|
fn expectation_json(e : @rules.Expectation) -> @text.JsonValue {
  JString(e.original)
}

///|
fn lines_json(lines : Array[(Int, Bytes)]) -> @text.JsonValue {
  JArray(
    lines.map(l => {
      @text.JArray([JNumber(l.0.to_string()), JString(@text.lossy_string(l.1))])
    }),
  )
}

///|
fn diff_line_json(line : @diff.DiffLine) -> @text.JsonValue {
  match line {
    MatchedExpectation(index~, expectation~, lines~) =>
      JObject([
        ("kind", JString("matched_expectation")),
        ("index", JNumber(index.to_string())),
        ("expectation", expectation_json(expectation)),
        ("lines", lines_json(lines)),
      ])
    UnmatchedExpectation(index~, expectation~) =>
      JObject([
        ("kind", JString("unmatched_expectation")),
        ("index", JNumber(index.to_string())),
        ("expectation", expectation_json(expectation)),
      ])
    UnexpectedLines(lines~) =>
      JObject([
        ("kind", JString("unexpected_lines")),
        ("lines", lines_json(lines)),
      ])
  }
}

///|
fn error_json(err : @exec.TestCaseError, outcome : Outcome) -> @text.JsonValue {
  match err {
    MalformedOutput(diff) =>
      JObject([
        ("kind", JString("malformed_output")),
        ("diff", JArray(diff.lines.map(diff_line_json))),
      ])
    JsonSchemaFailed(kind, errors) =>
      JObject([
        (
          "kind",
          JString(
            match kind {
              "InvalidSchema" => "json_schema_invalid_schema"
              "InvalidJson" => "json_schema_invalid_json"
              _ => "json_schema_validation_errors"
            },
          ),
        ),
        ("errors", JArray(errors.map(x => @text.JString(x)))),
        ("output", JString(@text.lossy_string(outcome.output.stdout))),
      ])
    InvalidExitCode(actual~, expected~) =>
      JObject([
        ("kind", JString("invalid_exit_code")),
        ("actual", JNumber(actual.to_string())),
        ("expected", JNumber(expected.to_string())),
      ])
    InternalError(msg) =>
      JObject([("kind", JString("internal_error")), ("error", JString(msg))])
    Timeout => JObject([("kind", JString("timeout"))])
    Skipped => JObject([("kind", JString("skipped"))])
  }
}

///|
/// An outcome as upstream serializes it.
pub fn Outcome::to_json(self : Outcome) -> @text.JsonValue {
  let e : Array[(String, @text.JsonValue)] = []
  if self.location is Some(location) {
    e.push(("location", JString(location)))
  }
  match self.result {
    Err(err) => {
      e.push(("output", output_json(self.output)))
      e.push(("testcase", testcase_json(self.testcase)))
      e.push(("result", error_json(err, self)))
    }
    Ok(_) => {
      e.push(("title", JString(self.testcase.title)))
      e.push(("result", JObject([("kind", JString("success"))])))
    }
  }
  JObject(e)
}

///|
/// All outcomes as compact JSON (upstream `JsonRenderer`).
pub fn render_json(outcomes : Array[Outcome]) -> String {
  @text.JArray(outcomes.map(o => o.to_json())).to_string()
}
