// Regex expectations (upstream src/rules/regex.rs): the Cram-compatible
// fix-ups, then a translation from Rust `regex` syntax to
// `moonbitlang/regexp`.

///|
/// An invalid expectation (unknown rule, bad escape or regex).
pub(all) suberror RuleError {
  RuleError(String)
} derive(Debug)

///|
pub impl Show for RuleError with fn output(self, logger) {
  let RuleError(msg) = self
  logger.write_string(msg)
}

///|
/// Remove backslashes before characters that need no escaping (`\_` → `_`),
/// keeping regex meta characters and letters (`\d`).
pub fn cleanup_unrecognized_escape_sequences(expression : String) -> String {
  let chars = expression.to_array()
  let buf = StringBuilder()
  let mut i = 0
  while i < chars.length() {
    let c = chars[i]
    i += 1
    if c != '\\' {
      buf.write_char(c)
      continue
    }
    if i >= chars.length() {
      buf.write_char(c)
      continue
    }
    let c2 = chars[i]
    i += 1
    match c2 {
      '['
      | ']'
      | '{'
      | '}'
      | '('
      | ')'
      | '|'
      | '?'
      | '*'
      | '+'
      | '-'
      | '.'
      | '^'
      | '$'
      | '\\'
      | 'a'..='z'
      | 'A'..='Z' => buf.write_char(c)
      _ => ()
    }
    buf.write_char(c2)
  }
  buf.to_string()
}

///|
/// Whether `chars[i..]` starts a valid repetition `{n}` / `{n,m}`; returns the
/// index after the closing brace.
fn valid_repetition(chars : Array[Char], i : Int) -> Int? {
  guard i < chars.length() && chars[i] == '{' else { return None }
  let mut j = i + 1
  let digits = (start : Int) => {
    let mut k = start
    while k < chars.length() && chars[k] >= '0' && chars[k] <= '9' {
      k += 1
    }
    k
  }
  let k = digits(j)
  if k == j {
    return None
  }
  j = k
  if j < chars.length() && chars[j] == ',' {
    let k2 = digits(j + 1)
    if k2 == j + 1 {
      return None
    }
    j = k2
  }
  if j < chars.length() && chars[j] == '}' {
    Some(j + 1)
  } else {
    None
  }
}

///|
/// Escape curly braces that are not a repetition quantifier (`hello{world}`),
/// which Rust's regex would reject.
pub fn escape_misused_repetition_quantifier(expression : String) -> String {
  // Upstream protects valid quantifiers as `<<<<n,m>>>>`, escapes all other
  // braces (skipping escaped characters), then restores the quantifiers.
  let chars = expression.to_array()
  let protected = StringBuilder()
  let mut i = 0
  while i < chars.length() {
    match valid_repetition(chars, i) {
      Some(end) => {
        protected.write_string("<<<<")
        for k in (i + 1)..<(end - 1) {
          protected.write_char(chars[k])
        }
        protected.write_string(">>>>")
        i = end
      }
      None => {
        protected.write_char(chars[i])
        i += 1
      }
    }
  }
  let chars = protected.to_string().to_array()
  let escaped = StringBuilder()
  let mut i = 0
  while i < chars.length() {
    let c = chars[i]
    i += 1
    match c {
      '\\' => {
        escaped.write_char(c)
        if i < chars.length() {
          escaped.write_char(chars[i])
          i += 1
        }
      }
      '{' | '}' => {
        escaped.write_char('\\')
        escaped.write_char(c)
      }
      _ => escaped.write_char(c)
    }
  }
  // Restore `<<<<x>>>>` (lazily, like the `<<<<(.+?)>>>>` replacement).
  let s = escaped.to_string()
  let chars = s.to_array()
  let out = StringBuilder()
  let mut i = 0
  let starts = (k : Int, lit : String) => {
    let l = lit.to_array()
    if k + l.length() > chars.length() {
      return false
    }
    for j in 0..<l.length() {
      if chars[k + j] != l[j] {
        return false
      }
    }
    true
  }
  while i < chars.length() {
    if starts(i, "<<<<") {
      // `.+?`: at least one character, then the first `>>>>`.
      let mut j = i + 5
      let mut found = -1
      while j + 4 <= chars.length() {
        if starts(j, ">>>>") {
          found = j
          break
        }
        j += 1
      }
      if found >= 0 {
        out.write_char('{')
        for k in (i + 4)..<found {
          out.write_char(chars[k])
        }
        out.write_char('}')
        i = found + 4
        continue
      }
    }
    out.write_char(chars[i])
    i += 1
  }
  out.to_string()
}

