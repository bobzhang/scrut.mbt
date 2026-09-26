// The line-by-line test case parser shared by the Markdown and Cram formats
// (upstream src/parsers/line_parser.rs).

///|
priv enum Position {
  Start
  Config
  PreCommand
  Command
  Body
} derive(Eq)

///|
fn Position::rank(self : Position) -> Int {
  match self {
    Start => 0
    Config => 1
    PreCommand => 2
    Command => 3
    Body => 4
  }
}

///|
priv struct LineParser {
  testcases : Array[TestCase]
  maker : @rules.ExpectationMaker
  mut title : String?
  command_lines : Array[String]
  config_lines : Array[String]
  mut exit_code : Int?
  expectations : Array[@rules.Expectation]
  mut position : Position
  allow_multiple_commands : Bool
  allow_multiline_config : Bool
  mut output_start_index : Int?
  default_config : @config.TestCaseConfig
  mut config : @config.TestCaseConfig?
  mut json_schema_mode : Bool
  json_schema_lines : Array[String]
}

///|
fn LineParser::new(
  maker : @rules.ExpectationMaker,
  default_config : @config.TestCaseConfig,
  allow_multiple_commands~ : Bool,
  allow_multiline_config~ : Bool,
) -> LineParser {
  {
    testcases: [],
    maker,
    title: None,
    command_lines: [],
    config_lines: [],
    exit_code: None,
    expectations: [],
    position: Start,
    allow_multiple_commands,
    allow_multiline_config,
    output_start_index: None,
    default_config,
    config: None,
    json_schema_mode: false,
    json_schema_lines: [],
  }
}

///|
/// Lines starting with `#` are comments.
pub fn is_comment(line : String) -> Bool {
  line.has_prefix("#")
}

///|
/// `[<digits>]`, as an exit code (`None` if it does not fit an i32).
pub fn extract_exit_code(line : String) -> Int? {
  guard line.has_prefix("[") && line.has_suffix("]") && line.length() > 2 else {
    return None
  }
  let digits = line[1:line.length() - 1]
  let mut v = 0L
  for c in digits {
    guard c >= '0' && c <= '9' else { return None }
    v = v * 10L + (c.to_int() - '0'.to_int()).to_int64()
    if v > 2147483647L {
      return None
    }
  }
  Some(v.to_int())
}

///|
fn parse_config_yaml(text : String) -> @config.TestCaseConfig raise ParseError {
  let yaml = @config.parse_yaml(text) catch {
    e => raise ParseError(e.to_string())
  }
  @config.test_case_config_from_yaml(yaml) catch {
    e => raise ParseError(e.to_string())
  }
}

///|
fn LineParser::add_testcase_body(
  self : LineParser,
  line : String,
  index : Int,
) -> Unit raise ParseError {
  // Comments before the command.
  if self.position.rank() < Command.rank() && is_comment(line) {
    return
  }
  // Configuration lines before the command.
  if self.allow_multiline_config && self.position.rank() <= Config.rank() {
    if line.has_prefix("% ") {
      self.config_lines.push(line[2:].to_owned())
      self.position = Config
      return
    }
    self.position = PreCommand
  }
  // The start of a command.
  if self.allow_multiple_commands || self.command_lines.is_empty() {
    if line.has_prefix("$ ") {
      if !self.command_lines.is_empty() {
        self.end_testcase(index)
      }
      self.position = Command
      self.detect_json_schema_mode()
      self.output_start_index = Some(index)
      self.command_lines.push(line[2:].to_owned())
      return
    }
  }
  // A continuation of the command.
  if self.position == Command && (line == ">" || line.has_prefix("> ")) {
    self.command_lines.push(if line == ">" { "" } else { line[2:].to_owned() })
    return
  }
  // The body: exit code and output expectations.
  self.position = Body
  if extract_exit_code(line) is Some(code) {
    if self.exit_code is Some(_) {
      raise ParseError("line \{index + 1}: exit code provided multiple times")
    }
    self.exit_code = Some(code)
    return
  }
  if self.json_schema_mode {
    self.json_schema_lines.push(line)
    return
  }
  let expectation = self.maker.parse(line) catch {
    e => raise ParseError("parsing line \{index + 1}: \{e}")
  }
  self.expectations.push(expectation)
}

///|
fn LineParser::detect_json_schema_mode(self : LineParser) -> Unit {
  if self.config is Some(c) && c.is_json_schema() {
    self.json_schema_mode = true
    return
  }
  if !self.config_lines.is_empty() {
    let parsed = try? parse_config_yaml(self.config_lines.join("\n"))
    if parsed is Ok(c) && c.is_json_schema() {
      self.json_schema_mode = true
      return
    }
  }
  if self.default_config.is_json_schema() {
    self.json_schema_mode = true
  }
}

///|
/// Finish the current test case, if it has a command.
fn LineParser::end_testcase(
  self : LineParser,
  line_index : Int,
) -> Unit raise ParseError {
  if self.command_lines.is_empty() {
    if !self.expectations.is_empty() {
      raise ParseError(
        "line \{line_index + 1}: testcase output expectation(s) given, but no shell expression specified. Did you forget to prefix the command with '$'?",
      )
    }
    return
  }
  if !self.config_lines.is_empty() {
    let config = parse_config_yaml(self.config_lines.join("\n")) catch {
      ParseError(msg) => raise ParseError("parse testcase config lines: \{msg}")
    }
    let from = self.config.unwrap_or(self.default_config)
    self.config = Some(config.with_defaults_from(from))
  }
  self.testcases.push({
    title: self.title.unwrap_or(""),
    shell_expression: self.command_lines.join("\n"),
    exit_code: self.exit_code,
    body: if self.json_schema_mode {
      JsonSchema(self.json_schema_lines.join("\n"))
    } else {
      Output(self.expectations.copy())
    },
    line_number: self.output_start_index.unwrap_or(line_index) + 1,
    config: self.config.unwrap_or(self.default_config),
  })
  self.flush()
}

///|
fn LineParser::has_testcase_body(self : LineParser) -> Bool {
  !self.command_lines.is_empty() || !self.expectations.is_empty()
}

///|
fn LineParser::flush(self : LineParser) -> Unit {
  self.title = None
  self.command_lines.clear()
  self.config_lines.clear()
  self.position = Start
  self.expectations.clear()
  self.exit_code = None
  self.output_start_index = None
  self.config = None
  self.json_schema_mode = false
  self.json_schema_lines.clear()
}
