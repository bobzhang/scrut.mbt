// A parser for Rust `regex` syntax: a port of regex-syntax 0.8's AST parser
// (`ast/parse.rs`), so that the same patterns are accepted, with the same
// structure (flags, `x` mode, class set operations, repetitions).

///|
/// A literal character; `byte` is set for a two-digit `\xHH` escape (a raw
/// byte when Unicode mode is off).
priv struct Lit {
  c : Char
  byte : Int?
}

///|
priv enum FlagItem {
  Negation
  Flag(Char)
}

///|
priv enum AssertKind {
  StartLine
  EndLine
  StartText
  EndText
  WordBoundary
  NotWordBoundary
  /// `\b{start}`, `\b{end}`, `\b{start-half}`, `\b{end-half}`, `\<`, `\>`.
  SpecialWordBoundary
}

///|
priv enum PerlKind {
  Digit
  Space
  Word
}

///|
/// A `\p`/`\P` class; `negated` accounts for `\P` and `!=`.
priv struct UnicodeClassAst {
  negated : Bool
  query : UnicodeQuery
}

///|
priv enum GroupKind {
  Capture
  NonCapturing(Array[FlagItem])
}

///|
priv enum ClassOp {
  Intersection
  Difference
  SymmetricDifference
}

///|
priv enum ClassSetItem {
  EmptyItem
  LiteralItem(Lit)
  RangeItem(Lit, Lit)
  /// `[:name:]` (negated with `[:^name:]`).
  AsciiItem(String, Bool)
  UnicodeItem(UnicodeClassAst)
  PerlItem(PerlKind, Bool)
  BracketedItem(Bool, ClassSet)
  UnionItem(Array[ClassSetItem])
}

///|
priv enum ClassSet {
  Item(ClassSetItem)
  BinaryOp(ClassOp, ClassSet, ClassSet)
}

///|
priv enum Ast {
  Empty
  SetFlags(Array[FlagItem])
  Literal(Lit)
  Dot
  Assertion(AssertKind)
  UnicodeClass(UnicodeClassAst)
  PerlClass(PerlKind, Bool)
  Bracketed(Bool, ClassSet)
  Repetition(Ast, Int64, Int64?, Bool)
  Group(GroupKind, Ast)
  Alternation(Array[Ast])
  Concat(Array[Ast])
}

///|
priv enum GroupState {
  /// An open group: the concatenation before it, its kind and the `x` mode
  /// outside it.
  OpenGroup(Array[Ast], GroupKind, Bool)
  OpenAlternation(Array[Ast])
}

///|
priv enum ClassState {
  /// An open bracket: the enclosing union and whether it is negated.
  Open(Array[ClassSetItem], Bool)
  Op(ClassOp, ClassSet)
}

///|
/// A primitive: something parsed from one position.
priv enum Primitive {
  PLiteral(Lit)
  PAssertion(AssertKind)
  PDot
  PPerl(PerlKind, Bool)
  PUnicode(UnicodeClassAst)
}

///|
priv struct Parser {
  pattern : Array[Char]
  expression : String
  mut pos : Int
  mut ignore_whitespace : Bool
  groups : Array[GroupState]
  classes : Array[ClassState]
  capture_names : Map[String, Unit]
}

///|
const NEST_LIMIT = 250

///|
fn Parser::new(expression : String) -> Parser {
  {
    pattern: expression.to_array(),
    expression,
    pos: 0,
    ignore_whitespace: false,
    groups: [],
    classes: [],
    capture_names: {},
  }
}

///|
fn Parser::error(self : Parser, msg : String) -> RuleError {
  RuleError("\{msg} in regex `\{self.expression}`")
}

///|
fn Parser::is_eof(self : Parser) -> Bool {
  self.pos >= self.pattern.length()
}

///|
fn Parser::char(self : Parser) -> Char {
  self.pattern[self.pos]
}

///|
/// Advances one character; whether there is a character after it.
fn Parser::bump(self : Parser) -> Bool {
  if self.is_eof() {
    return false
  }
  self.pos += 1
  !self.is_eof()
}

