// Compiling a parsed Rust regex (regex-syntax `hir/translate.rs`) into the
// syntax of the core regex engine (`@string.Regex`): flags are resolved,
// every class becomes an explicit set of code point ranges and every
// literal that is not ASCII alphanumeric a `\u{..}` escape.

///|
priv struct Flags {
  case_insensitive : Bool
  multi_line : Bool
  dot_matches_new_line : Bool
  swap_greed : Bool
  unicode : Bool
  crlf : Bool
}

///|
fn Flags::apply(self : Flags, items : Array[FlagItem]) -> Flags {
  let mut flags = self
  let mut enable = true
  for item in items {
    match item {
      Negation => enable = false
      Flag('i') => flags = { ..flags, case_insensitive: enable, }
      Flag('m') => flags = { ..flags, multi_line: enable, }
      Flag('s') => flags = { ..flags, dot_matches_new_line: enable, }
      Flag('U') => flags = { ..flags, swap_greed: enable, }
      Flag('u') => flags = { ..flags, unicode: enable, }
      Flag('R') => flags = { ..flags, crlf: enable, }
      Flag(_) => ()
    }
  }
  flags
}

///|
priv enum Look {
  Start
  End
  WordBoundary
  NotWordBoundary
}

///|
/// A compiled regex: literals are one-element sets.
priv enum Hir {
  HEmpty
  HSet(CharSet)
  HLook(Look)
  HRepeat(Hir, Int64, Int64?, Bool)
  HConcat(Array[Hir])
  HAlt(Array[Hir])
  HGroup(Hir)
}

///|
priv struct Translator {
  parser : Parser
  mut flags : Flags
}

///|
fn Translator::unsupported(self : Translator, what : String) -> RuleError {
  self.parser.error("\{what} is not supported")
}

///|
fn Translator::translate(self : Translator, ast : Ast) -> Hir raise RuleError {
  match ast {
    Empty => HEmpty
    SetFlags(items) => {
      self.flags = self.flags.apply(items)
      HEmpty
    }
    Literal(lit) => self.literal(lit)
    Dot => {
      let f = self.flags
      if !f.unicode {
        raise self.unsupported("`.` matching any byte (Unicode mode off)")
      }
      if f.dot_matches_new_line {
        HSet(CharSet::from_ranges([(0, MAX_CHAR)]))
      } else if f.crlf {
        HSet(CharSet::from_ranges([(0, 9), (11, 12), (14, MAX_CHAR)]))
      } else {
        HSet(CharSet::from_ranges([(0, 9), (11, MAX_CHAR)]))
      }
    }
    Assertion(kind) => {
      let f = self.flags
      match kind {
        // Lines never contain a line feed, so multi-line anchors match
        // where the others do; CRLF mode also stops at a carriage return.
        StartLine | EndLine if f.multi_line && f.crlf =>
          raise self.unsupported("a CRLF-mode multi-line anchor")
        StartLine | StartText => HLook(Start)
        EndLine | EndText => HLook(End)
        WordBoundary => HLook(WordBoundary)
        NotWordBoundary => HLook(NotWordBoundary)
        SpecialWordBoundary =>
          raise self.unsupported("a special word boundary assertion")
      }
    }
    UnicodeClass(cls) => HSet(self.unicode_class(cls))
    PerlClass(kind, negated) =>
      HSet(self.check_bytes(self.perl_class(kind, negated)))
    Bracketed(negated, set) => {
      let cls = self.fold_and_negate(self.class_set(set), negated)
      HSet(self.check_bytes(cls))
    }
    Repetition(sub, min, max, greedy) => {
      let h = self.translate(sub)
      HRepeat(h, min, max, if self.flags.swap_greed { !greedy } else { greedy })
    }
    Group(kind, sub) => {
      let old = self.flags
      if kind is NonCapturing(items) {
        self.flags = self.flags.apply(items)
      }
      let h = self.translate(sub)
      self.flags = old
      HGroup(h)
    }
    Concat(asts) => {
      let out = []
      for a in asts {
        let h = self.translate(a)
        if !(h is HEmpty) {
          out.push(h)
        }
      }
      HConcat(out)
    }
    Alternation(asts) => HAlt(asts.map(a => self.translate(a)))
  }
}

///|
fn Translator::literal(self : Translator, lit : Lit) -> Hir raise RuleError {
  let f = self.flags
  let c = if !f.unicode && lit.byte is Some(b) && b > 0x7F {
    raise self.unsupported("a raw byte literal (Unicode mode off)")
  } else {
    lit.c.to_int()
  }
  if !f.case_insensitive {
    return HSet(CharSet::single(c))
  }
  if f.unicode {
    match case_orbit(c) {
      Some(orbit) => HSet(CharSet::from_ranges(orbit.map(m => (m, m))))
      None => HSet(CharSet::single(c))
    }
  } else {
    HSet(CharSet::single(c).ascii_case_fold())
  }
}

