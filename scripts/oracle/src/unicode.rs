//! Unicode tables for the MoonBit regex compiler (`rules/unicode_tables.mbt`).
//!
//! Every set is computed through the public API of the regex-syntax crate the
//! regex crate uses (and, for the Perl classes, by testing every code point
//! against the regex crate itself), so they are exact for that version. The
//! property and value *names* come from regex-syntax's own name tables, read
//! from its source in the cargo registry.

use std::collections::BTreeMap;
use std::path::PathBuf;

use regex_syntax::hir::{Class, HirKind};

/// The regex-syntax version pinned in Cargo.toml (and upstream's Cargo.lock).
const REGEX_SYNTAX: &str = "regex-syntax-0.8.11";

pub type Ranges = Vec<(u32, u32)>;

fn tables_dir() -> PathBuf {
    if let Some(dir) = std::env::args().nth(2) {
        return PathBuf::from(dir);
    }
    let home = std::env::var("CARGO_HOME")
        .map(PathBuf::from)
        .unwrap_or_else(|_| PathBuf::from(std::env::var("HOME").unwrap()).join(".cargo"));
    let src = home.join("registry").join("src");
    for entry in std::fs::read_dir(&src).expect("cargo registry") {
        let dir = entry.unwrap().path().join(REGEX_SYNTAX).join("src").join("unicode_tables");
        if dir.is_dir() {
            return dir;
        }
    }
    panic!("{REGEX_SYNTAX} not found under {}", src.display());
}

pub fn read(name: &str) -> String {
    std::fs::read_to_string(tables_dir().join(name)).unwrap()
}

/// `("a", "b"),` pairs at the given indentation.
pub fn pairs(text: &str, indent: usize) -> Vec<(String, String)> {
    let prefix = format!("{}(\"", " ".repeat(indent));
    text.lines()
        .filter_map(|l| {
            let rest = l.strip_prefix(&prefix)?;
            let (a, rest) = rest.split_once("\", \"")?;
            let b = rest.strip_suffix("\"),")?;
            Some((a.to_string(), b.to_string()))
        })
        .collect()
}

/// PROPERTY_VALUES: each property's (normalized alias, canonical value)
/// pairs.
pub fn property_values() -> Vec<(String, Vec<(String, String)>)> {
    let mut values: Vec<(String, Vec<(String, String)>)> = vec![];
    // `        "Name",` starts a property's values.
    for l in read("property_values.rs").lines() {
        if let Some(rest) = l.strip_prefix("        \"") {
            values.push((rest.trim_end_matches("\",").to_string(), vec![]));
        } else if let Some(rest) = l.strip_prefix("            (\"") {
            let (a, rest) = rest.split_once("\", \"").unwrap();
            values.last_mut().unwrap().1.push((a.to_string(), rest.trim_end_matches("\"),").to_string()));
        }
    }
    assert_eq!(values.len(), 7);
    values
}

/// The names in a table file's `BY_NAME`.
pub fn by_name(file: &str) -> Vec<String> {
    let text = read(file);
    let start = text.find("pub const BY_NAME").unwrap();
    let body = &text[start..];
    let body = &body[..body.find("];").unwrap()];
    body.lines()
        .filter_map(|l| {
            let rest = l.trim().strip_prefix("(\"")?;
            Some(rest.split_once('"')?.0.to_string())
        })
        .collect()
}

fn without_surrogates(ranges: Ranges) -> Ranges {
    let mut out = vec![];
    for (lo, hi) in ranges {
        if hi < 0xD800 || lo > 0xDFFF {
            out.push((lo, hi));
            continue;
        }
        if lo < 0xD800 {
            out.push((lo, 0xD7FF));
        }
        if hi > 0xDFFF {
            out.push((0xE000, hi));
        }
    }
    out
}

/// The code point ranges a pattern that compiles to a single class matches.
pub fn class_of(pattern: &str) -> Ranges {
    try_class_of(pattern).unwrap_or_else(|| panic!("{pattern}: not a class"))
}

