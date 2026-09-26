// Finding and parsing test documents (upstream src/bin/utils/file_parser.rs).

///|
/// An error with its context chain, outermost first (rendered like
/// `anyhow`'s debug format).
pub(all) suberror AppError {
  AppError(Array[String])
} derive(Debug)

///|
pub impl Show for AppError with fn output(self, logger) {
  let AppError(messages) = self
  logger.write_string(messages.get(0).unwrap_or(""))
  if messages.length() == 2 {
    logger.write_string("\n\nCaused by:\n    \{messages[1]}")
  } else if messages.length() > 2 {
    logger.write_string("\n\nCaused by:")
    for i, m in messages[1:] {
      logger.write_string("\n    \{i}: \{m}")
    }
  }
}

///|
/// Add an outer context to an error.
fn AppError::context(self : AppError, message : String) -> AppError {
  let AppError(messages) = self
  AppError([message, ..messages])
}

///|
pub let default_match_markdown : String = "*.{md,markdown,scrut}"

///|
pub let default_match_cram : String = "*.{t,cram}"

///|
pub let default_markdown_languages : ReadOnlyArray[String] = ["scrut"]

///|
/// A parsed test document.
pub(all) struct ParsedTestFile {
  path : String
  parser_type : @document.ParserType
  testcases : Array[@document.TestCase]
  config : @config.DocumentConfig
}

///|
/// Picks the parser for a document by its file name.
pub struct FileParser {
  match_markdown : Glob
  match_cram : Glob
  markdown_languages : Array[String]
}

///|
pub fn FileParser::new(
  match_markdown : String,
  match_cram : String,
  markdown_languages : Array[String],
) -> FileParser raise AppError {
  let match_markdown = Glob::new(match_markdown) catch {
    e =>
      raise AppError(["create file parser", "create markdown matcher", "\{e}"])
  }
  let match_cram = Glob::new(match_cram) catch {
    e => raise AppError(["create file parser", "create cram matcher", "\{e}"])
  }
  { match_markdown, match_cram, markdown_languages, }
}

///|
fn FileParser::accept(self : FileParser, path : String) -> Bool {
  self.match_markdown.is_match(path) || self.match_cram.is_match(path)
}

///|
/// Join a path to a directory like Rust's `Path::join`.
pub fn path_join(directory : String, path : String) -> String {
  if directory.is_empty() || is_absolute(path) {
    path
  } else if directory.has_suffix("/") ||
    (is_windows() && directory.has_suffix("\\")) {
    directory + path
  } else {
    directory + separator() + path
  }
}

///|
fn is_windows() -> Bool {
  @async.platform is Windows
}

///|
fn separator() -> String {
  if is_windows() {
    "\\"
  } else {
    "/"
  }
}

///|
fn is_absolute(path : String) -> Bool {
  if is_windows() {
    path.has_prefix("\\") ||
    path.has_prefix("/") ||
    (
      path.length() > 2 &&
      path[1:2] == ":" &&
      (path[2:3] == "\\" || path[2:3] == "/")
    )
  } else {
    path.has_prefix("/")
  }
}

///|
/// The directory part of a path (Rust's `Path::parent`, `""` for a bare
/// file name).
pub fn path_parent(path : String) -> String {
  let chars = path.to_array()
  let mut end = chars.length()
  let is_sep = (c : Char) => c == '/' || (is_windows() && c == '\\')
  // Trailing separators do not count.
  while end > 1 && is_sep(chars[end - 1]) {
    end -= 1
  }
  let mut i = end
  while i > 0 && !is_sep(chars[i - 1]) {
    i -= 1
  }
  if i == 0 {
    return ""
  }
  let mut j = i - 1
  while j > 0 && is_sep(chars[j - 1]) {
    j -= 1
  }
  if j == 0 {
    // The root.
    return String::from_array(chars[:1])
  }
  String::from_array(chars[:j])
}

///|
/// The last component of a path.
pub fn path_file_name(path : String) -> String {
  let chars = path.to_array()
  let mut end = chars.length()
  let is_sep = (c : Char) => c == '/' || (is_windows() && c == '\\')
  while end > 0 && is_sep(chars[end - 1]) {
    end -= 1
  }
  let mut i = end
  while i > 0 && !is_sep(chars[i - 1]) {
    i -= 1
  }
  String::from_array(chars[i:end])
}

///|
async fn FileParser::read_test_contents(
  self : FileParser,
  path : String,
  into : Array[(String, String)],
) -> Unit {
  let kind = @fs.kind(path, follow_symlink=true) catch {
    e => raise AppError(["read metadata from path", "\{e}"])
  }
  if kind is Directory {
    let entries = @fs.readdir(path, include_hidden=true, sort=true) catch {
      e => raise AppError(["list tests documents in directory", "\{e}"])
    }
    for entry in entries {
      self.read_test_contents(path_join(path, entry), into)
    }
  } else if self.accept(path) {
    let data = @fs.read_file(path) catch {
      e => raise AppError(["read contents from test document", "\{e}"])
    }
    let bytes = @text.replace_crlf(data.binary())
    match @text.utf8_string(bytes) {
      Some(text) => into.push((path, text))
      None => raise AppError(["content file `\{path}` is not utf-8 encoded"])
    }
  }
}

///|
/// Read the test documents at `paths` (directories recursively, in sorted
/// order) and parse them.
pub async fn FileParser::find_and_parse(
  self : FileParser,
  name : String,
  paths : Array[String],
  cram_compat : Bool,
) -> Array[ParsedTestFile] {
  let contents = []
  for path in paths {
    let exists = @fs.exists(path) catch { _ => false }
    if !exists {
      raise AppError([
        "read contents from \{name} document path(s)",
        "path `\{path}` does not exist",
      ])
    }
    self.read_test_contents(path, contents) catch {
      AppError(_) as e =>
        raise e
          .context("scan provided path \{path}")
          .context("read contents from \{name} document path(s)")
      e => raise e
    }
  }
  let result = []
  for entry in contents {
    let (path, content) = entry
    let parser_type : @document.ParserType = if self.match_markdown.is_match(
        path,
      ) {
      Markdown
    } else {
      Cram
    }
    let parsed = try {
      match parser_type {
        Markdown =>
          @document.parse_markdown(
            content,
            languages=self.markdown_languages,
            cram_compat~,
          )
        Cram => @document.parse_cram(content)
      }
    } catch {
      e =>
        raise AppError([
          "Failed to parse \{name} from \{rust_debug_string(path)} with \{parser_type.to_string()} parser",
          "\{e}",
        ])
    }
    result.push({
      path,
      parser_type,
      testcases: parsed.testcases,
      config: parsed.config,
    })
  }
  result
}

///|
/// A string quoted like Rust's `Debug` for strings and paths.
fn rust_debug_string(s : String) -> String {
  let buf = StringBuilder()
  buf.write_char('"')
  for c in s {
    match c {
      '"' => buf.write_string("\\\"")
      '\\' => buf.write_string("\\\\")
      '\n' => buf.write_string("\\n")
      '\r' => buf.write_string("\\r")
      '\t' => buf.write_string("\\t")
      _ => buf.write_char(c)
    }
  }
  buf.write_char('"')
  buf.to_string()
}