///|
fn Translator::unicode_class(
  self : Translator,
  cls : UnicodeClassAst,
) -> CharSet raise RuleError {
  if !self.flags.unicode {
    raise self.parser.error("Unicode not allowed here")
  }
  match unicode_class(cls.query) {
    Ok(set) => self.fold_and_negate(set, cls.negated)
    Err(msg) => raise self.parser.error(msg)
  }
}

///|
fn Translator::perl_class(
  self : Translator,
  kind : PerlKind,
  negated : Bool,
) -> CharSet {
  let set = if self.flags.unicode {
    match kind {
      Digit => perl_digit()
      Space => perl_space()
      Word => perl_word()
    }
  } else {
    let name = match kind {
      Digit => "digit"
      Space => "space"
      Word => "word"
    }
    CharSet::from_ranges(ascii_class(name).unwrap())
  }
  if negated {
    set.negate(max=self.universe())
  } else {
    set
  }
}

///|
/// The largest member of a class: a byte when Unicode mode is off.
fn Translator::universe(self : Translator) -> Int {
  if self.flags.unicode {
    MAX_CHAR
  } else {
    0xFF
  }
}

///|
/// A byte class (Unicode mode off) with non-ASCII bytes would match parts
/// of characters or invalid UTF-8, which a character matcher cannot.
fn Translator::check_bytes(
  self : Translator,
  set : CharSet,
) -> CharSet raise RuleError {
  if !self.flags.unicode && set.has_at_least(0x80) {
    raise self.unsupported(
      "a class matching non-ASCII bytes (Unicode mode off)",
    )
  }
  set
}

///|
fn Translator::fold(self : Translator, set : CharSet) -> CharSet {
  if !self.flags.case_insensitive {
    set
  } else if self.flags.unicode {
    set.case_fold()
  } else {
    set.ascii_case_fold()
  }
}

///|
fn Translator::fold_and_negate(
  self : Translator,
  set : CharSet,
  negated : Bool,
) -> CharSet {
  let set = self.fold(set)
  if negated {
    set.negate(max=self.universe())
  } else {
    set
  }
}

///|
/// A class literal: a byte when Unicode mode is off.
fn Translator::class_literal(
  self : Translator,
  lit : Lit,
) -> Int raise RuleError {
  if self.flags.unicode {
    return lit.c.to_int()
  }
  match lit.byte {
    Some(b) => b
    None =>
      if lit.c.to_int() <= 0x7F {
        lit.c.to_int()
      } else {
        raise self.parser.error("Unicode not allowed here")
      }
  }
}

///|
fn Translator::class_set(
  self : Translator,
  set : ClassSet,
) -> CharSet raise RuleError {
  match set {
    Item(item) => self.class_item(item)
    BinaryOp(op, lhs, rhs) => {
      let lhs = self.fold(self.class_set(lhs))
      let rhs = self.fold(self.class_set(rhs))
      match op {
        Intersection => lhs.intersect(rhs)
        Difference => lhs.difference(rhs)
        SymmetricDifference => lhs.symmetric_difference(rhs)
      }
    }
  }
}

///|
fn Translator::class_item(
  self : Translator,
  item : ClassSetItem,
) -> CharSet raise RuleError {
  match item {
    EmptyItem => CharSet::empty()
    LiteralItem(lit) => CharSet::single(self.class_literal(lit))
    RangeItem(lo, hi) =>
      CharSet::from_ranges([(self.class_literal(lo), self.class_literal(hi))])
    AsciiItem(name, negated) =>
      self.fold_and_negate(
        CharSet::from_ranges(ascii_class(name).unwrap()),
        negated,
      )
    UnicodeItem(cls) => self.unicode_class(cls)
    PerlItem(kind, negated) => self.perl_class(kind, negated)
    BracketedItem(negated, set) =>
      self.fold_and_negate(self.class_set(set), negated)
    UnionItem(items) => {
      let mut out = CharSet::empty()
      for i in items {
        out = out.union(self.class_item(i))
      }
      out
    }
  }
}

///|
/// The core engine's largest repetition count.
const MAX_REPEAT = 256L

///|
fn write_hex_char(buf : StringBuilder, c : Int) -> Unit {
  buf.write_string("\\u{")
  buf.write_string(c.to_string(radix=16))
  buf.write_char('}')
}

///|
fn write_set(buf : StringBuilder, set : CharSet) -> Unit {
  match set.single_char() {
    Some(c) if (c >= '0' && c <= '9') ||
      (c >= 'a' && c <= 'z') ||
      (c >= 'A' && c <= 'Z') => buf.write_char(c.unsafe_to_char())
    Some(c) => write_hex_char(buf, c)
    None => {
      buf.write_char('[')
      for r in set.ranges {
        write_hex_char(buf, r.0)
        if r.1 > r.0 {
          buf.write_char('-')
          write_hex_char(buf, r.1)
        }
      }
      buf.write_char(']')
    }
  }
}