///|
fn Parser::bump_if(self : Parser, prefix : String) -> Bool {
  let p = prefix.to_array()
  if self.pos + p.length() > self.pattern.length() {
    return false
  }
  for i, c in p {
    if self.pattern[self.pos + i] != c {
      return false
    }
  }
  self.pos += p.length()
  true
}

///|
fn Parser::bump_and_bump_space(self : Parser) -> Bool {
  if !self.bump() {
    return false
  }
  self.bump_space()
  !self.is_eof()
}

///|
/// In `x` mode, skips whitespace and `#` comments.
fn Parser::bump_space(self : Parser) -> Unit {
  if !self.ignore_whitespace {
    return
  }
  while !self.is_eof() {
    if is_rust_whitespace(self.char()) {
      self.pos += 1
    } else if self.char() == '#' {
      self.pos += 1
      while !self.is_eof() {
        let c = self.char()
        self.pos += 1
        if c == '\n' {
          break
        }
      }
    } else {
      break
    }
  }
}

///|
fn Parser::peek(self : Parser) -> Char? {
  self.pattern.get(self.pos + 1)
}

///|
/// The next character after the current one, skipping `x` mode space.
fn Parser::peek_space(self : Parser) -> Char? {
  if !self.ignore_whitespace {
    return self.peek()
  }
  let mut in_comment = false
  for i in (self.pos + 1)..<self.pattern.length() {
    let c = self.pattern[i]
    if is_rust_whitespace(c) {
      continue
    } else if !in_comment && c == '#' {
      in_comment = true
    } else if in_comment && c == '\n' {
      in_comment = false
    } else if !in_comment {
      return Some(c)
    }
  }
  None
}

///|
fn concat_into_ast(asts : Array[Ast]) -> Ast {
  match asts.length() {
    0 => Empty
    1 => asts[0]
    _ => Concat(asts)
  }
}

///|
fn alternation_into_ast(asts : Array[Ast]) -> Ast {
  match asts.length() {
    0 => Empty
    1 => asts[0]
    _ => Alternation(asts)
  }
}

///|
fn union_into_item(items : Array[ClassSetItem]) -> ClassSetItem {
  match items.length() {
    0 => EmptyItem
    1 => items[0]
    _ => UnionItem(items)
  }
}

///|
/// The state of `flag` set by flag items (`Some(false)` when negated).
fn flag_state(items : Array[FlagItem], flag : Char) -> Bool? {
  let mut negated = false
  for item in items {
    match item {
      Negation => negated = true
      Flag(f) if f == flag => return Some(!negated)
      _ => ()
    }
  }
  None
}

///|
/// Parses a whole pattern.
fn Parser::parse(self : Parser) -> Ast raise RuleError {
  let mut concat : Array[Ast] = []
  for ;; {
    self.bump_space()
    if self.is_eof() {
      break
    }
    match self.char() {
      '(' => concat = self.push_group(concat)
      ')' => concat = self.pop_group(concat)
      '|' => {
        self.push_or_add_alternation(concat_into_ast(concat))
        self.pos += 1
        concat = []
      }
      '[' => {
        let (negated, set) = self.parse_set_class()
        concat.push(Bracketed(negated, set))
      }
      '?' => self.parse_uncounted_repetition(concat, 0L, Some(1L))
      '*' => self.parse_uncounted_repetition(concat, 0L, None)
      '+' => self.parse_uncounted_repetition(concat, 1L, None)
      '{' => self.parse_counted_repetition(concat)
      _ => concat.push(self.parse_primitive().into_ast())
    }
  }
  let ast = self.pop_group_end(concat)
  check_nest_limit(ast, 0, self)
  ast
}

///|
fn Primitive::into_ast(self : Primitive) -> Ast {
  match self {
    PLiteral(lit) => Literal(lit)
    PAssertion(kind) => Assertion(kind)
    PDot => Dot
    PPerl(kind, negated) => PerlClass(kind, negated)
    PUnicode(cls) => UnicodeClass(cls)
  }
}

