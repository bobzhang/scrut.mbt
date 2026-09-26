// Removing ANSI escape sequences, exactly like the `strip-ansi-escapes` 0.2.1
// crate upstream uses: bytes run through vte 0.14's terminal parser, keeping
// printed characters and line feeds only (tabs, carriage returns and every
// other control character are dropped).

///|
priv enum VteState {
  Ground
  Escape
  EscapeIntermediate
  CsiEntry
  CsiIgnore
  CsiIntermediate
  CsiParam
  DcsEntry
  DcsIgnore
  DcsIntermediate
  DcsParam
  DcsPassthrough
  OscString
  SosPmApcString
} derive(Eq)

///|
/// The result of validating UTF-8 like Rust's `str::from_utf8`: the length of
/// the valid prefix and, on failure, the length of the invalid sequence
/// (`None` when the input ends in the middle of a sequence).
fn utf8_validate(bytes : BytesView) -> (Int, Int?)? {
  let n = bytes.length()
  let mut i = 0
  while i < n {
    let first = bytes[i].to_int()
    if first < 0x80 {
      i += 1
      continue
    }
    let cont = (k : Int) => {
      i + k < n &&
      bytes[i + k].to_int() >= 0x80 &&
      bytes[i + k].to_int() <= 0xBF
    }
    let has = (k : Int) => i + k < n
    let width = if first >= 0xC2 && first <= 0xDF {
      2
    } else if first >= 0xE0 && first <= 0xEF {
      3
    } else if first >= 0xF0 && first <= 0xF4 {
      4
    } else {
      0
    }
    match width {
      2 => {
        if !has(1) {
          return Some((i, None))
        }
        if !cont(1) {
          return Some((i, Some(1)))
        }
      }
      3 | 4 => {
        if !has(1) {
          return Some((i, None))
        }
        let second = bytes[i + 1].to_int()
        let (lo, hi) = match first {
          0xE0 => (0xA0, 0xBF)
          0xED => (0x80, 0x9F)
          0xF0 => (0x90, 0xBF)
          0xF4 => (0x80, 0x8F)
          _ => (0x80, 0xBF)
        }
        if second < lo || second > hi {
          return Some((i, Some(1)))
        }
        if !has(2) {
          return Some((i, None))
        }
        if !cont(2) {
          return Some((i, Some(2)))
        }
        if width == 4 {
          if !has(3) {
            return Some((i, None))
          }
          if !cont(3) {
            return Some((i, Some(3)))
          }
        }
      }
      _ => return Some((i, Some(1)))
    }
    i += width
  }
  None
}

