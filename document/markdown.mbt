// Markdown test documents (upstream src/parsers/markdown.rs).

///|
fn is_letter(c : Char) -> Bool {
  let cp = c.to_int()
  let mut lo = 0
  let mut hi = letter_ranges.length()
  while lo < hi {
    let mid = (lo + hi) / 2
    let (a, b) = letter_ranges[mid]
    if cp < a {
      hi = mid
    } else if cp > b {
      lo = mid + 1
    } else {
      return true
    }
  }
  false
}

///|
fn is_white_space(c : Char) -> Bool {
  match c.to_int() {
    0x09..=0x0D
    | 0x20
    | 0x85
    | 0xA0
    | 0x1680
    | 0x2000..=0x200A
    | 0x2028
    | 0x2029
    | 0x202F
    | 0x205F
    | 0x3000 => true
    _ => false
  }
}

///|
/// Rust's `str::trim`.
pub fn rust_trim(s : String) -> String {
  let chars = s.to_array()
  let mut a = 0
  let mut b = chars.length()
  while a < b && is_white_space(chars[a]) {
    a += 1
  }
  while b > a && is_white_space(chars[b - 1]) {
    b -= 1
  }
  String::from_array(chars[a:b])
}

///|
/// A paragraph (starting with a letter) or a heading (`# title`): the title
/// text.
pub fn extract_title(line : String) -> String? {
  let line = rust_trim(line)
  let chars = line.to_array()
  if chars.length() > 0 && is_letter(chars[0]) {
    return Some(line)
  }
  // `^(#+\s+)(.+)$`
  let mut i = 0
  while i < chars.length() && chars[i] == '#' {
    i += 1
  }
  if i == 0 {
    return None
  }
  let hashes_end = i
  while i < chars.length() && is_white_space(chars[i]) {
    i += 1
  }
  if i == hashes_end {
    return None
  }
  // `\s+` is greedy but must leave at least one character for `.+`.
  if i == chars.length() {
    if i - hashes_end < 2 {
      return None
    }
    i -= 1
  }
  Some(String::from_array(chars[i:]))
}

///|
/// The opening of a code block: (backticks, language, config).
pub fn extract_code_block_start(line : String) -> (String, String, String)? {
  if line == "```" {
    return Some((line, "", ""))
  }
  let chars = line.to_array()
  let mut language_start : Int? = None
  for i, c in chars {
    match language_start {
      Some(ls) =>
        if c == '{' {
          let language = rust_trim_end(String::from_array(chars[ls:i]))
          return Some(
            (
              String::from_array(chars[0:ls]),
              language,
              String::from_array(chars[i:]),
            ),
          )
        }
      None =>
        if c != '`' {
          if i < 2 {
            return None
          }
          language_start = Some(i)
        }
    }
  }
  match language_start {
    Some(ls) =>
      Some(
        (String::from_array(chars[0:ls]), String::from_array(chars[ls:]), ""),
      )
    None => None
  }
}

///|
fn rust_trim_end(s : String) -> String {
  let chars = s.to_array()
  let mut b = chars.length()
  while b > 0 && is_white_space(chars[b - 1]) {
    b -= 1
  }
  String::from_array(chars[0:b])
}

///|
/// A part of a Markdown document (upstream `MarkdownToken`).
pub(all) enum MarkdownToken {
  /// Any other line.
  Line(String)
  /// The front matter's lines (between `---` lines).
  DocumentConfigLines(Array[String])
  /// A test code block: its language, the `{...}` configuration on the
  /// opening line, leading comment lines and the code (with line indices).
  TestCodeBlock(
    language~ : String,
    config_lines~ : Array[String],
    comment_lines~ : Array[String],
    code_lines~ : Array[(Int, String)]
  )
  /// Any other code block, with all its lines (backtick lines included).
  VerbatimCodeBlock(
    starting_line~ : Int,
    language~ : String,
    lines~ : Array[String]
  )
}

