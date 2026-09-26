// Sets of code points for the regex compiler: character classes are
// computed here, then emitted as explicit ranges.

///|
/// The largest code point.
const MAX_CHAR = 0x10FFFF

///|
/// A set of code points: sorted, disjoint, non-adjacent inclusive ranges
/// without surrogates (U+D800 to U+DFFF).
priv struct CharSet {
  ranges : Array[(Int, Int)]
}

///|
fn CharSet::empty() -> CharSet {
  { ranges: [], }
}

///|
fn CharSet::single(c : Int) -> CharSet {
  CharSet::from_ranges([(c, c)])
}

///|
/// A normalized set of the given (unsorted, possibly overlapping) ranges.
fn CharSet::from_ranges(ranges : Array[(Int, Int)]) -> CharSet {
  let sorted = ranges.filter(r => r.0 <= r.1)
  sorted.sort_by((a, b) => a.0.compare(b.0))
  let out : Array[(Int, Int)] = []
  let push = (lo : Int, hi : Int) => {
    if lo > hi {
      return
    }
    match out.last() {
      Some((plo, phi)) if lo <= phi + 1 =>
        out[out.length() - 1] = (plo, if hi > phi { hi } else { phi })
      _ => out.push((lo, hi))
    }
  }
  for r in sorted {
    let (lo, hi) = r
    // Split around the surrogates.
    if hi < 0xD800 || lo > 0xDFFF {
      push(lo, hi)
    } else {
      push(lo, 0xD7FF)
      push(0xE000, hi)
    }
  }
  { ranges: out, }
}

///|
fn CharSet::contains(self : CharSet, c : Int) -> Bool {
  let ranges = self.ranges
  for lo = 0, hi = ranges.length(); lo < hi; {
    let mid = lo + (hi - lo) / 2
    let (a, b) = ranges[mid]
    if c < a {
      continue lo, mid
    } else if c > b {
      continue mid + 1, hi
    } else {
      break true
    }
  } nobreak {
    false
  }
}

///|
/// The single code point of a one-element set.
fn CharSet::single_char(self : CharSet) -> Int? {
  if self.ranges is [(lo, hi)] && lo == hi {
    Some(lo)
  } else {
    None
  }
}

///|
/// Whether some member is at least `c`.
fn CharSet::has_at_least(self : CharSet, c : Int) -> Bool {
  self.ranges.last() is Some((_, hi)) && hi >= c
}

///|
fn CharSet::union(self : CharSet, other : CharSet) -> CharSet {
  CharSet::from_ranges([..self.ranges, ..other.ranges])
}

///|
/// The complement within `0..=max` (surrogates excluded).
fn CharSet::negate(self : CharSet, max? : Int = MAX_CHAR) -> CharSet {
  let out : Array[(Int, Int)] = []
  let mut next = 0
  for r in self.ranges {
    if r.0 > next {
      out.push((next, r.0 - 1))
    }
    next = r.1 + 1
  }
  if next <= max {
    out.push((next, max))
  }
  CharSet::from_ranges(out)
}

///|
fn CharSet::intersect(self : CharSet, other : CharSet) -> CharSet {
  let out : Array[(Int, Int)] = []
  let a = self.ranges
  let b = other.ranges
  for i = 0, j = 0; i < a.length() && j < b.length(); {
    let lo = if a[i].0 > b[j].0 { a[i].0 } else { b[j].0 }
    let hi = if a[i].1 < b[j].1 { a[i].1 } else { b[j].1 }
    if lo <= hi {
      out.push((lo, hi))
    }
    if a[i].1 < b[j].1 {
      continue i + 1, j
    } else {
      continue i, j + 1
    }
  }
  { ranges: out, }
}

///|
fn CharSet::difference(self : CharSet, other : CharSet) -> CharSet {
  self.intersect(other.negate())
}

///|
fn CharSet::symmetric_difference(self : CharSet, other : CharSet) -> CharSet {
  self.difference(other).union(other.difference(self))
}

///|
/// Closed under Unicode simple case folding (as `(?i)` does).
fn CharSet::case_fold(self : CharSet) -> CharSet {
  let added : Array[(Int, Int)] = []
  let orbits = case_orbits()
  for orbit in orbits {
    if orbit.iter().any(c => self.contains(c)) {
      for c in orbit {
        added.push((c, c))
      }
    }
  }
  if added.is_empty() {
    self
  } else {
    CharSet::from_ranges([..self.ranges, ..added])
  }
}

///|
/// Closed under ASCII case folding (`(?i-u)`).
fn CharSet::ascii_case_fold(self : CharSet) -> CharSet {
  let added : Array[(Int, Int)] = []
  for c in 'a'.to_int()..<='z'.to_int() {
    if self.contains(c) || self.contains(c - 32) {
      added.push((c, c))
      added.push((c - 32, c - 32))
    }
  }
  CharSet::from_ranges([..self.ranges, ..added])
}
