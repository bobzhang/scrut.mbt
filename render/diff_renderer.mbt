// The unified diff renderer (upstream src/renderers/diff.rs): failures as
// hunks against the test document.

///|
/// Rendering failed (upstream renderer errors).
pub(all) suberror RenderError {
  RenderError(String)
} derive(Debug)

///|
pub impl Show for RenderError with fn output(self, logger) {
  let RenderError(msg) = self
  logger.write_string(msg)
}

///|
fn join_multiline(text : String, sep : String) -> String {
  @document.rust_lines(text).join(sep)
}

///|
fn line_prefix(outcome : Outcome) -> String {
  match outcome.format {
    Markdown => ""
    Cram => "  "
  }
}

///|
fn length_suffix(len : Int) -> String {
  if len > 1 || len == 0 {
    ",\{len}"
  } else {
    ""
  }
}

///|
fn diff_header(
  old_start : Int,
  old_length : Int,
  new_start : Int,
  new_length : Int,
  kind : String,
  title : String,
) -> String {
  "@@ -\{old_start}\{length_suffix(old_length)} +\{new_start}\{length_suffix(new_length)} @@ \{kind}: \{title}\n"
}

///|
/// Render failures as a unified diff. Raises when some outcomes have a
/// location and others not, or when unexpected output is not UTF-8.
pub fn render_diff(outcomes : Array[Outcome]) -> String raise RenderError {
  let count_locations = outcomes.filter(o => o.location is Some(_)).length()
  let outcomes = outcomes.copy()
  if count_locations > 0 {
    if count_locations != outcomes.length() {
      raise RenderError(
        "cannot render diff with some outcomes providing locations, but not all",
      )
    }
    // A stable sort by location (byte order), then line number.
    outcomes.sort_by((a, b) => {
      let c = @text.compare_utf8(
        a.location.unwrap_or(""),
        b.location.unwrap_or(""),
      )
      if c != 0 {
        c
      } else {
        a.testcase.line_number.compare(b.testcase.line_number)
      }
    })
  }
  let output = StringBuilder()
  let mut last_location : String? = None
  for outcome in outcomes {
    guard outcome.result is Err(err) else { continue }
    if outcome.location != last_location && outcome.location is Some(location) {
      if last_location is Some(_) {
        output.write_char('\n')
      }
      last_location = outcome.location
      output.write_string("--- \{location}\n+++ \{location}.new\n")
    }
    output.write_string(render_diff_error(err, outcome))
  }
  output.to_string()
}

///|
fn render_diff_error(
  err : @exec.TestCaseError,
  outcome : Outcome,
) -> String raise RenderError {
  let title = join_multiline(outcome.testcase.title, " * ")
  let prefix = line_prefix(outcome)
  match err {
    InvalidExitCode(actual~, ..) => {
      let tc = outcome.testcase
      let line_number = tc.line_number +
        tc.shell_expression_lines() +
        tc.expectations().length()
      let out = StringBuilder()
      out.write_string(
        diff_header(
          line_number,
          if tc.exit_code is Some(_) {
            1
          } else {
            0
          },
          line_number,
          1,
          "invalid exit code",
          title,
        ),
      )
      if tc.exit_code is Some(code) {
        out.write_string("-\{prefix}[\{code}]\n")
      }
      out.write_string("+\{prefix}[\{actual}]\n")
      out.to_string()
    }
    InternalError(msg) => {
      let out = StringBuilder()
      out.write_string("# ---- INTERNAL ERROR ----\n")
      if outcome.location is Some(location) {
        out.write_string("# PATH:  \{location}\n")
      }
      out.write_string("# TITLE: \{title}\n")
      for line in @document.rust_lines(msg) {
        out.write_string("# ERROR: \{line}\n")
      }
      out.write_string("# ---- INTERNAL ERROR ----\n")
      out.to_string()
    }
    MalformedOutput(diff) => unified_diff(outcome, diff, title, prefix)
    Timeout | Skipped => ""
    JsonSchemaFailed(kind, errors) => {
      let out = StringBuilder()
      out.write_string("# ---- JSON SCHEMA VALIDATION FAILED ----\n")
      if outcome.location is Some(location) {
        out.write_string("# PATH:  \{location}\n")
      }
      out.write_string("# TITLE: \{title}\n")
      out.write_string("# KIND:  \{kind}\n")
      for error in errors {
        for line in @document.rust_lines(error) {
          out.write_string("# ERROR: \{line}\n")
        }
      }
      out.write_string("# OUTPUT:\n")
      for
        line in @document.rust_lines(@text.lossy_string(outcome.output.stdout)) {
        out.write_string("# \{line}\n")
      }
      out.write_string("# ---- JSON SCHEMA VALIDATION FAILED ----\n")
      out.to_string()
    }
  }
}

///|
fn unified_diff(
  outcome : Outcome,
  diff : @diff.Diff,
  title : String,
  prefix : String,
) -> String raise RenderError {
  let line_number = outcome.testcase.line_number +
    outcome.testcase.shell_expression_lines()
  let output = StringBuilder()
  let mut unmatched_start : Int? = None
  let unmatched_lines : Array[String] = []
  let mut unexpected_start : Int? = None
  let unexpected_lines : Array[String] = []
  let add_hunk = () => {
    if unmatched_start is Some(_) || unexpected_start is Some(_) {
      let (old_start, new_start) = match unmatched_start {
        Some(u) => (u, unexpected_start.unwrap_or(u))
        None => {
          let u = unexpected_start.unwrap()
          (u, u)
        }
      }
      output.write_string(
        diff_header(
          old_start + line_number,
          unmatched_lines.length(),
          new_start + line_number,
          unexpected_lines.length(),
          "malformed output",
          title,
        ),
      )
      for line in unmatched_lines {
        output.write_string("-\{prefix}\{line}\n")
      }
      for line in unexpected_lines {
        output.write_string("+\{prefix}\{line}\n")
      }
      unmatched_start = None
      unexpected_start = None
      unmatched_lines.clear()
      unexpected_lines.clear()
    }
  }
  let mut expectation_index = 0
  for line in diff.lines {
    match line {
      MatchedExpectation(index~, ..) => {
        expectation_index = index
        add_hunk()
      }
      UnmatchedExpectation(index~, expectation~) => {
        expectation_index = index
        if unmatched_start is None {
          unmatched_start = Some(index)
        }
        unmatched_lines.push(expectation.original)
      }
      UnexpectedLines(lines~) => {
        if unexpected_start is None {
          unexpected_start = Some(expectation_index)
        }
        for entry in lines {
          let bytes = @text.trim_newlines(entry.1)
          match @text.utf8_string(bytes) {
            Some(text) => unexpected_lines.push(text)
            None =>
              raise RenderError(
                @text.rust_utf8_error(bytes).unwrap_or("invalid utf-8"),
              )
          }
        }
        if unmatched_start is Some(_) {
          add_hunk()
        }
      }
    }
  }
  add_hunk()
  output.to_string()
}
