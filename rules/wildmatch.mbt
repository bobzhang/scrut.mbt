// Glob matching with `*` and `?`, exactly like the `wildmatch` 2.6.1 crate
// (case-sensitive, no escaping, character-based).

///|
/// A compiled glob pattern: runs of `*` collapsed into one.
pub struct WildMatch {
  priv pattern : Array[Char]
} derive(Eq, Debug)

///|
pub fn WildMatch::new(pattern : String) -> WildMatch {
  let out : Array[Char] = []
  for c in pattern {
    if c == '*' && out.length() > 0 && out[out.length() - 1] == '*' {
      continue
    }
    out.push(c)
  }
  { pattern: out, }
}

///|
/// The (simplified) pattern text.
pub fn WildMatch::to_string(self : WildMatch) -> String {
  String::from_array(self.pattern)
}

///|
pub fn WildMatch::matches(self : WildMatch, input : String) -> Bool {
  let pattern = self.pattern
  let plen = pattern.length()
  if plen == 0 {
    return input.is_empty()
  }
  let chars = input.to_array()
  let mut pidx = 0
  if chars.length() > 0 {
    // `next` is the index of the next unread input character; `cur` the
    // current one.
    let mut cur = 0
    let mut next = 1
    let none = -1
    let mut start_idx = none
    // The saved iterator position of `matched` (the characters after the one
    // the last `*` started at).
    let mut matched = chars.length()
    while true {
      if pidx < plen && pattern[pidx] == '*' {
        start_idx = pidx
        matched = next
        pidx += 1
      } else if pidx < plen &&
        (pattern[pidx] == '?' || pattern[pidx] == chars[cur]) {
        pidx += 1
        if next < chars.length() {
          cur = next
          next += 1
        } else {
          break
        }
      } else if start_idx != none {
        pidx = start_idx + 1
        if matched < chars.length() {
          cur = matched
          matched += 1
        } else {
          break
        }
        next = matched
      } else {
        return false
      }
    }
  }
  while pidx < plen && pattern[pidx] == '*' {
    pidx += 1
  }
  pidx == plen
}