///|
/// Escape square brackets inside a character class (`[[]]` → `[\[\]]`).
pub fn escape_misused_character_class(expression : String) -> String {
  let chars = expression.to_array()
  let actual_closing_index = (idx : Int) => {
    let mut idx = idx
    while idx < chars.length() {
      if chars[idx - 1] != '\\' {
        if chars[idx] == ']' {
          return Some(idx)
        } else if chars[idx] == '[' {
          return None
        }
      }
      idx += 1
    }
    None
  }
  let out = StringBuilder()
  let mut index = 0
  let mut in_cc = false
  while index < chars.length() {
    let c = chars[index]
    index += 1
    match c {
      '\\' => {
        out.write_char(c)
        if index < chars.length() {
          out.write_char(chars[index])
          index += 1
        }
      }
      '[' => {
        if in_cc {
          out.write_char('\\')
        } else {
          in_cc = true
        }
        out.write_char(c)
      }
      ']' => {
        if in_cc && actual_closing_index(index) is None {
          in_cc = false
        } else {
          out.write_char('\\')
        }
        out.write_char(c)
      }
      _ => out.write_char(c)
    }
  }
  out.to_string()
}

///|
/// Upstream's fix-ups, in upstream's order.
pub fn fixup_regex(expression : String) -> String {
  expression
  |> cleanup_unrecognized_escape_sequences
  |> escape_misused_repetition_quantifier
  |> escape_misused_character_class
}

///|
fn posix_class(name : String) -> String? {
  match name {
    "alpha" => Some("a-zA-Z")
    "digit" => Some("0-9")
    "alnum" => Some("a-zA-Z0-9")
    "upper" => Some("A-Z")
    "lower" => Some("a-z")
    "space" => Some(" \\t\\n\\r\\f\\u{0b}")
    "blank" => Some(" \\t")
    "xdigit" => Some("0-9A-Fa-f")
    "word" => Some("0-9A-Za-z_")
    "punct" => Some("!-/:-@\\[-`{-~")
    "cntrl" => Some("\\u{0}-\\u{1f}\\u{7f}")
    "print" => Some(" -~")
    "graph" => Some("!-~")
    "ascii" => Some("\\u{0}-\\u{7f}")
    _ => None
  }
}

///|
fn is_regex_meta(c : Char) -> Bool {
  match c {
    '\\'
    | '.'
    | '+'
    | '*'
    | '?'
    | '('
    | ')'
    | '|'
    | '['
    | ']'
    | '{'
    | '}'
    | '^'
    | '$'
    | '-'
    | '#'
    | '&'
    | '~' => true
    _ => false
  }
}

///|
/// One translated atom (with its quantifiers) of a regex being translated.
priv struct Atom {
  mut text : String
  /// Whether a repetition quantifier has been applied.
  mut quantified : Bool
  /// Whether the last thing appended was a quantifier (so `?` would make it
  /// lazy).
  mut after_quantifier : Bool
  /// Group start marker (an open parenthesis not yet closed).
  group_start : Bool
  /// Alternation: not repeatable.
  repeatable : Bool
  /// A zero-width assertion (`^`, `$`, `\b`, `\B`): Rust allows repeating
  /// it; with a minimum of zero repetitions it becomes optional (empty).
  assertion : Bool
}

///|
fn Atom::new(text : String) -> Atom {
  {
    text,
    quantified: false,
    after_quantifier: false,
    group_start: false,
    repeatable: true,
    assertion: false,
  }
}

///|
/// The members of Rust's Unicode `\w` class: alphabetic characters
/// (letters, letter numbers and the alphabetic symbols among
/// `Other_Alphabetic`), marks, decimal digits, connector punctuation and
/// join controls.
let word_class : String = "\\p{L}\\p{Nl}\\p{M}\\p{Nd}\\p{Pc}\\u{200C}\\u{200D}\\u{24B6}-\\u{24E9}\\u{1F130}-\\u{1F149}\\u{1F150}-\\u{1F169}\\u{1F170}-\\u{1F189}"

