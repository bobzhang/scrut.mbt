//! Character classes compiled by the regex crate, sampled on code points
//! (`rules/class_oracle_cases_wbtest.mbt`): property names in their loose
//! spellings, Perl, POSIX and nested classes, set operations, `.` and case
//! folding under inline flags.

use crate::rng::{mbt, Rng};
use regex_syntax::hir::{Class, HirKind};

use crate::unicode::{pairs, property_values, read, try_class_of, Ranges};

/// Like upstream, byte regexes (so Unicode mode may be turned off).
fn compiles(pattern: &str) -> bool {
    regex::bytes::Regex::new(&format!("^(?:{pattern})$")).is_ok()
}

/// The ranges of a single class, as a byte regex parses it: `None` when not
/// a single class, empty ranges for a byte class (Unicode mode off) with
/// non-ASCII bytes.
fn class_ranges(pattern: &str) -> Option<Ranges> {
    if let Some(ranges) = try_class_of(pattern) {
        return Some(ranges);
    }
    let hir = regex_syntax::ParserBuilder::new().utf8(false).build().parse(pattern).ok()?;
    match hir.kind() {
        HirKind::Class(Class::Bytes(_)) => Some(vec![]),
        _ => None,
    }
}

/// Code points worth checking in every class.
const FIXED: &[u32] = &[
    0x0, 0x9, 0xA, 0xD, 0x20, 0x2D, 0x30, 0x39, 0x41, 0x4B, 0x53, 0x5A, 0x5F, 0x61, 0x6B, 0x73,
    0x7A, 0x7F, 0x80, 0x85, 0xA0, 0xAA, 0xB5, 0xC0, 0xC9, 0xDF, 0xE9, 0xFF, 0x130, 0x131, 0x17F,
    0x1C4, 0x1C5, 0x1C6, 0x391, 0x3A3, 0x3A9, 0x3B1, 0x3C2, 0x3C3, 0x3C9, 0x410, 0x5D0, 0x660,
    0x663, 0x903, 0x1E9E, 0x2028, 0x2126, 0x212A, 0x212B, 0x24B6, 0x3000, 0x4E00, 0xAC00,
    0xD7FF, 0xE000, 0xFB01, 0xFFFD, 0x10400, 0x1D400, 0x1F600, 0xE0001, 0x10FFFF,
];

/// Code points a regex matches as a whole, among the samples.
fn sample(rng: &mut Rng, pattern: &str, ranges: &Ranges) -> (Vec<u32>, Vec<u32>) {
    let re = regex::bytes::Regex::new(&format!("^(?:{pattern})$")).unwrap();
    let mut points: Vec<u32> = FIXED.to_vec();
    for _ in 0..6 {
        if ranges.is_empty() {
            break;
        }
        let &(lo, hi) = rng.pick(ranges);
        points.extend([lo.wrapping_sub(1), lo, hi, hi + 1, lo + (hi - lo) / 2]);
    }
    for _ in 0..6 {
        points.push(rng.below(0x110000) as u32);
    }
    points.sort();
    points.dedup();
    let (mut yes, mut no) = (vec![], vec![]);
    for cp in points {
        let Some(c) = char::from_u32(cp) else { continue };
        if re.is_match(c.encode_utf8(&mut [0; 4]).as_bytes()) {
            yes.push(cp);
        } else {
            no.push(cp);
        }
    }
    (yes, no)
}

/// Loose spelling of a property name, as regex-syntax accepts it.
fn mangle(rng: &mut Rng, name: &str) -> String {
    let mut out = String::new();
    if rng.chance(15) {
        out.push_str(rng.pick(&["is", "Is", "IS"]));
    }
    for c in name.chars() {
        if rng.chance(8) {
            out.push(*rng.pick(&[' ', '_', '-']));
        }
        match rng.below(3) {
            0 => out.extend(c.to_uppercase()),
            1 => out.extend(c.to_lowercase()),
            _ => out.push(c),
        }
    }
    out
}

