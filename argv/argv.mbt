// Turning a test case's command into a program and its arguments, without a
// shell. Only commands that mean exactly the same thing to bash are accepted:
// one simple command with POSIX quoting; the only expansion is `$NAME` /
// `${NAME}` inside double quotes (see PLAN.md).

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
/// A part of a word: literal text or a variable reference.
priv enum Segment {
  Text(String)
  Var(String)
}

///|
/// A word with facts about its raw (unquoted) spelling.
priv struct Word {
  segments : Array[Segment]
  /// Every character was unquoted and unescaped.
  plain : Bool
  /// The raw text starts with `NAME=` (unquoted name): an assignment of the
  /// segments after the `=`.
  assignment : (String, Array[Segment])?
}

///|
/// Variables bash manages itself: their values in bash need not be the
/// environment's, so references to them are rejected.
let shell_variables : ReadOnlyArray[String] = [
  "BASHOPTS", "BASHPID", "BASH_ALIASES", "BASH_ARGC", "BASH_ARGV", "BASH_ARGV0",
  "BASH_CMDS", "BASH_COMMAND", "BASH_EXECUTION_STRING", "BASH_LINENO", "BASH_REMATCH",
  "BASH_SOURCE", "BASH_SUBSHELL", "BASH_VERSINFO", "BASH_VERSION", "BASH", "COMP_WORDBREAKS",
  "DIRSTACK", "EPOCHREALTIME", "EPOCHSECONDS", "EUID", "FUNCNAME", "GROUPS", "HISTCMD",
  "HOSTNAME", "HOSTTYPE", "IFS", "LINENO", "MACHTYPE", "OLDPWD", "OPTARG", "OPTIND",
  "OSTYPE", "PIPESTATUS", "PPID", "PS4", "PWD", "RANDOM", "REPLY", "SECONDS", "SHELLOPTS",
  "SHLVL", "SRANDOM", "UID",
]

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
    '<' | '>' =>
      "redirections (`\{c}`) are not supported; use the `stdin` configuration for input"
    '(' | ')' => "subshells and grouping (`\{c}`) are not supported"
    '`' => "command substitution (`` ` ``) is not supported"
    '$' =>
      "unquoted `$` is not supported; write \"$NAME\" (in double quotes) to use a variable"
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
    let segments : Array[Segment] = []
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
            if d == '$' {
              // `$NAME` or `${NAME}`.
              let (name, next) = variable_reference(chars, j)
              if !buf.is_empty() {
                segments.push(Text(buf.to_string()))
                buf.reset()
              }
              segments.push(Var(name))
              j = next
              continue
            }
            if d == '`' {
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
        '|'
        | '&'
        | ';'
        | '<'
        | '>'
        | '('
        | ')'
        | '`'
        | '$'
        | '*'
        | '?'
        | '['
        | '{'
        | '}' => raise not_supported(c)
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
    if !buf.is_empty() || segments.is_empty() {
      segments.push(Text(buf.to_string()))
    }
    // The `=` of an assignment is in the unquoted prefix: the first segment.
    let assignment = match (assignment_at, segments[0]) {
      (Some(at), Text(first)) => {
        let value = [Text(first[at + 1:].to_owned())]
        value.append(segments[1:].to_owned())
        Some((first[:at].to_owned(), value))
      }
      _ => None
    }
    out.push({ segments, plain, assignment, })
  }
  out
}

///|
fn is_name(name : String) -> Bool {
  let chars = name.to_array()
  chars.length() > 0 &&
  is_name_start(chars[0]) &&
  chars.iter().all(is_name_char)
}

///|
/// The variable name of a `$NAME` or `${NAME}` reference at `chars[i]` (a
/// `$` inside double quotes) and the index after it.
fn variable_reference(
  chars : Array[Char],
  i : Int,
) -> (String, Int) raise ArgvError {
  let n = chars.length()
  let hint = "only $NAME and ${NAME} are supported"
  let name_and_next = if i + 1 < n && chars[i + 1] == '{' {
    let mut j = i + 2
    while j < n && chars[j] != '}' && chars[j] != '"' {
      j += 1
    }
    let name = String::from_array(chars[i + 2:j])
    guard j < n && chars[j] == '}' && is_name(name) else {
      let text = String::from_array(chars[i:j.min(n - 1) + 1])
      raise ArgvError("`\{text}` is not supported: \{hint}")
    }
    (name, j + 1)
  } else if i + 1 < n && is_name_start(chars[i + 1]) {
    let mut j = i + 1
    while j < n && is_name_char(chars[j]) {
      j += 1
    }
    (String::from_array(chars[i + 1:j]), j)
  } else {
    let text = if i + 1 < n && chars[i + 1] != '"' {
      "$" + chars[i + 1].to_string()
    } else {
      "$"
    }
    raise ArgvError(
      "`\{text}` is not supported: \{hint} (write \\$ for a literal `$`)",
    )
  }
  let (name, _) = name_and_next
  if shell_variables.contains(name) {
    raise ArgvError(
      "`$\{name}` is not supported: bash manages `\{name}` itself",
    )
  }
  name_and_next
}

///|
/// A variable's value in `env` (empty when unset, as in bash).
fn lookup(env : ArrayView[(String, String)], name : String) -> String {
  for i = env.length() - 1; i >= 0; i = i - 1 {
    if env[i].0 == name {
      return env[i].1
    }
  }
  ""
}

///|
fn expand(
  segments : Array[Segment],
  env : ArrayView[(String, String)],
) -> String {
  let buf = StringBuilder()
  for segment in segments {
    match segment {
      Text(t) => buf.write_string(t)
      Var(name) => buf.write_string(lookup(env, name))
    }
  }
  buf.to_string()
}

///|
/// The words of a command as bash would pass them (no assignment
/// handling), with variables looked up in `env`.
pub fn tokenize(
  expr : String,
  env? : Array[(String, String)] = [],
) -> Array[String] raise ArgvError {
  words(expr).map(w => expand(w.segments, env))
}

///|
/// Words bash treats as syntax in command position (when unquoted).
let reserved_words : ReadOnlyArray[String] = [
  "if", "then", "else", "elif", "fi", "case", "esac", "for", "select", "while", "until",
  "do", "done", "function", "time", "coproc", "!", "[[", "]]",
]

///|
/// Parse a command: leading assignments, then the program and its
/// arguments. Variables are looked up in `env`, the environment before the
/// command's own assignments (as bash expands them).
pub fn parse_command(
  expr : String,
  env? : Array[(String, String)] = [],
) -> Command raise ArgvError {
  let ws = words(expr)
  let assignments : Array[(String, String)] = []
  let mut k = 0
  while k < ws.length() && ws[k].assignment is Some((name, value)) {
    // Bash versions disagree whether an assignment sees an earlier one in
    // the same command.
    for segment in value {
      if segment is Var(v) && assignments.iter().any(a => a.0 == v) {
        raise ArgvError(
          "`$\{v}` refers to `\{v}` assigned earlier in the same command; use the `environment` configuration",
        )
      }
    }
    assignments.push((name, expand(value, env)))
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
  let program_text = expand(program.segments, env)
  if program.plain && reserved_words.contains(program_text) {
    raise ArgvError("shell syntax (`\{program_text}`) is not supported")
  }
  { env: assignments, argv: ws[k:].map(w => expand(w.segments, env)), }
}