///|
fn Parser::push_or_add_alternation(self : Parser, ast : Ast) -> Unit {
  match self.groups.last() {
    Some(OpenAlternation(alts)) => alts.push(ast)
    _ => self.groups.push(OpenAlternation([ast]))
  }
}

///|
fn Parser::push_group(
  self : Parser,
  concat : Array[Ast],
) -> Array[Ast] raise RuleError {
  match self.parse_group() {
    Ok(flags) => {
      if flag_state(flags, 'x') is Some(v) {
        self.ignore_whitespace = v
      }
      concat.push(SetFlags(flags))
      concat
    }
    Err(kind) => {
      let old = self.ignore_whitespace
      let new = match kind {
        NonCapturing(flags) => flag_state(flags, 'x').unwrap_or(old)
        Capture => old
      }
      self.groups.push(OpenGroup(concat, kind, old))
      self.ignore_whitespace = new
      []
    }
  }
}

///|
fn Parser::pop_group(
  self : Parser,
  group_concat : Array[Ast],
) -> Array[Ast] raise RuleError {
  let (prior, kind, ignore_whitespace, alt) = match self.groups.pop() {
    Some(OpenGroup(concat, kind, iw)) => (concat, kind, iw, None)
    Some(OpenAlternation(alt)) =>
      match self.groups.pop() {
        Some(OpenGroup(concat, kind, iw)) => (concat, kind, iw, Some(alt))
        _ => raise self.error("unopened group")
      }
    None => raise self.error("unopened group")
  }
  self.ignore_whitespace = ignore_whitespace
  self.pos += 1
  let inner = match alt {
    Some(alt) => {
      alt.push(concat_into_ast(group_concat))
      alternation_into_ast(alt)
    }
    None => concat_into_ast(group_concat)
  }
  prior.push(Group(kind, inner))
  prior
}

///|
fn Parser::pop_group_end(
  self : Parser,
  concat : Array[Ast],
) -> Ast raise RuleError {
  let ast = match self.groups.pop() {
    None => concat_into_ast(concat)
    Some(OpenAlternation(alt)) => {
      alt.push(concat_into_ast(concat))
      alternation_into_ast(alt)
    }
    Some(OpenGroup(_)) => raise self.error("unclosed group")
  }
  if self.groups.pop() is Some(_) {
    raise self.error("unclosed group")
  }
  ast
}

///|
/// A group opening: `Ok(flags)` for `(?flags)`, else the group's kind.
fn Parser::parse_group(
  self : Parser,
) -> Result[Array[FlagItem], GroupKind] raise RuleError {
  self.pos += 1
  self.bump_space()
  if self.bump_if("?=") ||
    self.bump_if("?!") ||
    self.bump_if("?<=") ||
    self.bump_if("?<!") {
    raise self.error(
      "look-around, including look-ahead and look-behind, is not supported",
    )
  }
  if self.bump_if("?P<") || self.bump_if("?<") {
    self.parse_capture_name()
    Err(Capture)
  } else if self.bump_if("?") {
    if self.is_eof() {
      raise self.error("unclosed group")
    }
    let flags = self.parse_flags()
    let end = self.char()
    self.pos += 1
    if end == ')' {
      if flags.is_empty() {
        raise self.error("repetition operator missing expression")
      }
      Ok(flags)
    } else {
      Err(NonCapturing(flags))
    }
  } else {
    Err(Capture)
  }
}

///|
fn Parser::parse_capture_name(self : Parser) -> Unit raise RuleError {
  if self.is_eof() {
    raise self.error("EOF in capture name")
  }
  let start = self.pos
  for ;; {
    if self.char() == '>' {
      break
    }
    let c = self.char()
    let ok = if self.pos == start {
      c == '_' || is_rust_alphabetic(c)
    } else {
      c == '_' || c == '.' || c == '[' || c == ']' || is_rust_alphanumeric(c)
    }
    if !ok {
      raise self.error("invalid capture group character")
    }
    if !self.bump() {
      break
    }
  }
  if self.is_eof() {
    raise self.error("EOF in capture name")
  }
  let name = String::from_array(self.pattern[start:self.pos])
  self.pos += 1
  if name == "" {
    raise self.error("empty capture group name")
  }
  if self.capture_names.contains(name) {
    raise self.error("duplicate capture group name")
  }
  self.capture_names[name] = ()
}

