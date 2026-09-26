// Unicode classes of Rust's regex crate (regex-syntax `unicode.rs`): Perl
// classes, `\p{..}` lookup with its loose name matching, and simple case
// folding, from the generated `unicode_tables.mbt`.

///|
/// Decodes the base-32 numbers of a generated table.
fn decode_numbers(encoded : String) -> Array[Int] {
  let out = []
  let mut acc = 0
  for c in encoded {
    let (digit, last) = match c {
      '0'..='9' => (c.to_int() - '0'.to_int(), true)
      'a'..='v' => (c.to_int() - 'a'.to_int() + 10, true)
      'A'..='Z' => (c.to_int() - 'A'.to_int(), false)
      'w'..='z' => (c.to_int() - 'w'.to_int() + 26, false)
      '+' => (30, false)
      '/' => (31, false)
      // Line breaks of multi-line literals.
      _ => continue
    }
    acc = acc * 32 + digit
    if last {
      out.push(acc)
      acc = 0
    }
  }
  out
}

///|
/// Decodes a generated set: (gap, length - 1) pairs.
fn decode_set(encoded : String) -> CharSet {
  let numbers = decode_numbers(encoded)
  let ranges = []
  let mut next = 0
  for i = 0; i + 1 < numbers.length(); i = i + 2 {
    let lo = next + numbers[i]
    let hi = lo + numbers[i + 1]
    ranges.push((lo, hi))
    next = hi + 1
  }
  { ranges, }
}

///|
let unicode_set_index : Map[String, String] = Map::from_iter(
  unicode_sets.iter(),
)

///|
let unicode_set_cache : Map[String, CharSet] = Map([])

///|
/// A generated set by `kind:Canonical_Name`.
fn unicode_set(key : String) -> CharSet? {
  if unicode_set_cache.get(key) is Some(set) {
    return Some(set)
  }
  guard unicode_set_index.get(key) is Some(encoded) else { return None }
  let set = decode_set(encoded)
  unicode_set_cache[key] = set
  Some(set)
}

///|
fn perl_word() -> CharSet {
  unicode_set("perl:word").unwrap()
}

///|
fn perl_digit() -> CharSet {
  unicode_set("perl:digit").unwrap()
}

///|
fn perl_space() -> CharSet {
  unicode_set("perl:space").unwrap()
}

///|
let case_orbit_table : Ref[Array[Array[Int]]?] = Ref(None)

///|
/// The simple case folding orbits with more than one member.
fn case_orbits() -> Array[Array[Int]] {
  if case_orbit_table.val is Some(orbits) {
    return orbits
  }
  let numbers = decode_numbers(unicode_case_orbits)
  let orbits = []
  let mut prev = 0
  let mut i = 0
  while i < numbers.length() {
    let size = numbers[i]
    let first = prev + numbers[i + 1]
    let orbit = [first]
    for k in 1..<size {
      orbit.push(orbit[k - 1] + numbers[i + 1 + k])
    }
    orbits.push(orbit)
    prev = first
    i += 1 + size
  }
  case_orbit_table.val = Some(orbits)
  orbits
}

///|
let case_orbit_of_table : Ref[Map[Int, Int]?] = Ref(None)

///|
/// The case folding orbit of a code point, if it has other members.
fn case_orbit(c : Int) -> Array[Int]? {
  let orbits = case_orbits()
  let index = match case_orbit_of_table.val {
    Some(index) => index
    None => {
      let index = Map([])
      for i, orbit in orbits {
        for m in orbit {
          index[m] = i
        }
      }
      case_orbit_of_table.val = Some(index)
      index
    }
  }
  index.get(c).map(i => orbits[i])
}

///|
/// Rust's `char::is_whitespace` (White_Space).
fn is_rust_whitespace(c : Char) -> Bool {
  match c {
    '\t'..='\r'
    | ' '
    | '\u{85}'
    | '\u{A0}'
    | '\u{1680}'
    | '\u{2000}'..='\u{200A}'
    | '\u{2028}'
    | '\u{2029}'
    | '\u{202F}'
    | '\u{205F}'
    | '\u{3000}' => true
    _ => false
  }
}

///|
/// Rust's `char::is_alphabetic`.
fn is_rust_alphabetic(c : Char) -> Bool {
  c.is_ascii_alphabetic() ||
  (
    c.to_int() > 0x7F &&
    unicode_set("bool:Alphabetic").unwrap().contains(c.to_int())
  )
}

///|
/// Rust's `char::is_alphanumeric` (Alphabetic or Numeric).
fn is_rust_alphanumeric(c : Char) -> Bool {
  c.is_ascii_alphabetic() ||
  c.is_ascii_digit() ||
  (
    c.to_int() > 0x7F &&
    (
      is_rust_alphabetic(c) ||
      ["gc:Decimal_Number", "gc:Letter_Number", "gc:Other_Number"]
      .iter()
      .any(k => unicode_set(k).unwrap().contains(c.to_int()))
    )
  )
}