///|
/// The members of Rust's Unicode `\s` class (`White_Space`).
let space_class : String = "\\t\\n\\u{B}\\u{C}\\r \\u{85}\\u{A0}\\u{1680}\\u{2000}-\\u{200A}\\u{2028}\\u{2029}\\u{202F}\\u{205F}\\u{3000}"

///|
/// Letters Rust's regex accepts after a backslash.
fn is_rust_escape_letter(c : Char) -> Bool {
  match c {
    'a'
    | 'f'
    | 't'
    | 'n'
    | 'r'
    | 'v'
    | 'x'
    | 'u'
    | 'U'
    | 'd'
    | 'D'
    | 's'
    | 'S'
    | 'w'
    | 'W'
    | 'p'
    | 'P'
    | 'A'
    | 'z'
    | 'b'
    | 'B' => true
    _ => false
  }
}

///|
/// Translate Rust `regex` syntax into `moonbitlang/regexp` syntax. Features
/// the target engine lacks (inline flags, class set operations) are errors.
/// With `start_anchor` (`end_anchor`) off, `^` (`$`) never matches: for
/// matching a part of the text that does not start (end) it.
pub fn translate_rust_regex(
  expression : String,
  start_anchor? : Bool = true,
  end_anchor? : Bool = true,
) -> String raise RuleError {
  let chars = expression.to_array()
  let n = chars.length()
  let units : Array[Atom] = []
  let mut i = 0
  let hex_ok = (s : ArrayView[Char]) => {
    s.length() > 0 &&
    s
    .iter()
    .all(c => {
      (c >= '0' && c <= '9') || (c >= 'a' && c <= 'f') || (c >= 'A' && c <= 'F')
    })
  }
  let fail = (msg : String) => RuleError("\{msg} in regex `\{expression}`")
  // Translate one escape starting at `i` (a backslash); returns the
  // translated text and the index after it.
  let escape = (i : Int, in_class : Bool) => {
    guard i + 1 < n else { raise fail("trailing backslash") }
    let c2 = chars[i + 1]
    if c2 == 'x' {
      if i + 2 < n && chars[i + 2] == '{' {
        let mut j = i + 3
        while j < n && chars[j] != '}' {
          j += 1
        }
        guard j < n && hex_ok(chars[i + 3:j]) else {
          raise fail("invalid hex escape")
        }
        ("\\u{" + String::from_array(chars[i + 3:j]) + "}", j + 1)
      } else {
        guard i + 3 < n && hex_ok(chars[i + 2:i + 4]) else {
          raise fail("invalid hex escape")
        }
        ("\\u{" + String::from_array(chars[i + 2:i + 4]) + "}", i + 4)
      }
    } else if c2 == 'u' || c2 == 'U' {
      let width = if c2 == 'u' { 4 } else { 8 }
      if i + 2 < n && chars[i + 2] == '{' {
        let mut j = i + 3
        while j < n && chars[j] != '}' {
          j += 1
        }
        guard j < n && hex_ok(chars[i + 3:j]) else {
          raise fail("invalid unicode escape")
        }
        ("\\u{" + String::from_array(chars[i + 3:j]) + "}", j + 1)
      } else {
        guard i + 2 + width <= n && hex_ok(chars[i + 2:i + 2 + width]) else {
          raise fail("invalid unicode escape")
        }
        (
          "\\u{" + String::from_array(chars[i + 2:i + 2 + width]) + "}",
          i + 2 + width,
        )
      }
    } else if (c2 == 'p' || c2 == 'P') && i + 2 < n && chars[i + 2] != '{' {
      ("\\" + c2.to_string() + "{" + chars[i + 2].to_string() + "}", i + 3)
    } else if c2 == 'w' {
      // Rust's `\w` is Unicode aware, the target engine's is ASCII only.
      (if in_class { word_class } else { "[" + word_class + "]" }, i + 2)
    } else if c2 == 'W' && !in_class {
      ("[^" + word_class + "]", i + 2)
    } else if c2 == 's' {
      (if in_class { space_class } else { "[" + space_class + "]" }, i + 2)
    } else if c2 == 'S' && !in_class {
      ("[^" + space_class + "]", i + 2)
    } else if c2 == 'd' {
      ("\\p{Nd}", i + 2)
    } else if c2 == 'D' {
      ("\\P{Nd}", i + 2)
    } else if c2 == 'A' && !in_class {
      ("^", i + 2)
    } else if c2 == 'z' && !in_class {
      ("$", i + 2)
    } else if c2.is_ascii_alphabetic() && !is_rust_escape_letter(c2) {
      raise fail("unrecognized escape sequence `\\\{c2}`")
    } else {
      ("\\" + c2.to_string(), i + 2)
    }
  }
  while i < n {
    let c = chars[i]
    match c {
      '\\' => {
        let (text, next) = escape(i, false)
        i = next
        if text == "^" || text == "$" || text == "\\b" || text == "\\B" {
          units.push({ ..Atom::new(text), assertion: true, })
        } else {
          units.push(Atom::new(text))
        }
      }
      '[' => {
        // A character class, up to its closing bracket.
        let buf = StringBuilder()
        buf.write_char('[')
        let mut j = i + 1
        if j < n && chars[j] == '^' {
          buf.write_char('^')
          j += 1
        }
        // A leading `]` is literal.
        if j < n && chars[j] == ']' {
          buf.write_string("\\]")
          j += 1
        }
        let mut closed = false
        while j < n {
          let d = chars[j]
          if d == ']' {
            closed = true
            j += 1
            break
          } else if d == '\\' {
            let (text, next) = escape(j, true)
            buf.write_string(text)
            j = next
          } else if d == '[' && j + 1 < n && chars[j + 1] == ':' {
            let mut k = j + 2
            while k + 1 < n && !(chars[k] == ':' && chars[k + 1] == ']') {
              k += 1
            }
            let name = String::from_array(chars[j + 2:k])
            guard k + 1 < n && posix_class(name) is Some(ranges) else {
              raise fail("unsupported character class `[:\{name}:]`")
            }
            buf.write_string(ranges)
            j = k + 2
          } else if (d == '&' || d == '-' || d == '~') &&
            j + 1 < n &&
            chars[j + 1] == d {
            raise fail("character class set operations are not supported")
          } else if d == '[' {
            raise fail("nested character classes are not supported")
          } else {
            buf.write_char(d)
            j += 1
          }
        }
        guard closed else { raise fail("unclosed character class") }
        buf.write_char(']')
        units.push(Atom::new(buf.to_string()))
        i = j
      }
      '(' =>
        if i + 1 < n && chars[i + 1] == '?' {
          let next = if i + 2 < n { chars[i + 2] } else { ' ' }
          guard next == ':' || next == '<' || next == 'P' else {
            raise fail("inline regex flags (`(?...)`) are not supported")
          }
          // Copy the group prefix up to `:` or the name's `>`.
          let mut j = i + 2
          while j < n && chars[j] != ':' && chars[j] != '>' {
            j += 1
          }
          let prefix = if next == 'P' {
            // `(?P<name>` → `(?<name>`
            "(?" + String::from_array(chars[i + 3:j + 1])
          } else {
            String::from_array(chars[i:j + 1])
          }
          units.push({ ..Atom::new(prefix), group_start: true, })
          i = j + 1
        } else {
          units.push({ ..Atom::new("("), group_start: true, })
          i += 1
        }
      ')' => {
        // Merge the group's units into one atom.
        let mut k = units.length() - 1
        while k >= 0 && !units[k].group_start {
          k -= 1
        }
        guard k >= 0 else { raise fail("unopened group") }
        let buf = StringBuilder()
        for u in units[k:] {
          buf.write_string(u.text)
        }
        buf.write_char(')')
        units.truncate(k)
        units.push(Atom::new(buf.to_string()))
        i += 1
      }
      '|' => {
        units.push({ ..Atom::new("|"), repeatable: false, })
        i += 1
      }
      '^' | '$' => {
        units.push({ ..Atom::new(c.to_string()), assertion: true, })
        i += 1
      }
      '.' => {
        // Rust's `.` matches everything but a line feed (the target
        // engine's also excludes a carriage return).
        units.push(Atom::new("[^\\n]"))
        i += 1
      }
      '*' | '+' | '?' | '{' => {
        // A quantifier (a `{` here is a valid repetition after the fix-ups).
        let mut j = i + 1
        if c == '{' {
          while j < n && chars[j] != '}' {
            j += 1
          }
          j += 1
        }
        let q = String::from_array(chars[i:j.min(n)])
        guard units.length() > 0 &&
          units[units.length() - 1].repeatable &&
          !units[units.length() - 1].group_start else {
          raise fail("repetition operator missing expression")
        }
        let u = units[units.length() - 1]
        if u.assertion {
          // `^*` may repeat zero times (an optional assertion: empty); `^+`
          // is the assertion itself. Laziness does not matter.
          if !(c == '?' && u.after_quantifier) {
            let min_zero = c == '*' || c == '?' || q.has_prefix("{0")
            if min_zero {
              u.text = ""
            }
          }
          u.after_quantifier = true
          i = j
          continue
        }
        if c == '?' && u.after_quantifier {
          // A lazy quantifier.
          u.text = u.text + "?"
          u.after_quantifier = false
        } else if u.quantified {
          // Repetition of a repetition: `a**` is `(?:a*)*`.
          u.text = "(?:" + u.text + ")" + q
          u.after_quantifier = true
        } else {
          u.text = u.text + q
          u.quantified = true
          u.after_quantifier = true
        }
        i = j
      }
      _ => {
        units.push(Atom::new(c.to_string()))
        i += 1
      }
    }
  }
  let out = StringBuilder()
  for u in units {
    if u.assertion &&
      ((u.text == "^" && !start_anchor) || (u.text == "$" && !end_anchor)) {
      out.write_string(impossible)
    } else {
      out.write_string(u.text)
    }
  }
  out.to_string()
}