/// A random bracketed-class item.
fn item(rng: &mut Rng, depth: u32) -> String {
    const LITERALS: &[&str] = &[
        "a", "z", "A", "Z", "0", "9", "_", "k", "s", "é", "É", "σ", "Σ", "ß", "ǅ", "\\u{212A}",
        "\\x{17F}", "\\-", "\\]", "\\[", "\\^", "\\&", "\\~", "中", "😀", "\\n", "\\t", " ", ".",
        "$", "\\x7F", "\\u{3000}",
    ];
    const RANGES: &[&str] = &[
        "a-z", "A-Z", "0-9", "a-f", "k-s", "\\x00-\\x1F", "α-ω", "Α-Ω", "à-ÿ", "\\u{100}-\\u{17F}",
        "\\u{1F600}-\\u{1F64F}", "!-/", "\\u{0}-\\u{10FFFF}", "\\u{D7F0}-\\u{E010}",
    ];
    const CLASSES: &[&str] = &[
        "\\w", "\\W", "\\d", "\\D", "\\s", "\\S", "\\pL", "\\PL", "\\p{Greek}", "\\p{Latin}",
        "\\p{Lu}", "\\p{Ll}", "\\p{Nd}", "\\p{P}", "\\p{Z}", "\\P{Cc}", "\\p{Alphabetic}",
        "\\p{White_Space}", "\\p{ASCII}", "\\p{Han}", "[:alpha:]", "[:^alpha:]", "[:digit:]",
        "[:space:]", "[:word:]", "[:^punct:]", "[:upper:]", "[:lower:]", "[:xdigit:]",
    ];
    match rng.below(if depth < 2 { 5 } else { 4 }) {
        0 => rng.pick(LITERALS).to_string(),
        1 => rng.pick(RANGES).to_string(),
        2 | 3 => rng.pick(CLASSES).to_string(),
        _ => class(rng, depth + 1),
    }
}

/// A random bracketed class, possibly with set operations.
pub fn class(rng: &mut Rng, depth: u32) -> String {
    let mut out = String::from("[");
    if rng.chance(25) {
        out.push('^');
    }
    if rng.chance(8) {
        out.push(*rng.pick(&['-', ']']));
    }
    let terms = 1 + rng.below(3);
    for t in 0..terms {
        if t > 0 {
            out.push_str(rng.pick(&["&&", "--", "~~"]));
        }
        for _ in 0..1 + rng.below(3) {
            out.push_str(&item(rng, depth));
        }
    }
    if rng.chance(8) {
        out.push('-');
    }
    out.push(']');
    out
}

