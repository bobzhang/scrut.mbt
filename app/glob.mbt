// File name patterns with the semantics of the `globset` crate's defaults,
// which upstream uses to pick test documents: `*` and `?` also match `/`,
// `[...]` classes (`[!...]` negated), `{a,b}` alternatives and `\` escapes.

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
  Star
  Class(negated~ : Bool, ranges~ : Array[(Char, Char)])
  Alternatives(Array[Array[Token]])
}

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
/// Compile a pattern.
pub fn Glob::new(pattern : String) -> Glob raise GlobError {
  let chars = pattern.to_array()
  let mut i = 0
  // Parse a sequence up to `,` or `}` (inside alternatives) or the end.
  fn parse_seq(in_alt : Bool) -> Array[Token] raise GlobError {
    let out = []
    while i < chars.length() {
      let c = chars[i]
      match c {
        '*' => {
          i += 1
          out.push(Star)
        }
        '?' => {
          i += 1
          out.push(AnyChar)
        }
        '\\' => {
          if i + 1 >= chars.length() {
            raise GlobError("dangling '\\'")
          }
          out.push(Literal(chars[i + 1]))
          i += 2
        }
        '[' => {
          i += 1
          let negated = i < chars.length() &&
            (chars[i] == '!' || chars[i] == '^')
          if negated {
            i += 1
          }
          let ranges = []
          let mut first = true
          while i < chars.length() && (chars[i] != ']' || first) {
            let lo = chars[i]
            i += 1
            if i + 1 < chars.length() && chars[i] == '-' && chars[i + 1] != ']' {
              let hi = chars[i + 1]
              if hi < lo {
                raise GlobError("invalid range \{lo}-\{hi}")
              }
              ranges.push((lo, hi))
              i += 2
            } else {
              ranges.push((lo, lo))
            }
            first = false
          }
          if i >= chars.length() {
            raise GlobError("unclosed character class; missing ']'")
          }
          i += 1
          out.push(Class(negated~, ranges~))
        }
        '{' => {
          if in_alt {
            raise GlobError("nested alternate groups are not allowed")
          }
          i += 1
          let alternatives = [parse_seq(true)]
          while i < chars.length() && chars[i] == ',' {
            i += 1
            alternatives.push(parse_seq(true))
          }
          if i >= chars.length() {
            raise GlobError("unclosed alternate group; missing '}'")
          }
          i += 1
          out.push(Alternatives(alternatives))
        }
        '}' if in_alt => return out
        ',' if in_alt => return out
        '}' => raise GlobError("unopened alternate group; missing '{'")
        _ => {
          i += 1
          out.push(Literal(c))
        }
      }
    }
    out
  }

  let tokens = parse_seq(false)
  { pattern, tokens, }
}

///|
fn match_tokens(tokens : ArrayView[Token], text : ArrayView[Char]) -> Bool {
  match tokens {
    [] => text.is_empty()
    [Literal(c), .. rest] =>
      text is [d, .. more] && c == d && match_tokens(rest, more)
    [AnyChar, .. rest] => text is [_, .. more] && match_tokens(rest, more)
    [Star, .. rest] => {
      for k in 0..<=text.length() {
        if match_tokens(rest, text[k:]) {
          return true
        }
      }
      false
    }
    [Class(negated~, ranges~), .. rest] =>
      text is [c, .. more] &&
      ranges.iter().any(r => c >= r.0 && c <= r.1) != negated &&
      match_tokens(rest, more)
    [Alternatives(alts), .. rest] =>
      alts
      .iter()
      .any(alt => {
        let joined = alt.copy()
        joined.append(rest.to_owned())
        match_tokens(joined, text)
      })
  }
}

///|
/// Whether the whole path matches.
pub fn Glob::is_match(self : Glob, path : String) -> Bool {
  match_tokens(self.tokens, path.to_array())
}
