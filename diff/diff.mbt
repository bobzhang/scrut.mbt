// Comparing output with expectations (upstream src/diff.rs).

///|
/// One element of a diff.
pub enum DiffLine {
  /// An expectation that matched one or more output lines.
  MatchedExpectation(
    index~ : Int,
    expectation~ : @rules.Expectation,
    lines~ : Array[(Int, Bytes)]
  )
  /// A (non-optional) expectation that was not matched.
  UnmatchedExpectation(index~ : Int, expectation~ : @rules.Expectation)
  /// Output lines no expectation accounts for.
  UnexpectedLines(lines~ : Array[(Int, Bytes)])
}

///|
/// The result of comparing output with expectations.
pub struct Diff {
  lines : Array[DiffLine]
  count_matched : Int
  count_unmatched : Int
  count_output_lines : Int
}

///|
pub fn Diff::new(lines : Array[DiffLine]) -> Diff {
  let mut matched = 0
  let mut unmatched = 0
  let mut output_lines = 0
  for line in lines {
    match line {
      MatchedExpectation(lines~, ..) => {
        matched += 1
        output_lines += lines.length()
      }
      UnmatchedExpectation(..) => unmatched += 1
      UnexpectedLines(lines~) => output_lines += lines.length()
    }
  }
  {
    lines,
    count_matched: matched,
    count_unmatched: unmatched,
    count_output_lines: output_lines,
  }
}

///|
/// Whether anything did not match.
pub fn Diff::has_differences(self : Diff) -> Bool {
  self.lines.iter().any(l => !(l is MatchedExpectation(..)))
}

///|
priv enum PeekMatch {
  NextExpectation(Int)
  NextLine(Int)
  NoMatch
}

///|
/// Compare output with a list of expectations (upstream's greedy
/// algorithm, unchanged).
pub fn diff(
  expectations : Array[@rules.Expectation],
  output : BytesView,
) -> Diff {
  let lines = @text.split_at_newline(output)
  let owned = (i : Int) => (i, lines[i].to_owned())
  let range = (from : Int, to : Int) => {
    let out = []
    for i in from..<to {
      out.push(owned(i))
    }
    out
  }
  let peek_matching_expectation = (line : BytesView, start : Int) => {
    for i in start..<expectations.length() {
      if expectations[i].matches(line) {
        return Some(i)
      }
    }
    None
  }
  let peek_matching_line = (e : @rules.Expectation, start : Int) => {
    for i in start..<lines.length() {
      if e.matches(lines[i]) {
        return Some(i)
      }
    }
    None
  }
  let peek_match = (line_index : Int, expectation_index : Int) => {
    match peek_matching_expectation(lines[line_index], expectation_index + 1) {
      Some(i) => NextExpectation(i)
      None =>
        match
          peek_matching_line(expectations[expectation_index], line_index + 1) {
          Some(i) => NextLine(i)
          None => NoMatch
        }
    }
  }
  let mut expectation_index = 0
  let mut line_index = 0
  let diffs = []
  let mut match_start : Int? = None
  while expectation_index < expectations.length() && line_index < lines.length() {
    let expectation = expectations[expectation_index]
    let next_expectation = expectations.get(expectation_index + 1)
    let line = lines[line_index]
    if expectation.matches(line) {
      if expectation.multiline {
        if next_expectation is Some(next) &&
          (expectation.optional || match_start is Some(_)) &&
          next.matches(line) {
          if match_start is Some(start) {
            diffs.push(
              MatchedExpectation(
                index=expectation_index,
                expectation~,
                lines=range(start, line_index),
              ),
            )
          }
          expectation_index += 1
          match_start = None
          continue
        }
        if match_start is None {
          match_start = Some(line_index)
        }
        line_index += 1
        continue
      }
      diffs.push(
        MatchedExpectation(index=expectation_index, expectation~, lines=[
          owned(line_index),
        ]),
      )
      line_index += 1
      expectation_index += 1
      continue
    }
    if match_start is Some(start) {
      diffs.push(
        MatchedExpectation(
          index=expectation_index,
          expectation~,
          lines=range(start, line_index),
        ),
      )
      match_start = None
      expectation_index += 1
      continue
    }
    match_start = None
    match peek_match(line_index, expectation_index) {
      NextExpectation(next) => {
        for i in expectation_index..<next {
          if !expectations[i].optional {
            diffs.push(
              UnmatchedExpectation(index=i, expectation=expectations[i]),
            )
          }
        }
        expectation_index = next
      }
      NextLine(next) => {
        diffs.push(UnexpectedLines(lines=range(line_index, next)))
        line_index = next
      }
      NoMatch => {
        if !expectation.optional {
          diffs.push(
            UnmatchedExpectation(index=expectation_index, expectation~),
          )
        }
        expectation_index += 1
      }
    }
  }
  if match_start is Some(start) {
    diffs.push(
      MatchedExpectation(
        index=expectation_index,
        expectation=expectations[expectation_index],
        lines=range(start, line_index),
      ),
    )
    expectation_index += 1
  }
  for i in expectation_index..<expectations.length() {
    if !expectations[i].optional {
      diffs.push(UnmatchedExpectation(index=i, expectation=expectations[i]))
    }
  }
  if line_index < lines.length() {
    diffs.push(UnexpectedLines(lines=range(line_index, lines.length())))
  }
  Diff::new(diffs)
}

///|
fn pad4(n : Int) -> String {
  let s = n.to_string()
  "0000"[:4 - s.length().min(4)].to_owned() + s
}

///|
/// Upstream's `Debug` rendering of a diff (used to compare with upstream).
pub fn Diff::debug_string(self : Diff) -> String {
  let buf = StringBuilder()
  let mut matched = 0
  let mut unmatched = 0
  let mut unexpected = 0
  let body = StringBuilder()
  for line in self.lines {
    match line {
      MatchedExpectation(index~, expectation~, lines~) => {
        matched += lines.length()
        body.write_string("\{pad4(index + 1)}      | = \{expectation}\n")
        for l in lines {
          body.write_string(
            "     \{pad4(l.0 + 1)} | = \{@text.lossy_string(l.1)}",
          )
        }
      }
      UnmatchedExpectation(index~, expectation~) => {
        unmatched += 1
        body.write_string("\{pad4(index + 1)}      | - \{expectation}\n")
      }
      UnexpectedLines(lines~) => {
        unexpected += lines.length()
        for l in lines {
          let eol = @text.ends_in_newline(l.1)
          body.write_string(
            "     \{pad4(l.0 + 1)} | + \{@text.lossy_string(l.1)}\{if eol { "" } else { " (no-eol)" }}",
          )
        }
      }
    }
  }
  buf.write_string(
    "[matched: \{matched}, unmatched: \{unmatched}, unexpected: \{unexpected}]\n",
  )
  buf.write_string(body.to_string())
  buf.to_string()
}
