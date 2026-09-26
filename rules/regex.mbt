// Regex expectations (upstream src/rules/regex.rs): the Cram-compatible
// fix-ups, then Rust `regex` syntax compiled (`regex_compile.mbt`) for the
// core regex engine, `@string.Regex`.

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
  let shielded = StringBuilder()
  let mut i = 0
  while i < chars.length() {
    match valid_repetition(chars, i) {
      Some(end) => {
        shielded.write_string("<<<<")
        for k in (i + 1)..<(end - 1) {
          shielded.write_char(chars[k])
        }
        shielded.write_string(">>>>")
        i = end
      }
      None => {
        shielded.write_char(chars[i])
        i += 1
      }
    }
  }
  let chars = shielded.to_string().to_array()
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
/// A compiled regex expectation: upstream's fix-ups applied, matching the
/// whole line.
pub struct RegexMatcher {
  expression : String
  priv regex : @string.Regex
  /// Variants with the start and/or end anchor disabled, compiled when
  /// output that is not valid UTF-8 is matched.
  priv variants : Map[(Bool, Bool), @string.Regex]
}

///|
/// Compiles a translated pattern with the core engine.
fn compile_core(
  fixed : String,
  translated : String,
) -> @string.Regex raise RuleError {
  @string.Regex(translated) catch {
    e => raise RuleError("invalid regex `\{fixed}`: \{e}")
  }
}

///|
pub fn RegexMatcher::new(expression : String) -> RegexMatcher raise RuleError {
  let fixed = fixup_regex(expression)
  // The anchors take part in translation: upstream compiles `^expr$`, and a
  // leading quantifier repeats the `^`.
  let regex = compile_core(fixed, translate_rust_regex("^" + fixed + "$"))
  { expression: fixed, regex, variants: Map([]), }
}

///|
/// Whether the regex matches the whole line (without its line feed).
pub fn RegexMatcher::matches(self : RegexMatcher, line : String) -> Bool {
  self.regex.execute(line) is Some(_)
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
    return self.matches(text)
  }
  for segment in @text.utf8_segments(line) {
    let (start, text, end) = segment
    let key = (start == 0, end == line.length())
    let regex = match self.variants.get(key) {
      Some(r) => r
      None => {
        let r = compile_core(
          self.expression,
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
    if regex.execute(text) is Some(_) {
      return true
    }
  }
  false
}