///|
/// regex-syntax's `symbolic_name_normalize`: ASCII lowercase, without
/// spaces, `_`, `-`, non-ASCII characters and a leading `is`.
fn symbolic_name_normalize(name : String) -> String {
  let chars = name.to_array()
  let starts_with_is = chars.length() >= 2 &&
    (chars[0] == 'i' || chars[0] == 'I') &&
    (chars[1] == 's' || chars[1] == 'S')
  let buf = StringBuilder()
  for c in chars[if starts_with_is { 2 } else { 0 }:] {
    match c {
      ' ' | '_' | '-' => ()
      'A'..='Z' => buf.write_char((c.to_int() + 32).unsafe_to_char())
      _ => if c.to_int() <= 0x7F { buf.write_char(c) }
    }
  }
  let s = buf.to_string()
  // `isc` abbreviates `Other`, not `ISO_Comment`.
  if starts_with_is && s == "c" {
    "isc"
  } else {
    s
  }
}

///|
let unicode_property_name_index : Map[String, String] = Map::from_iter(
  unicode_property_names.iter(),
)

///|
let unicode_property_value_index : Map[String, Map[String, String]] = Map::from_iter(
  unicode_property_values.iter().map(p => (p.0, Map::from_iter(p.1.iter()))),
)

///|
fn canonical_prop(norm : String) -> String? {
  unicode_property_name_index.get(norm)
}

///|
fn canonical_value(property : String, norm : String) -> String? {
  unicode_property_value_index.get(property).bind(vals => vals.get(norm))
}

///|
fn canonical_gencat(norm : String) -> String? {
  match norm {
    "any" => Some("Any")
    "assigned" => Some("Assigned")
    "ascii" => Some("ASCII")
    _ => canonical_value("General_Category", norm)
  }
}

///|
/// A `\p{..}` query, as written.
priv enum UnicodeQuery {
  OneLetter(Char)
  Binary(String)
  ByValue(String, String)
}

///|
fn gencat(name : String) -> CharSet? {
  match name {
    "Decimal_Number" => Some(perl_digit())
    "ASCII" => Some(CharSet::from_ranges([(0, 0x7F)]))
    "Any" => Some(CharSet::from_ranges([(0, MAX_CHAR)]))
    "Assigned" => gencat("Unassigned").map(s => s.negate())
    _ =>
      for composite in unicode_gc_composites {
        if composite.0 == name {
          let mut set = CharSet::empty()
          for part in composite.1 {
            set = set.union(gencat(part).unwrap())
          }
          break Some(set)
        }
      } nobreak {
        unicode_set("gc:" + name)
      }
  }
}

///|
/// The code points of a Unicode class query (regex-syntax `unicode::class`),
/// or an error message.
fn unicode_class(query : UnicodeQuery) -> Result[CharSet, String] {
  let not_found = Err("Unicode property not found")
  let value_not_found = Err("Unicode property value not found")
  let binary = (name : String) => {
    let norm = symbolic_name_normalize(name)
    // `cf`, `sc` and `lc` are general categories here.
    if norm != "cf" && norm != "sc" && norm != "lc" {
      if canonical_prop(norm) is Some(canon) {
        return match canon {
          "Decimal_Number" => Ok(perl_digit())
          "White_Space" => Ok(perl_space())
          _ =>
            match unicode_set("bool:" + canon) {
              Some(set) => Ok(set)
              None => not_found
            }
        }
      }
    }
    if canonical_gencat(norm) is Some(canon) {
      return match gencat(canon) {
        Some(set) => Ok(set)
        None => value_not_found
      }
    }
    if canonical_value("Script", norm) is Some(canon) {
      return match unicode_set("sc:" + canon) {
        Some(set) => Ok(set)
        None => value_not_found
      }
    }
    not_found
  }
  match query {
    OneLetter(c) => binary(c.to_string())
    Binary(name) => binary(name)
    ByValue(name, value) => {
      let name = symbolic_name_normalize(name)
      let value = symbolic_name_normalize(value)
      guard canonical_prop(name) is Some(canon) else { return not_found }
      let (kind, property) = match canon {
        "General_Category" => {
          guard canonical_gencat(value) is Some(v) else {
            return value_not_found
          }
          return match gencat(v) {
            Some(set) => Ok(set)
            None => value_not_found
          }
        }
        "Script" => ("sc", canon)
        "Script_Extensions" => ("scx", canon)
        "Age" => ("age", canon)
        "Grapheme_Cluster_Break" => ("gcb", canon)
        "Sentence_Break" => ("sb", canon)
        "Word_Break" => ("wb", canon)
        // regex-syntax knows no values of other properties.
        _ => return value_not_found
      }
      guard canonical_value(property, value) is Some(v) else {
        return value_not_found
      }
      if kind == "age" {
        // Ages are cumulative; `Unassigned` is not one.
        if !unicode_ages.contains(v) {
          return value_not_found
        }
        let mut set = CharSet::empty()
        for age in unicode_ages {
          set = set.union(unicode_set("age:" + age).unwrap())
          if age == v {
            break
          }
        }
        return Ok(set)
      }
      match unicode_set(kind + ":" + v) {
        Some(set) => Ok(set)
        None => value_not_found
      }
    }
  }
}