///|
/// Split a Markdown document into the tokens upstream's iterator yields
/// (an unterminated front matter or code block ends the document).
pub fn markdown_tokens(
  languages : Array[String],
  text : String,
) -> Array[MarkdownToken] {
  let lines = rust_lines(text)
  let tokens = []
  let mut i = 0
  let mut content_start = false
  while i < lines.length() {
    let line = lines[i]
    i += 1
    if !content_start && line == "---" {
      let config = []
      while i < lines.length() && lines[i] != "---" {
        config.push(lines[i])
        i += 1
      }
      if i >= lines.length() {
        break
      }
      i += 1
      tokens.push(DocumentConfigLines(config))
      continue
    }
    guard extract_code_block_start(line) is Some((backticks, language, config)) else {
      if !rust_trim(line).is_empty() {
        content_start = true
      }
      tokens.push(Line(line))
      continue
    }
    content_start = true
    if !languages.contains(language) {
      let start = i - 1
      let block = [line]
      while i < lines.length() && !lines[i].has_prefix(backticks) {
        block.push(lines[i])
        i += 1
      }
      if i >= lines.length() {
        break
      }
      block.push(lines[i])
      i += 1
      tokens.push(
        VerbatimCodeBlock(starting_line=start, language~, lines=block),
      )
      continue
    }
    let config_lines = if config.has_prefix("{") &&
      config.has_suffix("}") &&
      config.length() > 2 {
      [config[1:config.length() - 1].to_owned()]
    } else {
      []
    }
    if i >= lines.length() {
      break
    }
    let comment_lines = []
    while i < lines.length() && is_comment(lines[i]) {
      comment_lines.push(lines[i])
      i += 1
    }
    let code_lines = []
    while i < lines.length() && !lines[i].has_prefix(backticks) {
      code_lines.push((i, lines[i]))
      i += 1
    }
    if i >= lines.length() {
      break
    }
    i += 1
    tokens.push(
      TestCodeBlock(language~, config_lines~, comment_lines~, code_lines~),
    )
  }
  tokens
}

///|
fn document_config_yaml(
  text : String,
) -> @config.DocumentConfig raise ParseError {
  let yaml = @config.parse_yaml(text) catch {
    e => raise ParseError("parse document config from front-matter: \{e}")
  }
  @config.document_config_from_yaml(yaml) catch {
    e => raise ParseError("parse document config from front-matter: \{e}")
  }
}

///|
/// Parse a Markdown test document. `languages` are the code block languages
/// of test cases (default `scrut`); `cram_compat` changes glob rules and the
/// test case defaults.
pub fn parse_markdown(
  text : String,
  languages? : Array[String] = ["scrut"],
  cram_compat? : Bool = false,
) -> Document raise ParseError {
  let base = if cram_compat {
    @config.TestCaseConfig::default_cram()
  } else {
    @config.TestCaseConfig::default_markdown()
  }
  let parser = LineParser::new(
    @rules.ExpectationMaker::new(cram_compat~),
    @config.TestCaseConfig::default_markdown(),
    allow_multiple_commands=false,
    allow_multiline_config=true,
  )
  let title_paragraph = []
  let mut config = @config.DocumentConfig::default_markdown()
  for token in markdown_tokens(languages, text) {
    match token {
      DocumentConfigLines(lines) => {
        let parsed = document_config_yaml(lines.join("\n"))
        config = config.with_overrides_from(parsed)
      }
      Line(line) =>
        match extract_title(line) {
          Some(title) => {
            title_paragraph.push(title)
            parser.title = Some(title_paragraph.join("\n"))
          }
          None => title_paragraph.clear()
        }
      VerbatimCodeBlock(starting_line~, language~, ..) =>
        if language.is_empty() {
          raise ParseError(
            "Code block starting at line \{starting_line} is missing language specifier. Use ```scrut to make this block a Scrut test, or any other language to make Scrut skip this block.",
          )
        }
      TestCodeBlock(config_lines~, code_lines~, ..) => {
        let parsed = if config_lines.is_empty() {
          @config.TestCaseConfig::empty()
        } else {
          parse_config_yaml("{" + config_lines.join("\n") + "}") catch {
            ParseError(msg) => raise ParseError("parse testcase config: \{msg}")
          }
        }
        for l in code_lines {
          parser.add_testcase_body(l.1, l.0)
        }
        parser.config = Some(
          parsed.with_defaults_from(config.defaults).with_defaults_from(base),
        )
        match code_lines {
          [] => parser.flush()
          _ => parser.end_testcase(code_lines[code_lines.length() - 1].0)
        }
        title_paragraph.clear()
      }
    }
  }
  { config, testcases: parser.testcases, }
}

///|
/// Parse a Cram test document (`.t`).
pub fn parse_cram(text : String) -> Document raise ParseError {
  let parser = LineParser::new(
    @rules.ExpectationMaker::new(cram_compat=true),
    @config.TestCaseConfig::default_cram(),
    allow_multiple_commands=true,
    allow_multiline_config=false,
  )
  let lines = rust_lines(text)
  for index, line in lines {
    if is_comment(line) {
      continue
    }
    if line.is_empty() {
      if parser.has_testcase_body() {
        parser.end_testcase(index)
      }
      continue
    }
    if line.has_prefix("  ") {
      parser.add_testcase_body(line[2:].to_owned(), index)
      continue
    }
    parser.end_testcase(index)
    parser.title = Some(line)
  }
  if parser.has_testcase_body() {
    parser.end_testcase(lines.length())
  }
  {
    config: @config.DocumentConfig::default_cram(),
    testcases: parser.testcases,
  }
}
