// Turning a test case's command into a program and its arguments, without a
// shell. Only commands that mean exactly the same thing to bash are accepted:
// one simple command with POSIX quoting, no expansions (see PLAN.md).

///|
/// A command that cannot be run without a shell.
pub(all) suberror ArgvError {
  ArgvError(String)
} derive(Debug)

///|
pub impl Show for ArgvError with fn output(self, logger) {
  let ArgvError(msg) = self
  logger.write_string(msg)
}

///|
/// A program invocation: leading `NAME=value` assignments and the words.
pub(all) struct Command {
  env : Array[(String, String)]
  argv : Array[String]
} derive(Eq, Debug)

///|
/// A word with facts about its raw (unquoted) spelling.
priv struct Word {
  text : String
  /// Every character was unquoted and unescaped.
  plain : Bool
  /// The raw text starts with `NAME=` (unquoted name): an assignment.
  assignment : (String, String)?
}

///|
fn is_name_start(c : Char) -> Bool {
  (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || c == '_'
}

///|
fn is_name_char(c : Char) -> Bool {
  is_name_start(c) || (c >= '0' && c <= '9')
}

///|
fn describe(c : Char) -> String {
  match c {
    '|' => "pipes (`|`) are not supported"
    '&' => "background jobs and `&&` (`&`) are not supported"
    ';' => "command lists (`;`) are not supported"
    '<' | '>' => "redirections (`\{c}`) are not supported; use the `stdin` configuration for input"
    '(' | ')' => "subshells and grouping (`\{c}`) are not supported"
    '`' => "command substitution (`` ` ``) is not supported"
    '$' => "variable expansion (`$`) is not supported; use the `environment` configuration"
    '*' | '?' | '[' => "glob patterns (`\{c}`) are not supported"
    '{' | '}' => "brace expansion (`\{c}`) is not supported"
    '~' => "tilde expansion (`~`) is not supported"
    '#' => "comments (`#`) are not supported"
    _ => "`\{c}` is not supported"
  }
}

///|
fn not_supported(c : Char) -> ArgvError {
  ArgvError("\{describe(c)} (quote '\{c}' to pass it literally)")
}

///|
/// Split a command into words with POSIX quoting; every shell feature beyond
/// quoting is an error.
fn words(expr : String) -> Array[Word] raise ArgvError {
  let chars = expr.to_array()
  let n = chars.length()
  let out : Array[Word] = []
  let mut i = 0
  while i < n {
    let c = chars[i]
    // Between words.
    if c == ' ' || c == '\t' {
      i += 1
      continue
    }
    if c == '\\' && i + 1 < n && chars[i + 1] == '\n' {
      i += 2
      continue
    }
    if c == '\n' {
      raise ArgvError(
        "one command per test case: end continuation lines with `\\` to continue the command",
      )
    }
    // A word.
    let buf = StringBuilder()
    let mut plain = true
    // Unquoted prefix of the raw word, for assignment detection.
    let raw_prefix = StringBuilder()
    let mut prefix_open = true
    let mut assignment_at : Int? = None
    let word_start = i
    let mut ends = false
    while i < n && !ends {
      let c = chars[i]
      match c {
        ' ' | '\t' | '\n' => ends = true
        '\'' => {
          plain = false
          prefix_open = false
          let mut j = i + 1
          while j < n && chars[j] != '\'' {
            buf.write_char(chars[j])
            j += 1
          }
          if j >= n {
            raise ArgvError("unmatched single quote")
          }
          i = j + 1
        }
        '"' => {
          plain = false
          prefix_open = false
          let mut j = i + 1
          while j < n && chars[j] != '"' {
            let d = chars[j]
            if d == '\\' && j + 1 < n {
              let e = chars[j + 1]
              match e {
                '$' | '`' | '"' | '\\' => {
                  buf.write_char(e)
                  j += 2
                }
                '\n' => j += 2
                _ => {
                  buf.write_char('\\')
                  j += 1
                }
              }
              continue
            }
            if d == '$' || d == '`' {
              raise not_supported(d)
            }
            if d == '\u{0}' {
              raise ArgvError("NUL characters are not supported")
            }
            buf.write_char(d)
            j += 1
          }
          if j >= n {
            raise ArgvError("unmatched double quote")
          }
          i = j + 1
        }
        '\\' => {
          if i + 1 >= n {
            raise ArgvError("trailing backslash")
          }
          let e = chars[i + 1]
          i += 2
          if e == '\n' {
            // A continuation inside a word joins it.
            continue
          }
          plain = false
          prefix_open = false
          buf.write_char(e)
        }
        '|' | '&' | ';' | '<' | '>' | '(' | ')' | '`' | '$' | '*' | '?' | '['
        | '{' | '}' => raise not_supported(c)
        '\u{0}' => raise ArgvError("NUL characters are not supported")
        '#' if i == word_start => raise not_supported(c)
        '~' if i == word_start => raise not_supported(c)
        '~' if assignment_at is Some(_) &&
          (chars[i - 1] == '=' || chars[i - 1] == ':') => raise not_supported(c)
        _ => {
          if prefix_open {
            if c == '=' && assignment_at is None {
              let name = raw_prefix.to_string()
              let name_chars = name.to_array()
              if name_chars.length() > 0 &&
                is_name_start(name_chars[0]) &&
                name_chars.iter().all(is_name_char) {
                assignment_at = Some(buf.to_string().length())
              }
              prefix_open = false
            } else {
              raw_prefix.write_char(c)
            }
          }
          buf.write_char(c)
          i += 1
        }
      }
    }
    let text = buf.to_string()
    let assignment = match assignment_at {
      Some(at) => Some((text[:at].to_owned(), text[at + 1:].to_owned()))
      None => None
    }
    out.push({ text, plain, assignment })
  }
  out
}

///|
/// The words of a command as bash would pass them (no assignment
/// handling).
pub fn tokenize(expr : String) -> Array[String] raise ArgvError {
  words(expr).map(w => w.text)
}

///|
/// Words bash treats as syntax in command position (when unquoted).
let reserved_words : ReadOnlyArray[String] = [
  "if", "then", "else", "elif", "fi", "case", "esac", "for", "select", "while",
  "until", "do", "done", "function", "time", "coproc", "!", "[[", "]]",
]

///|
/// Parse a command: leading assignments, then the program and its
/// arguments.
pub fn parse_command(expr : String) -> Command raise ArgvError {
  let ws = words(expr)
  let env = []
  let mut k = 0
  while k < ws.length() && ws[k].assignment is Some((name, value)) {
    env.push((name, value))
    k += 1
  }
  if k >= ws.length() {
    if ws.is_empty() {
      raise ArgvError("empty command")
    }
    raise ArgvError(
      "no program to run: a command made only of assignments is not supported; use the `environment` configuration",
    )
  }
  let program = ws[k]
  if program.plain && reserved_words.contains(program.text) {
    raise ArgvError("shell syntax (`\{program.text}`) is not supported")
  }
  { env, argv: ws[k:].map(w => w.text) }
}
