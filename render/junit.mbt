// JUnit XML reports (upstream src/renderers/junit.rs, written like the
// `quick-xml` writer with two-space indentation).

///|
/// An XML writer with `quick-xml`'s indentation rules: every tag starts a
/// new indented line, except the end tag right after text content.
priv struct XmlWriter {
  buf : StringBuilder
  mut depth : Int
  mut line_break : Bool
}

///|
fn XmlWriter::new() -> XmlWriter {
  { buf: StringBuilder(), depth: 0, line_break: false, }
}

///|
fn xml_escape(text : String, attribute : Bool) -> String {
  let buf = StringBuilder()
  for c in text {
    match c {
      '<' => buf.write_string("&lt;")
      '>' => buf.write_string("&gt;")
      '&' => buf.write_string("&amp;")
      '\'' => buf.write_string("&apos;")
      '"' => buf.write_string("&quot;")
      '\r' => buf.write_string("&#13;")
      '\n' if attribute => buf.write_string("&#10;")
      '\t' if attribute => buf.write_string("&#9;")
      _ => buf.write_char(c)
    }
  }
  buf.to_string()
}

///|
fn XmlWriter::wrapped(self : XmlWriter, text : String) -> Unit {
  if self.line_break {
    self.buf.write_char('\n')
    self.buf.write_string(" ".repeat(self.depth * 2))
  }
  self.buf.write_string(text)
  self.line_break = true
}

///|
fn tag(name : String, attributes : Array[(String, String)]) -> String {
  let buf = StringBuilder()
  buf.write_string(name)
  for a in attributes {
    buf.write_string(" \{a.0}=\"\{xml_escape(a.1, true)}\"")
  }
  buf.to_string()
}

///|
fn XmlWriter::start(
  self : XmlWriter,
  name : String,
  attributes : Array[(String, String)],
) -> Unit {
  self.wrapped("<" + tag(name, attributes) + ">")
  self.depth += 1
}

///|
fn XmlWriter::end(self : XmlWriter, name : String) -> Unit {
  self.depth -= 1
  self.wrapped("</\{name}>")
}

///|
fn XmlWriter::empty(
  self : XmlWriter,
  name : String,
  attributes : Array[(String, String)],
) -> Unit {
  self.wrapped("<" + tag(name, attributes) + "/>")
}

///|
fn XmlWriter::text_element(
  self : XmlWriter,
  name : String,
  attributes : Array[(String, String)],
  text : String,
) -> Unit {
  self.start(name, attributes)
  self.buf.write_string(xml_escape(text, false))
  self.line_break = false
  self.end(name)
}

///|
priv enum Status {
  Success
  SkippedCase(String)
  Failure(String, String, String)
  Error(String, String, String)
}

///|
priv struct Case {
  mut name : String
  classname : String
  line_number : Int
  duration_ms : Int64?
  status : Status
  system_out : String
  system_err : String
}

///|
priv struct Suite {
  name : String
  package : String?
  properties : Array[(String, String)]
  testcases : Array[Case]
}

///|
/// Seconds with three decimals (upstream `{:.3}` of the duration).
fn seconds(ms : Int64) -> String {
  let frac = (ms % 1000L).to_string()
  "\{ms / 1000L}." + "0".repeat(3 - frac.length()) + frac
}

///|
fn counts(cases : Array[Case]) -> Array[(String, String)] {
  let mut failures = 0
  let mut errors = 0
  let mut skipped = 0
  let mut time = 0L
  for case in cases {
    time += case.duration_ms.unwrap_or(0L)
    match case.status {
      Success => ()
      SkippedCase(_) => skipped += 1
      Failure(_) => failures += 1
      Error(_) => errors += 1
    }
  }
  [
    ("tests", cases.length().to_string()),
    ("failures", failures.to_string()),
    ("errors", errors.to_string()),
    ("skipped", skipped.to_string()),
    ("time", seconds(time)),
  ]
}