///|
/// Strip ANSI escape sequences from terminal output.
pub fn strip_ansi(data : BytesView) -> Bytes {
  let out = Buffer(size_hint=data.length())
  let print = (c : Char) => out.write_bytes(to_bytes(c.to_string()))
  let execute = (b : Int) => if b == 0x0A { out.write_byte(b'\n') }
  let mut state = Ground
  // A byte handled the same way in (nearly) every non-ground state.
  let anywhere = (b : Int) => {
    match b {
      0x18 | 0x1A => {
        execute(b)
        state = Ground
      }
      0x1B => state = Escape
      _ => ()
    }
  }
  // Characters of valid UTF-8 text in the ground state.
  let ground_text = (text : BytesView) => {
    for c in lossy_string(text) {
      let cp = c.to_int()
      if cp <= 0x1F || (cp >= 0x80 && cp <= 0x9F) {
        execute(cp)
      } else {
        print(c)
      }
    }
  }
  let n = data.length()
  let mut i = 0
  while i < n {
    if state == Ground {
      let rest = data[i:]
      let mut plain = 0
      while plain < rest.length() && rest[plain] != b'\x1b' {
        plain += 1
      }
      if plain == 0 {
        state = Escape
        i += 1
        continue
      }
      match utf8_validate(rest[0:plain]) {
        None => {
          ground_text(rest[0:plain])
          if plain < rest.length() {
            state = Escape
            i += plain + 1
          } else {
            i += plain
          }
        }
        Some((valid, error_len)) => {
          ground_text(rest[0:valid])
          match error_len {
            Some(len) => {
              let b = rest[valid].to_int()
              if len == 1 && b <= 0x9F {
                execute(b)
              } else {
                print('\u{FFFD}')
              }
              i += valid + len
            }
            None =>
              if plain < rest.length() {
                print('\u{FFFD}')
                state = Escape
                i += plain + 1
              } else {
                // An incomplete sequence at the end is kept as partial input
                // that never completes.
                i = n
              }
          }
        }
      }
      continue
    }
    let b = data[i].to_int()
    i += 1
    let c0 = b <= 0x17 || b == 0x19 || (b >= 0x1C && b <= 0x1F)
    match state {
      CsiEntry =>
        if c0 {
          execute(b)
        } else if b >= 0x20 && b <= 0x2F {
          state = CsiIntermediate
        } else if b >= 0x30 && b <= 0x3F {
          state = CsiParam
        } else if b >= 0x40 && b <= 0x7E {
          state = Ground
        } else {
          anywhere(b)
        }
      CsiIgnore =>
        if c0 {
          execute(b)
        } else if b >= 0x40 && b <= 0x7E {
          state = Ground
        } else if (b >= 0x20 && b <= 0x3F) || b == 0x7F {
          ()
        } else {
          anywhere(b)
        }
      CsiIntermediate =>
        if c0 {
          execute(b)
        } else if b >= 0x20 && b <= 0x2F {
          ()
        } else if b >= 0x30 && b <= 0x3F {
          state = CsiIgnore
        } else if b >= 0x40 && b <= 0x7E {
          state = Ground
        } else {
          anywhere(b)
        }
      CsiParam =>
        if c0 {
          execute(b)
        } else if b >= 0x20 && b <= 0x2F {
          state = CsiIntermediate
        } else if b >= 0x30 && b <= 0x3B {
          ()
        } else if b >= 0x3C && b <= 0x3F {
          state = CsiIgnore
        } else if b >= 0x40 && b <= 0x7E {
          state = Ground
        } else if b == 0x7F {
          ()
        } else {
          anywhere(b)
        }
      DcsEntry =>
        if c0 || b == 0x7F {
          ()
        } else if b >= 0x20 && b <= 0x2F {
          state = DcsIntermediate
        } else if b >= 0x30 && b <= 0x3F {
          state = DcsParam
        } else if b >= 0x40 && b <= 0x7E {
          state = DcsPassthrough
        } else {
          anywhere(b)
        }
      DcsIntermediate =>
        if c0 || b == 0x7F || (b >= 0x20 && b <= 0x2F) {
          ()
        } else if b >= 0x30 && b <= 0x3F {
          state = DcsIgnore
        } else if b >= 0x40 && b <= 0x7E {
          state = DcsPassthrough
        } else {
          anywhere(b)
        }
      DcsParam =>
        if c0 || b == 0x7F || (b >= 0x30 && b <= 0x3B) {
          ()
        } else if b >= 0x20 && b <= 0x2F {
          state = DcsIntermediate
        } else if b >= 0x3C && b <= 0x3F {
          state = DcsIgnore
        } else if b >= 0x40 && b <= 0x7E {
          state = DcsPassthrough
        } else {
          anywhere(b)
        }
      DcsPassthrough =>
        match b {
          0x18 | 0x1A => {
            execute(b)
            state = Ground
          }
          0x1B => state = Escape
          0x9C => state = Ground
          _ => ()
        }
      DcsIgnore | SosPmApcString => anywhere(b)
      Escape =>
        if c0 {
          execute(b)
        } else if b >= 0x20 && b <= 0x2F {
          state = EscapeIntermediate
        } else if b == 0x50 {
          state = DcsEntry
        } else if b == 0x58 || b == 0x5E || b == 0x5F {
          state = SosPmApcString
        } else if b == 0x5B {
          state = CsiEntry
        } else if b == 0x5D {
          state = OscString
        } else if b >= 0x30 && b <= 0x7E {
          state = Ground
        } else if b == 0x18 || b == 0x1A {
          execute(b)
          state = Ground
        } else {
          ()
        }
      EscapeIntermediate =>
        if c0 {
          execute(b)
        } else if b >= 0x20 && b <= 0x2F {
          ()
        } else if b >= 0x30 && b <= 0x7E {
          state = Ground
        } else if b == 0x7F {
          ()
        } else {
          anywhere(b)
        }
      OscString =>
        match b {
          0x07 => state = Ground
          0x18 | 0x1A => {
            execute(b)
            state = Ground
          }
          0x1B => state = Escape
          _ => ()
        }
      Ground => ()
    }
  }
  out.to_bytes()
}