///|
/// A class that matches nothing.
let impossible : String = "[^\\s\\S]"

///|
/// A compiled regex expectation: upstream's fix-ups applied, matching the
/// whole line.
pub struct RegexMatcher {
  expression : String
  priv regexp : @regexp.Regexp
  /// Whether the pattern uses `\b`/`\B` (see `RegexMatcher::matches`).
  priv word_boundary : Bool
  /// Variants with the start and/or end anchor disabled, compiled when
  /// output that is not valid UTF-8 is matched.
  priv variants : Map[(Bool, Bool), @regexp.Regexp]
}

///|
pub fn RegexMatcher::new(expression : String) -> RegexMatcher raise RuleError {
  let fixed = fixup_regex(expression)
  // The anchors take part in translation: upstream compiles `^expr$`, and a
  // leading quantifier repeats the `^`.
  let translated = translate_rust_regex("^" + fixed + "$")
  let regexp = @regexp.compile(translated) catch {
    e => raise RuleError("invalid regex `\{fixed}`: \{e}")
  }
  let word_boundary = translated.contains("\\b") || translated.contains("\\B")
  { expression: fixed, regexp, word_boundary, variants: Map([]), }
}

///|
fn RegexMatcher::matches_text(
  self : RegexMatcher,
  regexp : @regexp.Regexp,
  line : String,
) -> Bool {
  // Workaround: `moonbitlang/regexp` 0.3.5 panics evaluating a word boundary
  // next to a non-BMP character (it reads a lone low surrogate). Such
  // characters are not word characters, so a BMP non-word placeholder keeps
  // the boundaries (only a literal non-BMP character in the pattern would no
  // longer match).
  let line = if self.word_boundary && line.iter().any(c => c.to_int() > 0xFFFF) {
    String::from_iter(
      line.iter().map(c => if c.to_int() > 0xFFFF { '\u{FFFD}' } else { c }),
    )
  } else {
    line
  }
  regexp.execute(line).matched()
}

///|
/// Whether the regex matches the whole line (without its line feed).
pub fn RegexMatcher::matches(self : RegexMatcher, line : String) -> Bool {
  self.matches_text(self.regexp, line)
}

///|
/// Whether the regex matches output bytes (without the line feed) like
/// upstream's Unicode byte regex: a match never covers bytes that are not
/// valid UTF-8, so it lies within a valid part, where `^` and `$` hold only
/// at the start and end of the whole line.
pub fn RegexMatcher::matches_bytes(
  self : RegexMatcher,
  line : BytesView,
) -> Bool {
  if @text.utf8_string(line) is Some(text) {
    return self.matches_text(self.regexp, text)
  }
  for segment in @text.utf8_segments(line) {
    let (start, text, end) = segment
    let key = (start == 0, end == line.length())
    let regexp = match self.variants.get(key) {
      Some(r) => r
      None => {
        let r = @regexp.compile(
          translate_rust_regex(
            "^" + self.expression + "$",
            start_anchor=key.0,
            end_anchor=key.1,
          ),
        ) catch {
          _ => continue
        }
        self.variants[key] = r
        r
      }
    }
    if self.matches_text(regexp, text) {
      return true
    }
  }
  false
}
