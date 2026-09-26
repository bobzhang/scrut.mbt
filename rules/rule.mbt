// Output expectation rules (upstream src/rules/*.rs).

///|
/// A line-level comparison.
pub enum Rule {
  /// A line equal to the text, ending in a line feed.
  Equal(String)
  /// A line equal to the text, without a line feed.
  NoEol(String)
  /// A line equal to the bytes an escaped expression stands for (line feeds
  /// ignored).
  Escaped(String, Bytes)
  /// A `*`/`?` glob.
  Glob(WildMatch)
  /// Cram's glob, with `\*`, `\?` and `\\` escapes (Cram compatibility).
  CramGlob(String)
  /// A regular expression matching the whole line.
  Regex(RegexMatcher)
}

///|
/// The rule's kind, as written in documents.
pub fn Rule::kind(self : Rule) -> String {
  match self {
    Equal(_) => "equal"
    NoEol(_) => "no-eol"
    Escaped(_, _) => "escaped"
    Glob(_) | CramGlob(_) => "glob"
    Regex(_) => "regex"
  }
}

///|
/// Whether a line of output (with its line feed, if any) matches.
pub fn Rule::matches(self : Rule, line : BytesView) -> Bool {
  match self {
    Equal(text) => @text.assure_newline(@text.to_bytes(text)) == line.to_owned()
    NoEol(text) => @text.to_bytes(text) == line.to_owned()
    Escaped(_, bytes) => bytes == @text.trim_newlines(line).to_owned()
    Glob(w) => w.matches(@text.lossy_string(@text.trim_newlines(line)))
    CramGlob(pattern) =>
      cram_glob_matches(pattern, @text.lossy_string(@text.trim_newlines(line)))
    Regex(r) => r.matches(@text.lossy_string(@text.trim_newlines(line)))
  }
}

///|
/// The components the rule can be re-made from: kind and expression bytes.
pub fn Rule::unmake(self : Rule) -> (String, Bytes) {
  match self {
    Equal(text) | NoEol(text) | CramGlob(text) =>
      (self.kind(), @text.to_bytes(text))
    Escaped(_, bytes) => (self.kind(), bytes)
    Glob(w) => (self.kind(), @text.to_bytes(w.to_string()))
    Regex(r) => (self.kind(), @text.to_bytes(r.expression))
  }
}

///|
/// The rule as written in a document, e.g. `foo (glob+)`.
pub fn Rule::to_expression_string(
  self : Rule,
  optional : Bool,
  multiline : Bool,
  escaper : @text.Escaper,
) -> String {
  let (quantifier, equal_quantifier) = if optional {
    if multiline {
      ("*", " (*)")
    } else {
      ("?", " (?)")
    }
  } else if multiline {
    ("+", " (+)")
  } else {
    ("", "")
  }
  let (kind, expression) = self.unmake()
  let rendered = escaper.escaped_printable(expression)
  if kind == "equal" {
    if escaper.has_unprintable(expression) {
      "\{rendered} (escaped\{quantifier})"
    } else {
      "\{rendered}\{equal_quantifier}"
    }
  } else {
    "\{rendered} (\{kind}\{quantifier})"
  }
}

///|
/// `kind::expression`, used to compare rules.
pub fn Rule::to_string(self : Rule) -> String {
  let (kind, expression) = self.unmake()
  "\{kind}::\{@text.Escaper::Unicode.escaped_printable(expression)}"
}

///|
pub impl Show for Rule with fn output(self, logger) {
  logger.write_string(self.to_string())
}

///|
pub impl Eq for Rule with fn equal(self, other) {
  self.to_string() == other.to_string()
}

///|
/// Make the rule of a kind (or one of its aliases) from an expression.
pub fn Rule::make(
  kind : String,
  expression : String,
  cram_glob~ : Bool,
) -> Rule raise RuleError {
  match kind {
    "equal" | "eq" => Equal(expression)
    "no-eol" => NoEol(expression)
    "escaped" | "esc" => {
      let expression = if expression.has_suffix(" (no-eol)") {
        expression[:expression.length() - " (no-eol)".length()].to_owned()
      } else {
        expression
      }
      let bytes = @text.apply_escaped_filter_bytes(expression) catch {
        e => raise RuleError(e.to_string())
      }
      Escaped(expression, bytes)
    }
    "glob" | "gl" => {
      let expression = match @text.expression_as_escaped(expression) {
        Some(e) =>
          @text.apply_escaped_filter_utf8(e) catch {
            e => raise RuleError(e.to_string())
          }
        None => expression
      }
      if cram_glob {
        CramGlob(expression)
      } else {
        Glob(WildMatch::new(expression))
      }
    }
    "regex" | "re" => Regex(RegexMatcher::new(expression))
    _ => raise RuleError("no rule maker for \{kind} registered")
  }
}

///|
/// Cram's glob (upstream `glob_to_regex`): `*` is any run, `?` any character,
/// `\*`, `\?` and `\\` are literal; the whole line must match.
fn cram_glob_matches(pattern : String, input : String) -> Bool {
  // Tokens: 0 = any run, 1 = any character, 2 = literal.
  let kinds : Array[Int] = []
  let lits : Array[Char] = []
  let chars = pattern.to_array()
  let mut i = 0
  while i < chars.length() {
    let c = chars[i]
    i += 1
    if c == '\\' && i < chars.length() && chars[i] is ('*' | '?' | '\\') {
      kinds.push(2)
      lits.push(chars[i])
      i += 1
    } else if c == '*' {
      kinds.push(0)
      lits.push(c)
    } else if c == '?' {
      kinds.push(1)
      lits.push(c)
    } else {
      kinds.push(2)
      lits.push(c)
    }
  }
  let text = input.to_array()
  // Classic glob backtracking over tokens (equivalent to the anchored regex).
  let mut p = 0
  let mut t = 0
  let mut star_p = -1
  let mut star_t = 0
  while t < text.length() {
    if p < kinds.length() && kinds[p] == 0 {
      star_p = p
      star_t = t
      p += 1
    } else if p < kinds.length() && (kinds[p] == 1 || lits[p] == text[t]) {
      p += 1
      t += 1
    } else if star_p >= 0 {
      p = star_p + 1
      star_t += 1
      t = star_t
    } else {
      return false
    }
  }
  while p < kinds.length() && kinds[p] == 0 {
    p += 1
  }
  p == kinds.length()
}