pub fn main() {
    let mut rng = Rng(0xc1a5_5e5);
    let mut patterns: Vec<String> = vec![];
    let values = property_values();
    let names = pairs(&read("property_names.rs"), 4);
    let bool_file = read("property_bool.rs");
    // Every value alias of the properties `\p{..}` supports, loosely
    // spelled, alone or as `name=value`.
    for (prop, vals) in &values {
        let prop_aliases: Vec<&String> =
            names.iter().filter(|(_, canon)| canon == prop).map(|(alias, _)| alias).collect();
        for (alias, _) in vals {
            let value = mangle(&mut rng, alias);
            let p = if rng.chance(30) && (prop == "General_Category" || prop == "Script") {
                format!("\\p{{{value}}}")
            } else {
                let alias = rng.pick(&prop_aliases).to_string();
                let name = mangle(&mut rng, &alias);
                let op = rng.pick(&["=", ":", "!="]);
                format!("\\p{{{name}{op}{value}}}")
            };
            let p = if rng.chance(15) { p.replacen("\\p", "\\P", 1) } else { p };
            patterns.push(p);
        }
    }
    // Binary properties by every alias.
    for (alias, canon) in &names {
        if bool_file.contains(&format!("(\"{canon}\",")) || rng.chance(10) {
            let p = format!("\\p{{{}}}", mangle(&mut rng, alias));
            patterns.push(if rng.chance(20) { format!("(?i){p}") } else { p });
        }
    }
    // One-letter forms, specials and names that do not exist.
    for c in "LMNPSZCXlmnpszcx".chars() {
        patterns.push(format!("\\p{c}"));
        patterns.push(format!("\\P{c}"));
    }
    for p in [
        "\\p{Any}", "\\p{Assigned}", "\\P{Assigned}", "\\p{ASCII}", "\\p{isc}", "\\p{IsC}",
        "\\p{cf}", "\\p{sc}", "\\p{lc}", "\\p{L&}", "\\p{Cs}", "\\p{Surrogate}", "\\p{Script}",
        "\\p{gc}", "\\p{Nope}", "\\p{Greek=Yes}", "\\p{Alphabetic=Y}", "\\p{bc=L}",
        "\\p{age=V1_1}", "\\p{age=16.0}", "\\p{age=17.0}", "\\p{Age:6.1}", "\\p{scx=Zyyy}",
        "\\p{Decimal_Number}", "\\p{White_Space}", "\\p{wspace}", "\\p{space}", "\\p{InCB}",
        "\\p{In_Greek}", "\\p{ }", "\\p{}", "\\p{é}", "\\pé",
    ] {
        patterns.push(p.to_string());
    }
    // Perl classes, `.`, POSIX classes and literals under flags.
    for p in ["\\w", "\\W", "\\d", "\\D", "\\s", "\\S", ".", "[[:alpha:]]", "[[:^space:]]"] {
        for flags in ["", "(?i)", "(?s)", "(?R)", "(?sR)", "(?-u)", "(?i-u)", "(?x)"] {
            patterns.push(format!("{flags}{p}"));
        }
    }
    let orbit_chars = [
        "a", "k", "s", "K", "S", "é", "É", "ß", "ẞ", "σ", "ς", "Σ", "ǅ", "ǆ", "Ǆ", "ı", "İ", "i",
        "Ω", "ω", "\\u{2126}", "\\u{212A}", "\\u{17F}", "\\u{1E9E}", "θ", "ϑ", "µ", "Μ", "ſ",
        "\\u{10400}", "\\u{1E900}", "1", "中", " ",
    ];
    for c in orbit_chars {
        patterns.push(format!("(?i){c}"));
        patterns.push(format!("(?i:{c})"));
        patterns.push(format!("(?i)[{c}]"));
        patterns.push(format!("(?i)[^{c}]"));
    }
    // Random bracketed classes with set operations, under flags.
    for _ in 0..700 {
        let flags = rng.pick(&["", "", "", "(?i)", "(?x)", "(?i-u)", "(?-u)"]);
        let c = class(&mut rng, 0);
        patterns.push(format!("{flags}{c}"));
    }

    println!("// Generated by scripts/oracle (classes); DO NOT EDIT.\n");
    println!("///|\n/// (pattern, members, non-members): code points (hex, space-separated)");
    println!("/// that Rust's `^(?:pattern)$` matches, and some it does not; `ERR`");
    println!("/// members when the regex crate rejects the pattern.");
    const CHUNK: usize = 400;
    let ty = "Array[(String, String, String)]";
    let join = |v: &[u32]| v.iter().map(|c| format!("{c:x}")).collect::<Vec<_>>().join(" ");
    let mut chunks = 0;
    let mut count = 0;
    for p in &patterns {
        let entry = match compiles(p) {
            false => format!("  ({}, \"ERR\", \"\"),", mbt(p)),
            true => {
                // Only single classes (patterns like `(?i)1` are literals).
                let Some(ranges) = class_ranges(p) else { continue };
                let (yes, no) = sample(&mut rng, p, &ranges);
                format!("  ({}, {}, {}),", mbt(p), mbt(&join(&yes)), mbt(&join(&no)))
            }
        };
        if count % CHUNK == 0 {
            if count > 0 {
                println!("]\n\n///|");
            }
            println!("let class_cases_{chunks} : {ty} = [");
            chunks += 1;
        }
        println!("{entry}");
        count += 1;
    }
    println!("]\n\n///|");
    let parts: Vec<String> = (0..chunks).map(|k| format!("..class_cases_{k}")).collect();
    println!("let class_cases : {ty} = [{}]", parts.join(", "));
}