///|
fn is_legal_xml_char(c : Char) -> Bool {
  match c.to_int() {
    0x09 | 0x0A | 0x0D => true
    0x20..=0xD7FF | 0xE000..=0xFFFD | 0x10000..=0x10FFFF => true
    _ => false
  }
}

///|
/// Text that is valid XML character data: escaped line by line, with
/// characters XML forbids hex-escaped.
fn printable(text : BytesView, escaping : @text.Escaper) -> String {
  let escaped = @text.split_at_newline(text)
    .map(line => escaping.escaped_printable(@text.trim_newlines(line)))
    .join("\n")
  if escaped.iter().all(is_legal_xml_char) {
    return escaped
  }
  let buf = StringBuilder()
  for c in escaped {
    if is_legal_xml_char(c) {
      buf.write_char(c)
    } else {
      buf.write_string(
        @text.Escaper::Ascii.escaped_printable(@text.to_bytes(c.to_string())),
      )
    }
  }
  buf.to_string()
}

///|
fn attribute_text(text : String, escaping : @text.Escaper) -> String {
  printable(@text.to_bytes(text), escaping).replace_all(old="\n", new=" ")
}

///|
/// Path components for a lexical prefix comparison.
fn components(path : String) -> Array[String] {
  let out = []
  if path.has_prefix("/") {
    out.push("/")
  }
  for i, part in path.split("/").collect() {
    let part = part.to_owned()
    if part.is_empty() || (part == "." && i > 0) {
      continue
    }
    out.push(part)
  }
  out
}

///|
/// A document location relative to the base directory when it lies under
/// it (upstream `report_path`).
fn report_path(location : String, base : String?) -> String {
  guard base is Some(base) else { return location }
  let loc = components(location)
  let prefix = components(base)
  if prefix.length() > loc.length() {
    return location
  }
  for i, p in prefix {
    if loc[i] != p {
      return location
    }
  }
  loc[prefix.length():].to_owned().join("/")
}

///|
fn package_of(location : String) -> String? {
  match location.rev_find("/") {
    Some(i) if i > 0 => Some(location[:i].to_owned())
    _ => None
  }
}

///|
fn report_line(outcome : Outcome) -> Int {
  let line_number = outcome.testcase.line_number
  guard outcome.result is Err(MalformedOutput(diff)) else { return line_number }
  for line in diff.lines {
    if line is UnmatchedExpectation(index~, ..) {
      return line_number + outcome.testcase.shell_expression_lines() + index
    }
  }
  line_number
}

///|
/// Rust's `str::trim_end`.
fn trim_end(s : String) -> String {
  let chars = s.to_array()
  let mut end = chars.length()
  while end > 0 && is_whitespace(chars[end - 1]) {
    end -= 1
  }
  String::from_array(chars[:end])
}

///|
fn to_status(outcome : Outcome, styled : Bool) -> Status {
  guard outcome.result is Err(err) else { return Success }
  let (kind, message) = match err {
    MalformedOutput(_) =>
      ("malformed_output", "output does not match expectations")
    JsonSchemaFailed("InvalidSchema", _) =>
      ("json_schema_invalid_schema", "JSON Schema definition is invalid")
    JsonSchemaFailed("InvalidJson", _) =>
      ("json_schema_invalid_json", "output is not valid JSON")
    JsonSchemaFailed(_) =>
      (
        "json_schema_validation_errors", "output does not conform to JSON Schema",
      )
    InvalidExitCode(actual~, expected~) =>
      (
        "invalid_exit_code",
        "unexpected exit code: expected \{expected}, but got \{actual}",
      )
    Timeout => ("timeout", "execution timed out")
    InternalError(msg) => ("internal_error", msg)
    Skipped => return SkippedCase("test case was not executed")
  }
  let detail = render_pretty(
    PrettyRenderer::new(summarize=false),
    [outcome],
    styled~,
  )
  let detail = printable(@text.to_bytes(trim_end(detail)), outcome.escaping)
  let message = attribute_text(message, outcome.escaping)
  match err {
    Timeout | InternalError(_) => Error(kind, message, detail)
    _ => Failure(kind, message, detail)
  }
}