/// The code point ranges of a pattern, if it parses to a single class.
pub fn try_class_of(pattern: &str) -> Option<Ranges> {
    let hir = regex_syntax::ParserBuilder::new().build().parse(pattern).ok()?;
    let ranges = match hir.kind() {
        HirKind::Class(Class::Unicode(c)) => {
            c.ranges().iter().map(|r| (r.start() as u32, r.end() as u32)).collect()
        }
        HirKind::Class(Class::Bytes(c)) if c.ranges().iter().all(|r| r.end() < 0x80) => {
            c.ranges().iter().map(|r| (r.start() as u32, r.end() as u32)).collect()
        }
        HirKind::Literal(lit) => {
            let s = std::str::from_utf8(&lit.0).ok()?;
            let mut chars = s.chars();
            let c = chars.next()? as u32;
            if chars.next().is_some() {
                return None;
            }
            vec![(c, c)]
        }
        _ => return None,
    };
    Some(without_surrogates(ranges))
}

/// Code points `c` for which `re` matches the one-character string `c`.
fn brute_force(re: &str) -> Ranges {
    let re = regex::Regex::new(re).unwrap();
    let mut ranges: Ranges = vec![];
    for cp in 0u32..=0x10FFFF {
        let Some(c) = char::from_u32(cp) else { continue };
        if !re.is_match(c.encode_utf8(&mut [0; 4])) {
            continue;
        }
        match ranges.last_mut() {
            Some((_, hi)) if *hi + 1 == cp => *hi = cp,
            _ => ranges.push((cp, cp)),
        }
    }
    ranges
}

fn union(sets: &[&Ranges]) -> Ranges {
    let mut all: Vec<(u32, u32)> = sets.iter().flat_map(|s| s.iter().copied()).collect();
    all.sort();
    let mut out: Ranges = vec![];
    for (lo, hi) in all {
        match out.last_mut() {
            Some((_, h)) if lo <= *h + 1 => *h = (*h).max(hi),
            _ => out.push((lo, hi)),
        }
    }
    out
}

fn difference(a: &Ranges, b: &Ranges) -> Ranges {
    let mut out = vec![];
    for &(lo, hi) in a {
        let mut lo = lo;
        for &(blo, bhi) in b {
            if bhi < lo || blo > hi {
                continue;
            }
            if blo > lo {
                out.push((lo, blo - 1));
            }
            lo = bhi + 1;
        }
        if lo <= hi {
            out.push((lo, hi));
        }
    }
    union(&[&out])
}

const CONT: &[u8] = b"ABCDEFGHIJKLMNOPQRSTUVWXYZwxyz+/";
const TERM: &[u8] = b"0123456789abcdefghijklmnopqrstuv";

/// A number in base 32, most significant digit first; all digits but the
/// last are from `CONT`.
fn num(out: &mut String, n: u32) {
    let mut digits = vec![n & 31];
    let mut n = n >> 5;
    while n > 0 {
        digits.push(n & 31);
        n >>= 5;
    }
    for (i, d) in digits.iter().rev().enumerate() {
        let table = if i + 1 == digits.len() { TERM } else { CONT };
        out.push(table[*d as usize] as char);
    }
}

/// Ranges as (gap since the previous range, length - 1) pairs.
fn encode(ranges: &Ranges) -> String {
    let mut out = String::new();
    let mut next = 0u32;
    for &(lo, hi) in ranges {
        num(&mut out, lo - next);
        num(&mut out, hi - lo);
        next = hi + 1;
    }
    out
}

/// A MoonBit string literal split over `#|` lines (for long encodings).
fn long_string(s: &str, indent: &str) -> String {
    if s.len() <= 60 {
        return format!("\"{s}\"");
    }
    let mut out = String::from("(\n");
    for chunk in s.as_bytes().chunks(72) {
        out.push_str(indent);
        out.push_str("  #|");
        out.push_str(std::str::from_utf8(chunk).unwrap());
        out.push('\n');
    }
    out.push_str(indent);
    out.push(')');
    out
}