///|
/// A repetition in counts the engine accepts: a count above 256 becomes a
/// nested repetition.
fn write_repeat(
  buf : StringBuilder,
  sub : (StringBuilder) -> Unit,
  min : Int64,
  max : Int64?,
  greedy : Bool,
) -> Unit {
  let non_greedy = if greedy { "" } else { "?" }
  let small = (n : Int64) => n <= MAX_REPEAT
  match max {
    Some(max) if min > MAX_REPEAT || max > MAX_REPEAT =>
      if min > 0L && max > min {
        // x{min,max} = x{min} x{0,max-min}
        write_repeat(buf, sub, min, Some(min), greedy)
        write_repeat(buf, sub, 0L, Some(max - min), greedy)
      } else {
        // x{0,n} or x{n}: (?:x{256}){q} x{r}, or the same with {0,..}.
        let n = if min > 0L { min } else { max }
        let q = n / MAX_REPEAT
        let r = n % MAX_REPEAT
        let zero = min == 0L
        let block = (b : StringBuilder) => {
          b.write_string("(?:")
          sub(b)
          b.write_string(if zero { "{0,256}" } else { "{256}" })
          b.write_string(non_greedy)
          b.write_char(')')
        }
        write_repeat(buf, block, if zero { 0L } else { q }, Some(q), greedy)
        if r > 0L {
          write_repeat(buf, sub, if zero { 0L } else { r }, Some(r), greedy)
        }
      }
    None if !small(min) => {
      write_repeat(buf, sub, min, Some(min), greedy)
      write_repeat(buf, sub, 0L, None, greedy)
    }
    _ => {
      sub(buf)
      match (min, max) {
        (0L, None) => buf.write_char('*')
        (1L, None) => buf.write_char('+')
        (0L, Some(1L)) => buf.write_char('?')
        (n, None) => buf.write_string("{\{n},}")
        (n, Some(m)) if n == m => buf.write_string("{\{n}}")
        (n, Some(m)) => buf.write_string("{\{n},\{m}}")
      }
      buf.write_string(non_greedy)
    }
  }
}

///|
priv struct Emitter {
  start_anchor : Bool
  end_anchor : Bool
}

///|
fn Emitter::emit(self : Emitter, buf : StringBuilder, hir : Hir) -> Unit {
  match hir {
    HEmpty => ()
    HSet(set) => write_set(buf, set)
    HLook(Start) => buf.write_string(if self.start_anchor { "^" } else { "[]" })
    HLook(End) => buf.write_string(if self.end_anchor { "$" } else { "[]" })
    HLook(WordBoundary) => buf.write_string("\\b")
    HLook(NotWordBoundary) => buf.write_string("\\B")
    HRepeat(sub, min, max, greedy) => {
      let atom = (b : StringBuilder) => {
        if sub is HSet(_) {
          self.emit(b, sub)
        } else {
          b.write_string("(?:")
          self.emit(b, sub)
          b.write_char(')')
        }
      }
      write_repeat(buf, atom, min, max, greedy)
    }
    HConcat(items) =>
      for h in items {
        self.emit(buf, h)
      }
    HAlt(items) => {
      buf.write_string("(?:")
      for i, h in items {
        if i > 0 {
          buf.write_char('|')
        }
        self.emit(buf, h)
      }
      buf.write_char(')')
    }
    HGroup(sub) => {
      buf.write_string("(?:")
      self.emit(buf, sub)
      buf.write_char(')')
    }
  }
}

///|
/// Parses and translates Rust `regex` syntax.
fn compile_rust_regex(expression : String) -> Hir raise RuleError {
  let parser = Parser::new(expression)
  let ast = parser.parse()
  let translator : Translator = {
    parser,
    flags: {
      case_insensitive: false,
      multi_line: false,
      dot_matches_new_line: false,
      swap_greed: false,
      unicode: true,
      crlf: false,
    },
  }
  translator.translate(ast)
}

///|
/// Compiles Rust `regex` syntax to the core engine's syntax. Unknown escapes
/// and invalid patterns are errors, as in Rust, and so are the constructs
/// the core engine cannot express (see DIFFERENCES.md). With `start_anchor`
/// (`end_anchor`) off, `^` (`$`) never matches: for matching a part of the
/// text that does not start (end) it.
pub fn translate_rust_regex(
  expression : String,
  start_anchor? : Bool = true,
  end_anchor? : Bool = true,
) -> String raise RuleError {
  let hir = compile_rust_regex(expression)
  let buf = StringBuilder()
  { start_anchor, end_anchor, }.emit(buf, hir)
  buf.to_string()
}