///|
/// Outcomes as a JUnit XML report, one `<testsuite>` per document.
/// `base_directory` makes document paths relative, `timestamp` (local time
/// as `YYYY-MM-DDTHH:MM:SS`) stamps every suite and `styled` is passed on
/// to the pretty renderer that renders failure details.
pub fn render_junit(
  outcomes : Array[Outcome],
  base_directory? : String,
  timestamp? : String,
  styled? : Bool = false,
) -> String {
  let suites : Array[Suite] = []
  for outcome in outcomes {
    let location = match outcome.location {
      Some(l) => report_path(l, base_directory)
      None => "<unknown>"
    }
    let name = attribute_text(location, outcome.escaping)
    let case : Case = {
      name: if outcome.testcase.title.is_empty() {
        "line \{outcome.testcase.line_number}"
      } else {
        attribute_text(outcome.testcase.title, outcome.escaping)
      },
      classname: name,
      line_number: report_line(outcome),
      duration_ms: outcome.output.duration_ms,
      status: to_status(outcome, styled),
      system_out: printable(outcome.output.stdout, outcome.escaping),
      system_err: printable(outcome.output.stderr, outcome.escaping),
    }
    match suites.search_by(s => s.name == name) {
      Some(i) => suites[i].testcases.push(case)
      None =>
        suites.push({
          name,
          package: package_of(name),
          properties: [("scrut.format", outcome.format.to_string())],
          testcases: [case],
        })
    }
  }
  for suite in suites {
    let taken : Set[String] = Set::new()
    for case in suite.testcases {
      if !taken.contains(case.name) {
        taken.add(case.name)
        continue
      }
      let mut counter = 2
      while taken.contains("\{case.name} #\{counter}") {
        counter += 1
      }
      case.name = "\{case.name} #\{counter}"
      taken.add(case.name)
    }
  }
  let w = XmlWriter::new()
  w.wrapped("<?xml version=\"1.0\" encoding=\"UTF-8\"?>")
  let all_cases = []
  for suite in suites {
    all_cases.append(suite.testcases)
  }
  w.start("testsuites", counts(all_cases))
  for suite in suites {
    let attrs = [("name", suite.name)]
    if suite.package is Some(p) {
      attrs.push(("package", p))
    }
    if timestamp is Some(t) {
      attrs.push(("timestamp", t))
    }
    attrs.append(counts(suite.testcases))
    w.start("testsuite", attrs)
    if !suite.properties.is_empty() {
      w.start("properties", [])
      for p in suite.properties {
        w.empty("property", [("name", p.0), ("value", p.1)])
      }
      w.end("properties")
    }
    for case in suite.testcases {
      let attrs = [
        ("name", case.name),
        ("classname", case.classname),
        ("file", case.classname),
        ("line", case.line_number.to_string()),
      ]
      if case.duration_ms is Some(ms) {
        attrs.push(("time", seconds(ms)))
      }
      let has_body = !(case.status is Success) ||
        !case.system_out.is_empty() ||
        !case.system_err.is_empty()
      if !has_body {
        w.empty("testcase", attrs)
        continue
      }
      w.start("testcase", attrs)
      match case.status {
        Success => ()
        SkippedCase(message) => w.empty("skipped", [("message", message)])
        Failure(kind, message, detail) =>
          w.text_element(
            "failure",
            [("type", kind), ("message", message)],
            detail,
          )
        Error(kind, message, detail) =>
          w.text_element(
            "error",
            [("type", kind), ("message", message)],
            detail,
          )
      }
      if !case.system_out.is_empty() {
        w.text_element("system-out", [], case.system_out)
      }
      if !case.system_err.is_empty() {
        w.text_element("system-err", [], case.system_err)
      }
      w.end("testcase")
    }
    w.end("testsuite")
  }
  w.end("testsuites")
  w.buf.write_char('\n')
  w.buf.to_string()
}