/// Composite general categories and their members.
pub const GC_COMPOSITES: &[(&str, &[&str])] = &[
    (
        "Cased_Letter",
        &["Uppercase_Letter", "Lowercase_Letter", "Titlecase_Letter"],
    ),
    (
        "Letter",
        &["Uppercase_Letter", "Lowercase_Letter", "Titlecase_Letter", "Modifier_Letter", "Other_Letter"],
    ),
    ("Mark", &["Nonspacing_Mark", "Spacing_Mark", "Enclosing_Mark"]),
    ("Number", &["Decimal_Number", "Letter_Number", "Other_Number"]),
    (
        "Punctuation",
        &[
            "Connector_Punctuation",
            "Dash_Punctuation",
            "Open_Punctuation",
            "Close_Punctuation",
            "Initial_Punctuation",
            "Final_Punctuation",
            "Other_Punctuation",
        ],
    ),
    ("Symbol", &["Math_Symbol", "Currency_Symbol", "Modifier_Symbol", "Other_Symbol"]),
    ("Separator", &["Space_Separator", "Line_Separator", "Paragraph_Separator"]),
    ("Other", &["Control", "Format", "Private_Use", "Unassigned"]),
];

/// Simple case folding orbits (size > 1): for each code point c, the set of
/// characters `(?i)c` matches.
pub fn case_orbits() -> Vec<Vec<u32>> {
    let mut orbits: BTreeMap<u32, Vec<u32>> = BTreeMap::new();
    for cp in 0u32..=0x10FFFF {
        let Some(c) = char::from_u32(cp) else { continue };
        let members: Vec<u32> = class_of(&format!("(?i)\\x{{{:x}}}", c as u32))
            .iter()
            .flat_map(|&(lo, hi)| lo..=hi)
            .collect();
        if members.len() < 2 {
            continue;
        }
        match orbits.get(&members[0]) {
            Some(existing) => assert_eq!(existing, &members, "orbit of {cp:x}"),
            None => {
                orbits.insert(members[0], members.clone());
            }
        }
        assert!(members.contains(&cp));
    }
    orbits.into_values().collect()
}