///|
fn Parser::parse_flags(self : Parser) -> Array[FlagItem] raise RuleError {
  let items : Array[FlagItem] = []
  let mut last_was_negation = false
  while self.char() != ':' && self.char() != ')' {
    let item = if self.char() == '-' {
      last_was_negation = true
      Negation
    } else {
      last_was_negation = false
      match self.char() {
        'i' | 'm' | 's' | 'U' | 'u' | 'R' | 'x' => Flag(self.char())
        _ => raise self.error("unrecognized flag")
      }
    }
    let duplicate = items
      .iter()
      .any(x => {
        match (x, item) {
          (Negation, Negation) => true
          (Flag(a), Flag(b)) => a == b
          _ => false
        }
      })
    if duplicate {
      raise self.error("duplicate flag")
    }
    items.push(item)
    if !self.bump() {
      raise self.error("expected flag but got end of regex")
    }
  }
  if last_was_negation {
    raise self.error("flag negation operator missing flags")
  }
  items
}

///|
fn Parser::parse_uncounted_repetition(
  self : Parser,
  concat : Array[Ast],
  min : Int64,
  max : Int64?,
) -> Unit raise RuleError {
  let ast = match concat.pop() {
    None | Some(Empty) | Some(SetFlags(_)) =>
      raise self.error("repetition operator missing expression")
    Some(ast) => ast
  }
  let mut greedy = true
  if self.bump() && self.char() == '?' {
    greedy = false
    self.pos += 1
  }
  concat.push(Repetition(ast, min, max, greedy))
}

///|
fn Parser::parse_decimal(self : Parser) -> Int64? raise RuleError {
  while !self.is_eof() && is_rust_whitespace(self.char()) {
    self.pos += 1
  }
  let digits = StringBuilder()
  while !self.is_eof() && self.char() >= '0' && self.char() <= '9' {
    digits.write_char(self.char())
    self.bump_and_bump_space() |> ignore
  }
  while !self.is_eof() && is_rust_whitespace(self.char()) {
    self.bump_and_bump_space() |> ignore
  }
  let digits = digits.to_string()
  if digits == "" {
    return None
  }
  let n = digits
    .to_array()
    .fold(init=0L, (acc, c) => {
      if acc > 0xFFFFFFFFL {
        acc
      } else {
        acc * 10L + (c.to_int() - '0'.to_int()).to_int64()
      }
    })
  if n > 0xFFFFFFFFL {
    raise self.error("decimal literal invalid")
  }
  Some(n)
}

///|
fn Parser::parse_counted_repetition(
  self : Parser,
  concat : Array[Ast],
) -> Unit raise RuleError {
  let ast = match concat.pop() {
    None | Some(Empty) | Some(SetFlags(_)) =>
      raise self.error("repetition operator missing expression")
    Some(ast) => ast
  }
  let unclosed = self.error("unclosed counted repetition")
  let empty = self.error("repetition quantifier expects a valid decimal")
  if !self.bump_and_bump_space() {
    raise unclosed
  }
  let count_start = self.parse_decimal()
  if self.is_eof() {
    raise unclosed
  }
  let (min, max) = if self.char() == ',' {
    if !self.bump_and_bump_space() {
      raise unclosed
    }
    if self.char() != '}' {
      guard count_start is Some(start) else { raise empty }
      guard self.parse_decimal() is Some(end) else { raise empty }
      (start, Some(end))
    } else {
      guard count_start is Some(start) else { raise empty }
      (start, None)
    }
  } else {
    guard count_start is Some(start) else { raise empty }
    (start, Some(start))
  }
  if self.is_eof() || self.char() != '}' {
    raise unclosed
  }
  let mut greedy = true
  if self.bump_and_bump_space() && self.char() == '?' {
    greedy = false
    self.pos += 1
  }
  if max is Some(max) && min > max {
    raise self.error("invalid repetition count range")
  }
  concat.push(Repetition(ast, min, max, greedy))
}

