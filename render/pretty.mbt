// The default, human readable renderer (upstream src/renderers/pretty.rs).

///|
pub let default_surrounding_lines : Int = 5

///|
pub let default_multiline_matched_lines : Int = 100

///|
/// Options of the pretty renderer. With `color` off the output is
/// monochrome (colors stripped, as upstream's `PrettyMonochromeRenderer`).
pub(all) struct PrettyRenderer {
  color : Bool
  max_surrounding_lines : Int
  absolute_line_numbers : Bool
  summarize : Bool
  max_multiline_matched_lines : Int
}

///|
pub fn PrettyRenderer::new(
  color? : Bool = false,
  max_surrounding_lines? : Int = default_surrounding_lines,
  absolute_line_numbers? : Bool = false,
  summarize? : Bool = true,
  max_multiline_matched_lines? : Int = default_multiline_matched_lines,
) -> PrettyRenderer {
  {
    color,
    max_surrounding_lines,
    absolute_line_numbers,
    summarize,
    max_multiline_matched_lines,
  }
}

///|
fn PrettyRenderer::style(self : PrettyRenderer) -> Style {
  style(self.color)
}

///|
pub fn PrettyRenderer::render(
  self : PrettyRenderer,
  outcomes : Array[Outcome],
) -> String {
  let output = StringBuilder()
  let mut count_errors = 0
  let mut count_ok = 0
  let mut count_skipped = 0
  let locations : Map[String, Unit] = Map([])
  for outcome in outcomes {
    if outcome.location is Some(location) {
      locations[location] = ()
    }
    match outcome.result {
      Err(Skipped) => count_skipped += 1
      Err(err) => {
        count_errors += 1
        output.write_string(outcome.render_header(color=self.color))
        output.write_string(self.render_error(err, outcome))
        output.write_string("\n\n")
      }
      Ok(_) => count_ok += 1
    }
  }
  if self.summarize {
    output.write_string(
      self.render_summary(
        locations.length(),
        count_ok,
        count_errors,
        count_skipped,
      ),
    )
  }
  output.to_string()
}

///|
/// The pretty renderer's output: colored, or monochrome (colors stripped;
/// `styled` says whether the terminal would have received styles).
pub fn render_pretty(
  renderer : PrettyRenderer,
  outcomes : Array[Outcome],
  styled? : Bool = false,
) -> String {
  if renderer.color {
    renderer.render(outcomes)
  } else {
    strip_colors({ ..renderer, color: styled, }.render(outcomes))
  }
}

///|
fn PrettyRenderer::render_summary(
  self : PrettyRenderer,
  files : Int,
  ok : Int,
  errors : Int,
  ignored : Int,
) -> String {
  let s = self.style()
  let summary = s.underlined().paint("Result")
  let total = ok + errors + ignored
  let tests = s.bold().paint("\{total} testcase(s)")
  let succeeded = (if ok > 0 { s.green().bold() } else { s.green() }).paint(
    "\{ok} succeeded",
  )
  let failed = (if errors > 0 { s.red().bold() } else { s.red() }).paint(
    "\{errors} failed",
  )
  let skipped = (if ignored > 0 { s.yellow().bold() } else { s.yellow() }).paint(
    "\{ignored} skipped",
  )
  "\{summary}: \{files} document(s) with \{tests}: \{succeeded}, \{failed} and \{skipped}\n"
}

///|
fn PrettyRenderer::render_error(
  self : PrettyRenderer,
  err : @exec.TestCaseError,
  outcome : Outcome,
) -> String {
  match err {
    MalformedOutput(diff) => self.render_malformed_output(outcome, diff)
    JsonSchemaFailed(kind, errors) =>
      self.render_json_schema_failed(kind, errors, outcome)
    InvalidExitCode(actual~, expected~) =>
      "unexpected exit code\n  expected: \{expected}\n  actual:   \{actual}\n\n" +
      outcome.output.to_error_string(outcome.escaping)
    InternalError(msg) => "error: \{msg}\n"
    Timeout =>
      "timeout in execution\n\n" +
      outcome.output.to_error_string(outcome.escaping)
    Skipped => ""
  }
}

