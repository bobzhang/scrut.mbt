// Output expectations (upstream src/expectation.rs).

///|
/// A prediction about one or more lines of output.
pub struct Expectation {
  /// May be absent (`?` and `*`).
  optional : Bool
  /// May match several subsequent lines (`*` and `+`).
  multiline : Bool
  rule : Rule
  /// The expectation as written in the document.
  original : String
}

///|
pub fn Expectation::matches(self : Expectation, line : BytesView) -> Bool {
  self.rule.matches(line)
}

///|
/// The expectation as written in a document.
pub fn Expectation::to_expression_string(
  self : Expectation,
  escaper : @text.Escaper,
) -> String {
  self.rule.to_expression_string(self.optional, self.multiline, escaper)
}

///|
/// Decompose into (kind, expression, optional, multiline).
pub fn Expectation::unmake(self : Expectation) -> (String, Bytes, Bool, Bool) {
  let (kind, expression) = self.rule.unmake()
  (kind, expression, self.optional, self.multiline)
}

///|
pub impl Show for Expectation with fn output(self, logger) {
  logger.write_string(self.to_expression_string(@text.Escaper::Unicode))
}

///|
pub impl Eq for Expectation with fn equal(self, other) {
  self.optional == other.optional &&
  self.multiline == other.multiline &&
  self.rule == other.rule
}

///|
/// Makes expectations; Cram compatibility changes the glob rule.
pub struct ExpectationMaker {
  cram_glob : Bool
}

///|
pub fn ExpectationMaker::new(cram_compat? : Bool = false) -> ExpectationMaker {
  { cram_glob: cram_compat, }
}

///|
/// The rule names, as in upstream's registry (aliases included).
let rule_names : ReadOnlyArray[String] = [
  "eq", "equal", "esc", "escaped", "gl", "glob", "no-eol", "re", "regex",
]

///|
/// Rust regex `\s` (Unicode `White_Space`).
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
/// Split a line into (expression, kind, quantifier) like upstream's
/// `^(.*?)(?:\s\((<names>|)?([*+?])?\))?$`: the suffix is the last
/// parenthesised group, preceded by whitespace.
fn extract(line : String) -> (String, String, String) {
  let chars = line.to_array()
  let n = chars.length()
  let plain = (line, "equal", "")
  if n < 3 || chars[n - 1] != ')' {
    return plain
  }
  let mut open = n - 2
  while open >= 0 && chars[open] != '(' {
    if chars[open] == ')' {
      return plain
    }
    open -= 1
  }
  if open < 1 || !is_white_space(chars[open - 1]) {
    return plain
  }
  let content = String::from_array(chars[open + 1:n - 1])
  let expression = String::from_array(chars[0:open - 1])
  let (name, quantifier) = if content.has_suffix("*") ||
    content.has_suffix("+") ||
    content.has_suffix("?") {
    (
      content[:content.length() - 1].to_owned(),
      content[content.length() - 1:].to_owned(),
    )
  } else {
    (content, "")
  }
  if name != "" && !rule_names.contains(name) {
    return plain
  }
  // The kind group takes part even when empty: `x (+)` is an equal
  // expectation, `x ()` names the empty kind.
  if quantifier != "" {
    (expression, if name == "" { "equal" } else { name }, quantifier)
  } else {
    (expression, name, "")
  }
}

///|
/// Parse an expectation line: `<expression>` or `<expression> (<kind><q>)`.
pub fn ExpectationMaker::parse(
  self : ExpectationMaker,
  line : String,
) -> Expectation raise RuleError {
  let (expression, kind, quantifier) = extract(line)
  let multiline = quantifier == "*" || quantifier == "+"
  let optional = quantifier == "*" || quantifier == "?"
  self.make(
    kind,
    expression,
    optional,
    multiline,
    @text.trim_newlines_str(line),
  )
}

///|
/// Make an expectation from its components.
pub fn ExpectationMaker::make(
  self : ExpectationMaker,
  kind : String,
  expression : String,
  optional : Bool,
  multiline : Bool,
  original : String,
) -> Expectation raise RuleError {
  {
    optional,
    multiline,
    rule: Rule::make(kind, expression, cram_glob=self.cram_glob),
    original,
  }
}