///|
fn Parser::parse_primitive(self : Parser) -> Primitive raise RuleError {
  match self.char() {
    '\\' => self.parse_escape()
    '.' => {
      self.pos += 1
      PDot
    }
    '^' => {
      self.pos += 1
      PAssertion(StartLine)
    }
    '$' => {
      self.pos += 1
      PAssertion(EndLine)
    }
    c => {
      self.pos += 1
      PLiteral({ c, byte: None, })
    }
  }
}

///|
fn is_meta_character(c : Char) -> Bool {
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
    | '#'
    | '&'
    | '-'
    | '~' => true
    _ => false
  }
}

///|
fn is_escapeable_character(c : Char) -> Bool {
  if is_meta_character(c) {
    return true
  }
  if c.to_int() > 0x7F {
    return false
  }
  match c {
    '0'..='9' | 'A'..='Z' | 'a'..='z' | '<' | '>' => false
    _ => true
  }
}

///|
fn Parser::parse_escape(self : Parser) -> Primitive raise RuleError {
  if !self.bump() {
    raise self.error("incomplete escape sequence")
  }
  let c = self.char()
  match c {
    '0'..='9' => raise self.error("backreferences are not supported")
    'x' | 'u' | 'U' => return PLiteral(self.parse_hex())
    'p' | 'P' => return PUnicode(self.parse_unicode_class())
    'd' | 's' | 'w' | 'D' | 'S' | 'W' => {
      self.pos += 1
      let kind = match c {
        'd' | 'D' => Digit
        's' | 'S' => Space
        _ => Word
      }
      return PPerl(kind, c == 'D' || c == 'S' || c == 'W')
    }
    _ => ()
  }
  self.pos += 1
  if is_escapeable_character(c) {
    return PLiteral({ c, byte: None, })
  }
  let special = (c : Char) => PLiteral({ c, byte: None, })
  match c {
    'a' => special('\u{7}')
    'f' => special('\u{C}')
    't' => special('\t')
    'n' => special('\n')
    'r' => special('\r')
    'v' => special('\u{B}')
    'A' => PAssertion(StartText)
    'z' => PAssertion(EndText)
    'b' => {
      if !self.is_eof() && self.char() == '{' {
        if self.maybe_parse_special_word_boundary() {
          return PAssertion(SpecialWordBoundary)
        }
      }
      PAssertion(WordBoundary)
    }
    'B' => PAssertion(NotWordBoundary)
    '<' | '>' => PAssertion(SpecialWordBoundary)
    _ => raise self.error("unrecognized escape sequence `\\\{c}`")
  }
}

///|
/// After `\b`, whether a `{start}`-style special word boundary follows
/// (else the brace is a counted repetition).
fn Parser::maybe_parse_special_word_boundary(
  self : Parser,
) -> Bool raise RuleError {
  let is_valid = (c : Char) => c is ('A'..='Z' | 'a'..='z' | '-')
  let start = self.pos
  if !self.bump_and_bump_space() {
    raise self.error("unexpected end of special word boundary or repetition")
  }
  if !is_valid(self.char()) {
    self.pos = start
    return false
  }
  let name = StringBuilder()
  while !self.is_eof() && is_valid(self.char()) {
    name.write_char(self.char())
    self.bump_and_bump_space() |> ignore
  }
  if self.is_eof() || self.char() != '}' {
    raise self.error("unclosed special word boundary")
  }
  self.pos += 1
  match name.to_string() {
    "start" | "end" | "start-half" | "end-half" => true
    _ => raise self.error("unrecognized special word boundary")
  }
}

