// File name patterns with the semantics of the `globset` crate (0.4.20)
// with default options, which upstream uses to pick test documents: a port
// of its parser, matching bytes like its `(?-u)` regex. `*` and `?` also
// match `/` (but not a line feed), `**` is recursive only as a whole path
// component, `{a,b}` alternatives may nest (empty ones are dropped) and `\`
// escapes (on Windows it is a separator).

///|
pub(all) suberror GlobError {
  GlobError(String)
} derive(Debug)

///|
pub impl Show for GlobError with fn output(self, logger) {
  let GlobError(msg) = self
  logger.write_string(msg)
}

///|
priv enum Token {
  Literal(Char)
  AnyChar
  ZeroOrMore
  RecursivePrefix
  RecursiveSuffix
  RecursiveZeroOrMore
  Class(negated~ : Bool, ranges~ : Array[(Char, Char)])
  Alternates(Array[Array[Token]])
} derive(Eq)

///|
pub struct Glob {
  pattern : String
  priv tokens : Array[Token]
}

///|
pub fn Glob::to_string(self : Glob) -> String {
  self.pattern
}

///|
priv struct Parser {
  glob : String
  chars : Array[Char]
  mut pos : Int
  mut prev : Char?
  mut cur : Char?
  alternates_stack : Array[Int]
  branches : Array[Array[Token]]
}

///|
fn Parser::bump(self : Parser) -> Char? {
  self.prev = self.cur
  self.cur = self.chars.get(self.pos)
  if self.pos < self.chars.length() {
    self.pos += 1
  }
  self.cur
}

///|
fn Parser::peek(self : Parser) -> Char? {
  self.chars.get(self.pos)
}

///|
fn Parser::error(self : Parser, kind : String) -> GlobError {
  GlobError("error parsing glob '\{self.glob}': \{kind}")
}

///|
fn Parser::push_token(self : Parser, token : Token) -> Unit raise GlobError {
  match self.branches.last() {
    Some(branch) => branch.push(token)
    None => raise self.error("unopened alternate group; missing '{'")
  }
}

///|
fn Parser::pop_token(self : Parser) -> Token raise GlobError {
  match self.branches.last() {
    Some(branch) => branch.pop().unwrap()
    None => raise self.error("unopened alternate group; missing '{'")
  }
}

///|
fn Parser::have_tokens(self : Parser) -> Bool raise GlobError {
  match self.branches.last() {
    Some(branch) => !branch.is_empty()
    None => raise self.error("unopened alternate group; missing '{'")
  }
}

///|
fn glob_separator(c : Char) -> Bool {
  c == '/' || (is_windows() && c == '\\')
}

///|
fn Parser::parse_star(self : Parser) -> Unit raise GlobError {
  let prev = self.prev
  if self.peek() != Some('*') {
    self.push_token(ZeroOrMore)
    return
  }
  ignore(self.bump())
  if !self.have_tokens() {
    match self.peek() {
      Some(c) if !glob_separator(c) => {
        self.push_token(ZeroOrMore)
        self.push_token(ZeroOrMore)
      }
      _ => {
        self.push_token(RecursivePrefix)
        ignore(self.bump())
      }
    }
    return
  }
  if !(prev is Some(p) && glob_separator(p)) {
    if self.branches.length() <= 1 || (prev != Some(',') && prev != Some('{')) {
      self.push_token(ZeroOrMore)
      self.push_token(ZeroOrMore)
      return
    }
  }
  let is_suffix = match self.peek() {
    None => {
      ignore(self.bump())
      true
    }
    Some(',' | '}') if self.branches.length() >= 2 => true
    Some(c) if glob_separator(c) => {
      ignore(self.bump())
      false
    }
    _ => {
      self.push_token(ZeroOrMore)
      self.push_token(ZeroOrMore)
      return
    }
  }
  match self.pop_token() {
    RecursivePrefix => self.push_token(RecursivePrefix)
    RecursiveSuffix => self.push_token(RecursiveSuffix)
    _ =>
      self.push_token(
        if is_suffix {
          RecursiveSuffix
        } else {
          RecursiveZeroOrMore
        },
      )
  }
}

///|
fn Parser::parse_class(self : Parser) -> Unit raise GlobError {
  let ranges : Array[(Char, Char)] = []
  let negated = match self.peek() {
    Some('!' | '^') => {
      ignore(self.bump())
      true
    }
    _ => false
  }
  let mut first = true
  let mut in_range = false
  let add_to_last_range = (c : Char) => {
    let last = ranges[ranges.length() - 1]
    if c < last.0 {
      raise self.error("invalid range; '\{last.0}' > '\{c}'")
    }
    ranges[ranges.length() - 1] = (last.0, c)
  }
  while true {
    guard self.bump() is Some(c) else {
      raise self.error("unclosed character class; missing ']'")
    }
    match c {
      ']' => if first { ranges.push((']', ']')) } else { break }
      '-' =>
        if first {
          ranges.push(('-', '-'))
        } else if in_range {
          add_to_last_range('-')
          in_range = false
        } else {
          in_range = true
        }
      c => {
        if in_range {
          add_to_last_range(c)
        } else {
          ranges.push((c, c))
        }
        in_range = false
      }
    }
    first = false
  }
  if in_range {
    ranges.push(('-', '-'))
  }
  self.push_token(Class(negated~, ranges~))
}

