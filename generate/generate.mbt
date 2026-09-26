// Writing test documents from outcomes: updated expectations for existing
// documents and new documents (upstream src/generators/).

///|
pub(all) suberror GenerateError {
  GenerateError(Array[String])
} derive(Debug)

///|
fn message(msg : String) -> GenerateError {
  GenerateError([msg])
}

///|
fn GenerateError::context(self : GenerateError, msg : String) -> GenerateError {
  let GenerateError(messages) = self
  GenerateError([msg, ..messages])
}

///|
fn assure_newline(s : String) -> String {
  if s.has_suffix("\n") {
    s
  } else {
    s + "\n"
  }
}

///|
/// `$ command` with `> ` continuation lines.
fn testcase_expression(outcome : @render.Outcome) -> String {
  let lines = @text.split_at_newline(
    @text.to_bytes(outcome.testcase.shell_expression),
  )
  let buf = StringBuilder()
  for i, line in lines {
    buf.write_string(if i == 0 { "$ " } else { "> " })
    buf.write_string(@text.lossy_string(@text.assure_newline(line)))
  }
  buf.to_string()
}

///|
fn testcase_exit_code(outcome : @render.Outcome) -> String? {
  match outcome.output.exit_code {
    Code(code) if code != 0 => Some("[\{code}]\n")
    _ => None
  }
}

///|
/// A test case's command and expectations that match its output (upstream
/// `Outcome::generate_testcase`).
pub fn generate_testcase(
  outcome : @render.Outcome,
) -> String raise GenerateError {
  let generated = StringBuilder()
  generated.write_string(testcase_expression(outcome))
  match outcome.result {
    Ok(_) => {
      for e in outcome.testcase.expectations() {
        generated.write_string(assure_newline(e.original))
      }
      if testcase_exit_code(outcome) is Some(code) {
        generated.write_string(code)
      }
    }
    Err(MalformedOutput(diff)) => {
      for line in diff.lines {
        match line {
          MatchedExpectation(expectation~, ..) =>
            generated.write_string(assure_newline(expectation.original))
          UnexpectedLines(lines~) =>
            for entry in lines {
              let bytes = entry.1
              let suffix = if bytes.length() > 0 &&
                bytes[bytes.length() - 1] == b'\n' {
                ""
              } else {
                " (no-eol)"
              }
              generated.write_string(
                outcome.escaping.escaped_expectation(@text.trim_newlines(bytes)) +
                suffix +
                "\n",
              )
            }
          UnmatchedExpectation(_) => ()
        }
      }
      if testcase_exit_code(outcome) is Some(code) {
        generated.write_string(code)
      }
    }
    Err(InvalidExitCode(actual~, ..)) => {
      let output = @exec.output_string(
        outcome.output.stdout,
        "",
        outcome.escaping,
      )
      generated.write_string(output)
      generated.write_string("[\{actual}]\n")
    }
    Err(JsonSchemaFailed(_)) =>
      raise message("cannot generate json_schema testcase")
    Err(InternalError(msg)) =>
      raise message("cannot generate testcase from internal error: \{msg}")
    Err(Timeout) => raise message("cannot generate timed out testcase")
    Err(Skipped) => raise message("cannot generate skipped testcase")
  }
  generated.to_string()
}

///|
/// The number of backticks a code block around `code` needs, minus one.
fn max_backtick_size(code : String) -> Int {
  let mut max = 2
  for line in @document.rust_lines(code) {
    let mut count = 0
    for c in line {
      if c != '`' {
        break
      }
      count += 1
    }
    max = max.max(count)
  }
  max
}