///|
fn is_hex(c : Char) -> Bool {
  c is ('0'..='9' | 'a'..='f' | 'A'..='F')
}

///|
fn hex_value(digits : String) -> Int? {
  if digits.length() > 8 {
    // Leading zeros aside, too large for a code point.
    let trimmed = digits.to_array()
    let mut i = 0
    while i < trimmed.length() - 1 && trimmed[i] == '0' {
      i += 1
    }
    if trimmed.length() - i > 6 {
      return None
    }
    return hex_value(String::from_array(trimmed[i:]))
  }
  let mut n = 0L
  for c in digits {
    let d = match c {
      '0'..='9' => c.to_int() - '0'.to_int()
      'a'..='f' => c.to_int() - 'a'.to_int() + 10
      _ => c.to_int() - 'A'.to_int() + 10
    }
    n = n * 16L + d.to_int64()
  }
  if n > 0x10FFFFL || (n >= 0xD800L && n <= 0xDFFFL) {
    None
  } else {
    Some(n.to_int())
  }
}

///|
fn Parser::parse_hex(self : Parser) -> Lit raise RuleError {
  let digits_count = match self.char() {
    'x' => 2
    'u' => 4
    _ => 8
  }
  if !self.bump_and_bump_space() {
    raise self.error("incomplete escape sequence")
  }
  let scratch = StringBuilder()
  if self.char() == '{' {
    while self.bump_and_bump_space() && self.char() != '}' {
      if !is_hex(self.char()) {
        raise self.error("invalid hexadecimal digit")
      }
      scratch.write_char(self.char())
    }
    if self.is_eof() {
      raise self.error("incomplete escape sequence")
    }
    self.bump_and_bump_space() |> ignore
    let hex = scratch.to_string()
    if hex == "" {
      raise self.error("hexadecimal literal empty")
    }
    guard hex_value(hex) is Some(c) else {
      raise self.error("hexadecimal literal is not a Unicode scalar value")
    }
    { c: c.unsafe_to_char(), byte: None, }
  } else {
    for i in 0..<digits_count {
      if i > 0 && !self.bump_and_bump_space() {
        raise self.error("incomplete escape sequence")
      }
      if !is_hex(self.char()) {
        raise self.error("invalid hexadecimal digit")
      }
      scratch.write_char(self.char())
    }
    self.bump_and_bump_space() |> ignore
    guard hex_value(scratch.to_string()) is Some(c) else {
      raise self.error("hexadecimal literal is not a Unicode scalar value")
    }
    {
      c: c.unsafe_to_char(),
      byte: if digits_count == 2 {
        Some(c)
      } else {
        None
      },
    }
  }
}

///|
fn Parser::parse_unicode_class(
  self : Parser,
) -> UnicodeClassAst raise RuleError {
  let negated = self.char() == 'P'
  if !self.bump_and_bump_space() {
    raise self.error("incomplete escape sequence")
  }
  if self.char() == '{' {
    let scratch = StringBuilder()
    while self.bump_and_bump_space() && self.char() != '}' {
      scratch.write_char(self.char())
    }
    if self.is_eof() {
      raise self.error("incomplete escape sequence")
    }
    self.pos += 1
    let name = scratch.to_string()
    let split = (sep : String) => {
      guard name.find(sep) is Some(i) else { return None }
      Some(
        (
          name.view(end_offset=i).to_owned(),
          name.view(start_offset=i + sep.length()).to_owned(),
        ),
      )
    }
    if split("!=") is Some((n, v)) {
      { negated: !negated, query: ByValue(n, v), }
    } else if split(":") is Some((n, v)) {
      { negated, query: ByValue(n, v), }
    } else if split("=") is Some((n, v)) {
      { negated, query: ByValue(n, v), }
    } else {
      { negated, query: Binary(name), }
    }
  } else {
    let c = self.char()
    if c == '\\' {
      raise self.error("invalid Unicode character class")
    }
    self.bump_and_bump_space() |> ignore
    { negated, query: OneLetter(c), }
  }
}