pub fn main() {
    let names = pairs(&read("property_names.rs"), 4);
    let values = property_values();

    let mut sets: Vec<(String, Ranges)> = vec![];
    // Perl classes, by testing every code point (and checked against the
    // parser's own classes).
    for (name, class) in [("word", "\\w"), ("digit", "\\d"), ("space", "\\s")] {
        let ranges = brute_force(&format!("^{class}$"));
        assert_eq!(ranges, class_of(class), "{class}");
        sets.push((format!("perl:{name}"), ranges));
    }
    let composites: Vec<&str> = GC_COMPOSITES.iter().map(|c| c.0).collect();
    let mut gc: BTreeMap<String, Ranges> = BTreeMap::new();
    for name in by_name("general_category.rs") {
        let ranges = class_of(&format!("\\p{{gc={name}}}"));
        gc.insert(name.clone(), ranges.clone());
        if !composites.contains(&name.as_str()) {
            sets.push((format!("gc:{name}"), ranges));
        }
    }
    for (name, members) in GC_COMPOSITES {
        let parts: Vec<&Ranges> = members.iter().map(|m| &gc[*m]).collect();
        assert_eq!(union(&parts), gc[*name], "{name}");
    }
    for name in by_name("script.rs") {
        let ranges = class_of(&format!("\\p{{sc={name}}}"));
        sets.push((format!("sc:{name}"), ranges));
    }
    for name in by_name("script_extension.rs") {
        let ranges = class_of(&format!("\\p{{scx={name}}}"));
        sets.push((format!("scx:{name}"), ranges));
    }
    for name in by_name("property_bool.rs") {
        // Some table entries (`InCB`) have no name the parser resolves.
        let pattern = format!("\\p{{{name}}}");
        if regex_syntax::parse(&pattern).is_err() {
            continue;
        }
        sets.push((format!("bool:{name}"), class_of(&pattern)));
    }
    // Ages are cumulative (`Age=V2_0` includes V1_1); store increments.
    let mut ages = by_name("age.rs");
    let version = |s: &str| -> (u32, u32) {
        let (a, b) = s[1..].split_once('_').unwrap();
        (a.parse().unwrap(), b.parse().unwrap())
    };
    ages.sort_by_key(|a| version(a));
    let mut before: Ranges = vec![];
    for name in &ages {
        let ranges = class_of(&format!("\\p{{age={name}}}"));
        sets.push((format!("age:{name}"), difference(&ranges, &before)));
        before = ranges;
    }
    for (prop, file) in [("gcb", "grapheme_cluster_break.rs"), ("sb", "sentence_break.rs"), ("wb", "word_break.rs")] {
        for name in by_name(file) {
            let ranges = class_of(&format!("\\p{{{prop}={name}}}"));
            sets.push((format!("{prop}:{name}"), ranges));
        }
    }

    println!("// Generated by scripts/oracle (unicode); DO NOT EDIT.");
    println!("// Unicode data of the regex crate upstream scrut uses ({REGEX_SYNTAX}),");
    println!("// for compiling `\\p{{..}}`, `\\w`, `\\d`, `\\s` and `(?i)`.");
    println!("//");
    println!("// Code point sets are strings of base-32 numbers (digits `0-9a-v` end a");
    println!("// number, `A-Zw-z+/` continue it): for each range, the gap since the end");
    println!("// of the previous range, then the range's length minus one.\n");
    println!("///|\n/// Normalized property name aliases and their canonical names.");
    println!("let unicode_property_names : ReadOnlyArray[(String, String)] = [");
    for (a, b) in &names {
        println!("  ({a:?}, {b:?}),");
    }
    println!("]\n");
    println!("///|\n/// Normalized value aliases of the properties `\\p{{name=value}}` supports.");
    println!("let unicode_property_values : ReadOnlyArray[(String, ReadOnlyArray[(String, String)])] = [");
    for (prop, vals) in &values {
        println!("  (\n    {prop:?},\n    [");
        for (a, b) in vals {
            println!("      ({a:?}, {b:?}),");
        }
        println!("    ],\n  ),");
    }
    println!("]\n");
    println!("///|\n/// Composite general categories: unions of other categories.");
    println!("let unicode_gc_composites : ReadOnlyArray[(String, ReadOnlyArray[String])] = [");
    for (name, members) in GC_COMPOSITES {
        let m: Vec<String> = members.iter().map(|m| format!("{m:?}")).collect();
        println!("  ({name:?}, [{}]),", m.join(", "));
    }
    println!("]\n");
    println!("///|\n/// Unicode versions for `Age`, oldest first.");
    let a: Vec<String> = ages.iter().map(|a| format!("{a:?}")).collect();
    println!("let unicode_ages : ReadOnlyArray[String] = [{}]\n", a.join(", "));
    println!("///|\n/// Code point sets by `kind:Canonical_Name` (`age:` sets hold the code");
    println!("/// points new in that version).");
    println!("let unicode_sets : ReadOnlyArray[(String, String)] = [");
    for (name, ranges) in &sets {
        println!("  ({name:?}, {}),", long_string(&encode(ranges), "  "));
    }
    println!("]\n");
    // Orbits: member count, then the smallest member (relative to the previous
    // orbit's), then each further member relative to the previous one.
    let mut out = String::new();
    let mut prev = 0u32;
    for orbit in case_orbits() {
        num(&mut out, orbit.len() as u32);
        num(&mut out, orbit[0] - prev);
        for w in orbit.windows(2) {
            num(&mut out, w[1] - w[0]);
        }
        prev = orbit[0];
    }
    println!("///|\n/// Simple case folding orbits (the characters `(?i)c` matches, when more");
    println!("/// than `c`): each is its size, its smallest member relative to the previous");
    println!("/// orbit's and every further member relative to the one before.");
    println!("let unicode_case_orbits : String = {}", long_string(&out, ""));
}