///|
/// Compile a pattern.
pub fn Glob::new(pattern : String) -> Glob raise GlobError {
  let p : Parser = {
    glob: pattern,
    chars: pattern.to_array(),
    pos: 0,
    prev: None,
    cur: None,
    alternates_stack: [],
    branches: [[]],
  }
  while p.bump() is Some(c) {
    match c {
      '?' => p.push_token(AnyChar)
      '*' => p.parse_star()
      '[' => p.parse_class()
      '{' => {
        p.alternates_stack.push(p.branches.length())
        p.branches.push([])
      }
      '}' => {
        guard p.alternates_stack.pop() is Some(start) else {
          raise p.error("unopened alternate group; missing '{'")
        }
        let alternatives = p.branches[start:].to_owned()
        p.branches.truncate(start)
        p.push_token(Alternates(alternatives))
      }
      ',' =>
        if p.alternates_stack.is_empty() {
          p.push_token(Literal(','))
        } else {
          p.branches.push([])
        }
      '\\' =>
        if is_windows() {
          p.push_token(Literal('/'))
        } else {
          match p.bump() {
            Some(e) => p.push_token(Literal(e))
            None => raise p.error("dangling '\\'")
          }
        }
      c => p.push_token(Literal(c))
    }
  }
  if p.branches.length() > 1 {
    raise p.error("unclosed alternate group; missing '}'")
  }
  { pattern, tokens: p.branches[0], }
}

///|
/// Whether tokens translate to an empty regex (upstream drops such
/// alternatives).
fn is_empty_regex(tokens : Array[Token]) -> Bool {
  tokens
  .iter()
  .all(t => t is Alternates(alts) && alts.iter().all(is_empty_regex))
}

///|
/// Bytes a class member stands for (non-ASCII characters as their UTF-8
/// bytes, as upstream's byte regex does).
fn class_matches(ranges : Array[(Char, Char)], b : Int) -> Bool {
  for r in ranges {
    let (lo, hi) = r
    if lo.to_int() < 0x80 && hi.to_int() < 0x80 {
      if b >= lo.to_int() && b <= hi.to_int() {
        return true
      }
    } else {
      for c in [lo, hi] {
        for x in @text.to_bytes(c.to_string()) {
          if x.to_int() == b {
            return true
          }
        }
      }
    }
  }
  false
}

///|
/// Whether `tokens` match `text[at:]`, then `rest` matches the remainder.
fn match_at(
  tokens : ArrayView[Token],
  rest : @list.List[ArrayView[Token]],
  text : Bytes,
  at : Int,
) -> Bool {
  let n = text.length()
  // `.*` without line feeds from `at`, then continue at every position.
  let any_run = (continue_at : (Int) -> Bool) => {
    let mut i = at
    while true {
      if continue_at(i) {
        return true
      }
      if i >= n || text[i] == b'\n' {
        return false
      }
      i += 1
    }
    false
  }
  match tokens {
    [] =>
      match rest {
        Empty => at == n
        More(next, tail~) => match_at(next, tail, text, at)
      }
    [Literal(c), .. more] => {
      let bytes = @text.to_bytes(c.to_string())
      if at + bytes.length() > n {
        return false
      }
      for k in 0..<bytes.length() {
        if text[at + k] != bytes[k] {
          return false
        }
      }
      match_at(more, rest, text, at + bytes.length())
    }
    [AnyChar, .. more] =>
      at < n && text[at] != b'\n' && match_at(more, rest, text, at + 1)
    [ZeroOrMore, .. more] => any_run(i => match_at(more, rest, text, i))
    [RecursivePrefix, .. more] =>
      // `(?:/?|.*/)`
      match_at(more, rest, text, at) ||
      (at < n && text[at] == b'/' && match_at(more, rest, text, at + 1)) ||
      any_run(i => i < n && text[i] == b'/' && match_at(more, rest, text, i + 1))
    [RecursiveSuffix, .. more] =>
      // `/.*`
      at < n &&
      text[at] == b'/' &&
      match_at([ZeroOrMore, ..more], rest, text, at + 1)
    [RecursiveZeroOrMore, .. more] =>
      // `(?:/|/.*/)`
      at < n &&
      text[at] == b'/' &&
      (
        match_at(more, rest, text, at + 1) ||
        match_at([ZeroOrMore, Literal('/'), ..more], rest, text, at + 1)
      )
    [Class(negated~, ranges~), .. more] =>
      at < n &&
      class_matches(ranges, text[at].to_int()) != negated &&
      match_at(more, rest, text, at + 1)
    [Alternates(alts), .. more] => {
      let alts = alts.filter(a => !is_empty_regex(a))
      if alts.is_empty() {
        return match_at(more, rest, text, at)
      }
      alts.iter().any(alt => match_at(alt, rest.prepend(more), text, at))
    }
  }
}

///|
/// Whether the whole path matches.
pub fn Glob::is_match(self : Glob, path : String) -> Bool {
  let path = if is_windows() {
    path.replace_all(old="\\", new="/")
  } else {
    path
  }
  let text = @text.to_bytes(path)
  if self.tokens is [RecursivePrefix] {
    return !text.iter().any(b => b == b'\n')
  }
  match_at(self.tokens, @list.List::new(), text, 0)
}