///|
/// Parses a bracketed class starting at `[`: whether it is negated and its
/// set.
fn Parser::parse_set_class(self : Parser) -> (Bool, ClassSet) raise RuleError {
  let mut union : Array[ClassSetItem] = []
  for ;; {
    self.bump_space()
    if self.is_eof() {
      raise self.error("unclosed character class")
    }
    match self.char() {
      '[' => {
        if !self.classes.is_empty() {
          if self.maybe_parse_ascii_class() is Some((name, negated)) {
            union.push(AsciiItem(name, negated))
            continue
          }
        }
        let (negated, nested) = self.parse_set_class_open()
        self.classes.push(Open(union, negated))
        union = nested
      }
      ']' => {
        let prevset = self.pop_class_op(Item(union_into_item(union)))
        match self.classes.pop() {
          Some(Open(parent, negated)) => {
            self.pos += 1
            if self.classes.is_empty() {
              return (negated, prevset)
            }
            parent.push(BracketedItem(negated, prevset))
            union = parent
          }
          _ => panic()
        }
      }
      '&' if self.peek() == Some('&') => {
        self.pos += 2
        union = self.push_class_op(Intersection, union)
      }
      '-' if self.peek() == Some('-') => {
        self.pos += 2
        union = self.push_class_op(Difference, union)
      }
      '~' if self.peek() == Some('~') => {
        self.pos += 2
        union = self.push_class_op(SymmetricDifference, union)
      }
      _ => union.push(self.parse_set_class_range())
    }
  }
}

///|
fn Parser::push_class_op(
  self : Parser,
  kind : ClassOp,
  union : Array[ClassSetItem],
) -> Array[ClassSetItem] {
  let lhs = self.pop_class_op(Item(union_into_item(union)))
  self.classes.push(Op(kind, lhs))
  []
}

///|
fn Parser::pop_class_op(self : Parser, rhs : ClassSet) -> ClassSet {
  match self.classes.last() {
    Some(Op(kind, lhs)) => {
      self.classes.pop() |> ignore
      BinaryOp(kind, lhs, rhs)
    }
    _ => rhs
  }
}

///|
fn Parser::parse_set_class_range(self : Parser) -> ClassSetItem raise RuleError {
  let prim1 = self.parse_set_class_item()
  self.bump_space()
  if self.is_eof() {
    raise self.error("unclosed character class")
  }
  if self.char() != '-' ||
    self.peek_space() == Some(']') ||
    self.peek_space() == Some('-') {
    return match prim1 {
      PLiteral(lit) => LiteralItem(lit)
      PPerl(kind, negated) => PerlItem(kind, negated)
      PUnicode(cls) => UnicodeItem(cls)
      _ => raise self.error("invalid escape sequence in character class")
    }
  }
  if !self.bump_and_bump_space() {
    raise self.error("unclosed character class")
  }
  let prim2 = self.parse_set_class_item()
  guard prim1 is PLiteral(start) && prim2 is PLiteral(end) else {
    raise self.error("invalid range boundary, must be a literal")
  }
  if start.c > end.c {
    raise self.error("invalid character class range")
  }
  RangeItem(start, end)
}

///|
fn Parser::parse_set_class_item(self : Parser) -> Primitive raise RuleError {
  if self.char() == '\\' {
    self.parse_escape()
  } else {
    let c = self.char()
    self.pos += 1
    PLiteral({ c, byte: None, })
  }
}

///|
/// After `[`: negation, leading `-`s and a leading `]` (literals).
fn Parser::parse_set_class_open(
  self : Parser,
) -> (Bool, Array[ClassSetItem]) raise RuleError {
  let unclosed = self.error("unclosed character class")
  if !self.bump_and_bump_space() {
    raise unclosed
  }
  let negated = if self.char() != '^' {
    false
  } else {
    if !self.bump_and_bump_space() {
      raise unclosed
    }
    true
  }
  let union : Array[ClassSetItem] = []
  while self.char() == '-' {
    union.push(LiteralItem({ c: '-', byte: None, }))
    if !self.bump_and_bump_space() {
      raise unclosed
    }
  }
  if union.is_empty() && self.char() == ']' {
    union.push(LiteralItem({ c: ']', byte: None, }))
    if !self.bump_and_bump_space() {
      raise unclosed
    }
  }
  (negated, union)
}