///|
fn PrettyRenderer::render_json_schema_failed(
  self : PrettyRenderer,
  kind : String,
  errors : Array[String],
  outcome : Outcome,
) -> String {
  let s = self.style()
  let kind_str = match kind {
    "InvalidSchema" => "invalid schema"
    "InvalidJson" => "invalid JSON output"
    _ => "schema validation errors"
  }
  let out = StringBuilder()
  out.write_string(
    s.red().bold().paint("JSON Schema validation failed: \{kind_str}") + "\n",
  )
  out.write_string("\n")
  for error in errors {
    out.write_string("  \{s.red().bold().paint("-")} \{s.red().paint(error)}\n")
  }
  let actual = @text.lossy_string(outcome.output.stdout)
  if !actual.is_empty() {
    out.write_string("\n")
    out.write_string(s.underlined().paint("actual output:") + "\n")
    for line in @document.rust_lines(actual) {
      out.write_string("  \{line}\n")
    }
  }
  out.to_string()
}

///|
/// Byte length of a string in UTF-8 (Rust's `str::len`).
fn utf8_len(s : String) -> Int {
  let mut n = 0
  for c in s {
    let v = c.to_int()
    n += if v < 0x80 {
      1
    } else if v < 0x800 {
      2
    } else if v < 0x10000 {
      3
    } else {
      4
    }
  }
  n
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
fn PrettyRenderer::render_malformed_output(
  self : PrettyRenderer,
  outcome : Outcome,
  diff : @diff.Diff,
) -> String {
  let output = StringBuilder()
  let line_base = if self.absolute_line_numbers {
    outcome.testcase.line_number + outcome.testcase.shell_expression_lines() - 1
  } else {
    0
  }
  let decorator = Decorator::new(
    line_base +
    diff.count_output_lines.max(outcome.testcase.expectations().length()),
    self.color,
  )
  let mut last_error_index : Int? = None
  let next_error_index = (index : Int) => {
    for i in index..<diff.lines.length() {
      if !(diff.lines[i] is MatchedExpectation(_)) {
        return Some(i)
      }
    }
    None
  }
  let s = self.style()
  for diff_index, line in diff.lines {
    match line {
      MatchedExpectation(index~, expectation~, lines~) => {
        let mut skip = true
        let mut first_skip = false
        if self.max_surrounding_lines > 0 {
          if last_error_index is Some(last) {
            if last + self.max_surrounding_lines >= diff_index {
              skip = false
            } else if last + self.max_surrounding_lines + 1 == diff_index {
              first_skip = true
            }
          }
          if next_error_index(diff_index + 1) is Some(next) &&
            diff_index + self.max_surrounding_lines >= next {
            skip = false
          }
        } else {
          skip = false
        }
        if !skip {
          if !expectation.multiline || self.max_multiline_matched_lines <= 1 {
            output.write_string(
              assure_newline(
                decorator.line(
                  if expectation.multiline {
                    Some(0)
                  } else {
                    Some(line_base + lines[0].0 + 1)
                  },
                  Some(line_base + index + 1),
                  expectation.multiline,
                  " ",
                  expectation.to_expression_string(outcome.escaping),
                ),
              ),
            )
          } else {
            let mut half = 0
            let max = self.max_multiline_matched_lines
            let lines = if lines.length() > max {
              half = (max + 1) / 2
              let kept = lines[:half].to_owned()
              kept.append(lines[lines.length() - (max - half):].to_owned())
              kept
            } else {
              lines
            }
            let escaped = lines.map(l => {
              (
                l.0,
                outcome.escaping.escaped_printable(@text.trim_newlines(l.1)),
              )
            })
            let max_line_length = escaped.fold(init=0, (m, l) => {
              m.max(utf8_len(l.1))
            })
            for output_index, entry in escaped {
              let (line_index, line) = entry
              let output_line = if output_index == 0 {
                let padding = " ".repeat(max_line_length - utf8_len(line) + 2)
                let expression = expectation.to_expression_string(
                  outcome.escaping,
                )
                "\{line}\{padding}\{s.magenta().paint("//")} \{s.magenta().bold().paint(expression)}"
              } else {
                line
              }
              output.write_string(
                assure_newline(
                  decorator.line(
                    Some(line_base + line_index + 1),
                    if output_index == 0 {
                      Some(line_base + index + 1)
                    } else {
                      None
                    },
                    expectation.multiline,
                    " ",
                    output_line,
                  ),
                ),
              )
              if half > 0 && output_index + 1 == half {
                output.write_string(
                  assure_newline(
                    decorator.line(None, None, expectation.multiline, "…", ""),
                  ),
                )
              }
            }
          }
        } else if first_skip {
          output.write_string("...\n")
        }
      }
      UnmatchedExpectation(index~, expectation~) => {
        last_error_index = Some(diff_index)
        let content = self.highlight_trailing_spaces(
          expectation.to_expression_string(outcome.escaping),
        )
        output.write_string(
          assure_newline(
            decorator.line(
              None,
              Some(line_base + index + 1),
              expectation.multiline,
              "-",
              content,
            ),
          ),
        )
      }
      UnexpectedLines(lines~) =>
        for entry in lines {
          let (line_index, line) = entry
          let line = if @text.ends_in_newline(line) {
            line
          } else {
            let buf = Buffer()
            buf.write_bytes(line)
            buf.write_bytes(b" (no-eol)")
            buf.to_bytes()
          }
          let line = self.highlight_trailing_spaces(
            outcome.escaping.escaped_expectation(line),
          )
          last_error_index = Some(diff_index)
          output.write_string(
            assure_newline(
              decorator.line(
                Some(line_base + line_index + 1),
                None,
                false,
                "+",
                line,
              ),
            ),
          )
        }
    }
  }
  output.to_string()
}

///|
/// Rust's `char::is_whitespace` (the Unicode `White_Space` property).
fn is_whitespace(c : Char) -> Bool {
  match c.to_int() {
    0x09..=0x0D | 0x20 | 0x85 | 0xA0 | 0x1680 => true
    0x2000..=0x200A | 0x2028 | 0x2029 | 0x202F | 0x205F | 0x3000 => true
    _ => false
  }
}

///|
/// Make trailing whitespace visible: `↦` for tabs, `⎵` for spaces and `⍰`
/// for other whitespace.
fn PrettyRenderer::highlight_trailing_spaces(
  self : PrettyRenderer,
  input : String,
) -> String {
  let chars = input.to_array()
  let mut start = chars.length()
  while start > 0 && is_whitespace(chars[start - 1]) {
    start -= 1
  }
  // No trailing whitespace. (All-whitespace input is highlighted
  // entirely, like upstream.)
  if start == chars.length() {
    return input
  }
  let visible = StringBuilder()
  for c in chars[start:] {
    visible.write_char(
      match c {
        '\t' => '↦'
        ' ' => '⎵'
        _ => '⍰'
      },
    )
  }
  String::from_array(chars[:start]) +
  self.style().magenta().bold().paint(visible.to_string())
}

///|
/// Line number columns of the diff output.
priv struct Decorator {
  width : Int
  color : Bool
}

///|
fn Decorator::new(max_lines : Int, color : Bool) -> Decorator {
  { width: max_lines.to_string().length(), color, }
}

///|
fn Decorator::output_line_number(self : Decorator, num : Int?) -> String {
  match num {
    None => " ".repeat(self.width)
    Some(0) => "+".repeat(self.width)
    Some(n) => {
      let digits = n.to_string()
      " ".repeat((self.width - digits.length()).max(0)) + digits
    }
  }
}

///|
fn Decorator::expectation_line_number(
  self : Decorator,
  num : Int?,
  multiline : Bool,
) -> String {
  self.output_line_number(num) + (if multiline { "+" } else { " " })
}

///|
fn Decorator::line(
  self : Decorator,
  line_number : Int?,
  expectation_number : Int?,
  multiline : Bool,
  symbol : String,
  content : String,
) -> String {
  let s = style(self.color)
  let (color, line_color) : (Style, Style?) = match symbol {
    "+" => (s.green().bold(), Some(s.green()))
    "-" => (s.red().bold(), Some(s.red()))
    _ => (s.white(), None)
  }
  let paint_line = (text : String) => {
    match line_color {
      Some(c) => c.paint(text)
      None => text
    }
  }
  s
  .bright()
  .black()
  .paint(
    "\{paint_line(self.expectation_line_number(expectation_number, multiline))} \{paint_line(self.output_line_number(line_number))}  | \{color.paint(symbol)} \{color.paint(content)}",
  )
}