///|
/// A Markdown document with each test code block's contents regenerated
/// from the outcomes (in order).
pub fn update_markdown(
  original : String,
  outcomes : Array[@render.Outcome],
  languages : Array[String],
) -> String raise GenerateError {
  if outcomes.is_empty() {
    return original
  }
  let updated = StringBuilder()
  let mut index = 0
  for token in @document.markdown_tokens(languages, original) {
    match token {
      Line(line) => updated.write_string(assure_newline(line))
      DocumentConfigLines(lines) => {
        updated.write_string("---\n")
        updated.write_string(lines.join("\n"))
        updated.write_string("\n---\n")
      }
      VerbatimCodeBlock(lines~, ..) =>
        for line in lines {
          updated.write_string(assure_newline(line))
        }
      TestCodeBlock(language~, config_lines~, comment_lines~, ..) => {
        let config = if config_lines.is_empty() {
          ""
        } else {
          " {" + trim_start(config_lines.join("\n")) + "}"
        }
        guard outcomes.get(index) is Some(outcome) else {
          raise message("no outcome for testcase number \{index + 1}")
        }
        let generated = generate_testcase(outcome) catch {
          e => raise e.context("testcase number \{index + 1}")
        }
        let backticks = "`".repeat(max_backtick_size(generated) + 1)
        updated.write_string("\{backticks}\{language}\{config}\n")
        for line in comment_lines {
          updated.write_string(assure_newline(line))
        }
        updated.write_string(generated)
        updated.write_string(assure_newline(backticks))
        index += 1
      }
    }
  }
  updated.to_string()
}

///|
/// Rust's `str::trim_start`.
fn trim_start(s : String) -> String {
  let chars = s.to_array()
  let mut i = 0
  while i < chars.length() && is_whitespace(chars[i]) {
    i += 1
  }
  String::from_array(chars[i:])
}

///|
/// Rust's `char::is_whitespace`.
fn is_whitespace(c : Char) -> Bool {
  match c.to_int() {
    0x09..=0x0D | 0x20 | 0x85 | 0xA0 | 0x1680 => true
    0x2000..=0x200A | 0x2028 | 0x2029 | 0x202F | 0x205F | 0x3000 => true
    _ => false
  }
}

///|
/// New Markdown test cases, one code block of `language` each.
pub fn markdown_testcases(
  outcomes : Array[@render.Outcome],
  language : String,
) -> String raise GenerateError {
  let default_config = @config.TestCaseConfig::default_markdown()
  let rendered = []
  for outcome in outcomes {
    let out = StringBuilder()
    if !outcome.testcase.title.is_empty() {
      out.write_string("# \{outcome.testcase.title}\n\n")
    }
    let config_diff = outcome.testcase.config.diff(default_config)
    let config = if config_diff.is_empty() {
      ""
    } else {
      " " + config_diff.to_yaml_one_liner()
    }
    let generated = generate_testcase(outcome)
    let backticks = "`".repeat(max_backtick_size(generated) + 1)
    out.write_string("\{backticks}\{language}\{config}\n")
    out.write_string(generated)
    out.write_string("\{backticks}\n")
    rendered.push(out.to_string())
  }
  rendered.join("\n\n")
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
fn cram_indented(indent : String, from : String) -> String {
  if from.is_empty() {
    return ""
  }
  trim_end(from).split("\n").map(line => indent + line.to_owned()).join("\n") +
  "\n"
}

///|
/// The indentation of Cram test cases.
pub let cram_indention : Int = 2

///|
/// A Cram document regenerated from the outcomes. Like upstream, only the
/// test cases (with their titles) are kept, not other text.
pub fn update_cram(
  original : String,
  outcomes : Array[@render.Outcome],
) -> String raise GenerateError {
  if outcomes.is_empty() {
    return original
  }
  let indent = " ".repeat(cram_indention)
  let testcases = []
  for outcome in outcomes {
    let title = if outcome.testcase.title.is_empty() {
      ""
    } else {
      outcome.testcase.title + "\n"
    }
    testcases.push(title + cram_indented(indent, generate_testcase(outcome)))
  }
  testcases.join("\n\n")
}

///|
/// New Cram test cases.
pub fn cram_testcases(
  outcomes : Array[@render.Outcome],
) -> String raise GenerateError {
  let indent = " ".repeat(cram_indention)
  let rendered = []
  for outcome in outcomes {
    let title = if outcome.testcase.title.is_empty() {
      ""
    } else {
      outcome.testcase.title + "\n"
    }
    rendered.push(title + cram_indented(indent, generate_testcase(outcome)))
  }
  rendered.join("\n\n")
}