///|
/// `[:name:]` or `[:^name:]` inside a class, or `None` (nothing consumed).
fn Parser::maybe_parse_ascii_class(self : Parser) -> (String, Bool)? {
  let start = self.pos
  let fail = () => {
    self.pos = start
    None
  }
  if !self.bump() || self.char() != ':' {
    return fail()
  }
  if !self.bump() {
    return fail()
  }
  let mut negated = false
  if self.char() == '^' {
    negated = true
    if !self.bump() {
      return fail()
    }
  }
  let name_start = self.pos
  while self.char() != ':' {
    if !self.bump() {
      break
    }
  }
  if self.is_eof() {
    return fail()
  }
  let name = String::from_array(self.pattern[name_start:self.pos])
  if !self.bump_if(":]") {
    return fail()
  }
  if ascii_class(name) is None {
    return fail()
  }
  Some((name, negated))
}

///|
/// The ranges of a POSIX class.
fn ascii_class(name : String) -> Array[(Int, Int)]? {
  let r = (a : Char, b : Char) => (a.to_int(), b.to_int())
  match name {
    "alnum" => Some([r('0', '9'), r('A', 'Z'), r('a', 'z')])
    "alpha" => Some([r('A', 'Z'), r('a', 'z')])
    "ascii" => Some([(0, 0x7F)])
    "blank" => Some([r('\t', '\t'), r(' ', ' ')])
    "cntrl" => Some([(0, 0x1F), (0x7F, 0x7F)])
    "digit" => Some([r('0', '9')])
    "graph" => Some([r('!', '~')])
    "lower" => Some([r('a', 'z')])
    "print" => Some([r(' ', '~')])
    "punct" => Some([r('!', '/'), r(':', '@'), r('[', '`'), r('{', '~')])
    "space" => Some([(9, 13), r(' ', ' ')])
    "upper" => Some([r('A', 'Z')])
    "word" => Some([r('0', '9'), r('A', 'Z'), r('_', '_'), r('a', 'z')])
    "xdigit" => Some([r('0', '9'), r('A', 'F'), r('a', 'f')])
    _ => None
  }
}

///|
/// regex-syntax's nesting limit (groups, repetitions, classes,
/// alternations and concatenations).
fn check_nest_limit(ast : Ast, depth : Int, p : Parser) -> Unit raise RuleError {
  let deeper = () => {
    if depth + 1 > NEST_LIMIT {
      raise p.error("exceeds the nesting limit")
    }
    depth + 1
  }
  match ast {
    Bracketed(_, set) => check_set_nest_limit(set, deeper(), p)
    Repetition(sub, _, _, _) | Group(_, sub) =>
      check_nest_limit(sub, deeper(), p)
    Alternation(asts) | Concat(asts) => {
      let d = deeper()
      for a in asts {
        check_nest_limit(a, d, p)
      }
    }
    _ => ()
  }
}

///|
fn check_set_nest_limit(
  set : ClassSet,
  depth : Int,
  p : Parser,
) -> Unit raise RuleError {
  match set {
    BinaryOp(_, lhs, rhs) => {
      check_set_nest_limit(lhs, depth, p)
      check_set_nest_limit(rhs, depth, p)
    }
    Item(BracketedItem(_, inner)) => {
      if depth + 1 > NEST_LIMIT {
        raise p.error("exceeds the nesting limit")
      }
      check_set_nest_limit(inner, depth + 1, p)
    }
    Item(UnionItem(items)) => {
      if depth + 1 > NEST_LIMIT {
        raise p.error("exceeds the nesting limit")
      }
      for item in items {
        check_set_nest_limit(Item(item), depth + 1, p)
      }
    }
    Item(_) => ()
  }
}
