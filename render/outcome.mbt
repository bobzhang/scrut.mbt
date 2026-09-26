// The result of one test case as renderers see it (upstream src/outcome.rs
// and src/renderers/outcome.rs).

///|
pub(all) struct Outcome {
  /// The path of the test document.
  location : String?
  output : @exec.Output
  testcase : @document.TestCase
  format : @document.ParserType
  escaping : @text.Escaper
  result : Result[Unit, @exec.TestCaseError]
}

///|
let max_line_length = 80

///|
fn header_to_title(
  color : Bool,
  first_prefix : String,
  text : String,
  paint : (String) -> String,
) -> String {
  let buf = StringBuilder()
  let prefix = style(color).bright().black().paint("//")
  for index, line in text.split("\n").collect() {
    let p = if index == 0 { first_prefix } else { " " }
    buf.write_string(
      "\{prefix} \{style(color).bold().paint(p)} \{paint(line.to_owned())}\n",
    )
  }
  buf.to_string()
}

///|
/// The header above a failed test case: location, title and command
/// between dividers.
pub fn Outcome::render_header(self : Outcome, color? : Bool = false) -> String {
  let headers = []
  let location = match self.location {
    Some(location) => "\{location}:\{self.testcase.line_number}"
    None => "Line \{self.testcase.line_number}"
  }
  headers.push(
    header_to_title(color, "@", location, s => {
      style(color).bright().blue().paint(s)
    }),
  )
  if !self.testcase.title.is_empty() {
    headers.push(
      header_to_title(color, "#", self.testcase.title, s => {
        style(color).bright().cyan().paint(s)
      }),
    )
  }
  headers.push(
    header_to_title(color, "$", self.testcase.shell_expression, s => {
      style(color).bold().bright().yellow().paint(s)
    }),
  )
  let outer = style(color)
    .bright()
    .black()
    .paint("// " + "=".repeat(max_line_length - 3) + "\n")
  let inner = style(color)
    .bright()
    .black()
    .paint("// " + "-".repeat(max_line_length - 3) + "\n")
  outer + headers.join(inner) + outer + "\n"
}
