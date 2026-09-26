//! `serde_yaml::to_string` (upstream's YAML renderer) on random JSON-like
//! trees whose maps keep their key order.

use serde::ser::{Serialize, SerializeMap, SerializeSeq, Serializer};

use crate::rng::Rng;

enum Node {
    Null,
    Bool(bool),
    Int(i64),
    Str(String),
    Seq(Vec<Node>),
    Map(Vec<(String, Node)>),
}

impl Serialize for Node {
    fn serialize<S: Serializer>(&self, s: S) -> Result<S::Ok, S::Error> {
        match self {
            Node::Null => s.serialize_unit(),
            Node::Bool(b) => s.serialize_bool(*b),
            Node::Int(i) => s.serialize_i64(*i),
            Node::Str(v) => s.serialize_str(v),
            Node::Seq(xs) => {
                let mut seq = s.serialize_seq(Some(xs.len()))?;
                for x in xs {
                    seq.serialize_element(x)?;
                }
                seq.end()
            }
            Node::Map(entries) => {
                let mut map = s.serialize_map(Some(entries.len()))?;
                for (k, v) in entries {
                    map.serialize_entry(k, v)?;
                }
                map.end()
            }
        }
    }
}

/// Compact JSON with keys in the given order.
fn json(node: &Node, out: &mut String) {
    match node {
        Node::Null => out.push_str("null"),
        Node::Bool(b) => out.push_str(if *b { "true" } else { "false" }),
        Node::Int(i) => out.push_str(&i.to_string()),
        Node::Str(v) => out.push_str(&serde_json::to_string(v).unwrap()),
        Node::Seq(xs) => {
            out.push('[');
            for (i, x) in xs.iter().enumerate() {
                if i > 0 {
                    out.push(',');
                }
                json(x, out);
            }
            out.push(']');
        }
        Node::Map(entries) => {
            out.push('{');
            for (i, (k, v)) in entries.iter().enumerate() {
                if i > 0 {
                    out.push(',');
                }
                out.push_str(&serde_json::to_string(k).unwrap());
                out.push(':');
                json(v, out);
            }
            out.push('}');
        }
    }
}

/// A MoonBit string literal with everything outside printable ASCII
/// escaped.
fn mbt(s: &str) -> String {
    let mut out = String::from("\"");
    for c in s.chars() {
        match c {
            '"' => out.push_str("\\\""),
            '\\' => out.push_str("\\\\"),
            '\n' => out.push_str("\\n"),
            '\r' => out.push_str("\\r"),
            '\t' => out.push_str("\\t"),
            c if (c as u32) < 0x20 || (c as u32) >= 0x7f => {
                out.push_str(&format!("\\u{{{:x}}}", c as u32))
            }
            c => out.push(c),
        }
    }
    out.push('"');
    out
}

/// Scalars that are interesting on their own.
fn whole_strings() -> Vec<String> {
    let mut v: Vec<String> = [
        "", "0", "1", "-1", "+1", "1.5", "-1.5", "+1.5", "1e3", "1E3", "1e+3", "1e-3", "-1.5e-3",
        ".inf", "-.inf", "+.inf", ".Inf", ".INF", "-.Inf", "-.INF", ".iNf", ".nan", ".NaN",
        ".NAN", "-.NaN", "+.nan", "-.nan", "nan", "NaN", "inf", "-inf", "+inf", "infinity",
        "Infinity", "0x1F", "0x1f", "-0x1F", "+0x1F", "0x", "-0x", "0x+1", "0x-1", "-0x-1",
        "-0x+1", "+0x+1", "0X1F", "0xg", "0o7", "0o8", "-0o7", "+0o7", "0o", "0O7", "0b101",
        "0b2", "-0b1", "+0b1", "0b", "+", "-", "++1", "+-1", "-+1", "--1", "~", "null", "Null",
        "NULL", "nUll", "nul", "true", "True", "TRUE", "tRue", "false", "False", "FALSE",
        "yes", "no", "on", "off", "y", "n", "Y", "N", "Yes", "ON", "Off", "007", "-007", "+007",
        "00", "-0", "+0", "0.", "-0.", ".5", "-.5", ".", "1.", "1.e5", "1e", "1e+", "e5", "1e5.",
        "1.5.", "1_000", "1,000", "0.000", "1 ", " 1", "01.5", "00.5", "0e0", "0x0", "1e308",
        "1e309", "-1e309", "1.7976931348623158e308", "1.7976931348623159e308", "1e-400",
        "4.9e-324", "18446744073709551615", "18446744073709551616", "-9223372036854775808",
        "-9223372036854775809", "340282366920938463463374607431768211455",
        "340282366920938463463374607431768211456", "-170141183460469231731687303715884105728",
        "-170141183460469231731687303715884105729", "+340282366920938463463374607431768211455",
        "12345678901234567890123456789012345678901234567890",
        "0xffffffffffffffffffffffffffffffff", "0x1ffffffffffffffffffffffffffffffff",
        "0x000000000000000000000000000000000000000001", "-0x80000000000000000000000000000000",
        "-0x80000000000000000000000000000001", "-0x7fffffffffffffffffffffffffffffff", "---",
        "...", "--- a", "...a", "..", "--", "-- ", "- a", "-a", "? a", "?a", "?", ": a", ":a",
        ":", "a:", "a: b", "a:b", "a :b", "a #b", "a#b", "#a", "#", ",a", "a,b", "[a", "a]",
        "{a", "}", "a}", "&a", "*a", "!a", "|a", ">a", "'a", "a'b", "''", "\"a", "a\"b", "%a",
        "@a", "`a", "a`", " a", "a ", " ", "  ", "\t", "a\tb", "\ta", "a\t", "a\n", "a\n\n",
        "a\n\n\n", "\n", "\n\n", "\na", "\n a", " a\nb", "  a\n", "a \nb", "a\n b", "a\n b\n",
        "a\nb ", "a\n\nb", "a\n \nb", "a\r\nb\r\n", "a\rb", "\r", "\r\n", "a\n\t b",
        "- a\n- b\n", "a: b\nc: d\n", "#!/bin/sh\necho hi\n", "\u{7f}", "a\u{7f}", "\u{85}",
        "a\u{85}b", "\u{2028}", "a\u{2028}b", "a\u{2029}", "a \u{2028}b", "a\u{2028} b",
        "\u{feff}a", "a\u{feff}", "\u{fffe}", "\u{ffff}", "\u{fffd}", "\u{a0}", "a\u{a0}",
        "\u{9f}", "\u{80}", "\u{bf}", "\u{c0}", "\u{d7ff}", "\u{e000}", "\u{efff}", "\u{f000}",
        "\u{10000}", "\u{10ffff}", "😀", "é", "中文", "\0", "a\0", "-\0", "\0-", ":\0",
        "\u{1b}[31mred\u{1b}[0m", "\u{7}", "\u{8}", "\u{b}", "\u{c}", "\u{1}", "\u{1f}",
        "a\nb\u{85}c", "a\n\u{2028}b", "a\u{2028}\n", "\\", "a\\b", "\\n",
    ]
    .iter()
    .map(|s| s.to_string())
    .collect();
    v.push("0o3".to_string() + &"7".repeat(42));
    v.push("0o4".to_string() + &"0".repeat(42));
    v.push("-0o2".to_string() + &"0".repeat(42));
    v.push("-0o2".to_string() + &"0".repeat(41) + "1");
    v.push("0b".to_string() + &"1".repeat(128));
    v.push("0b1".to_string() + &"0".repeat(128));
    v.push("-0b1".to_string() + &"0".repeat(127));
    v.push("-0b1".to_string() + &"0".repeat(126) + "1");
    v.push("a".repeat(128));
    v.push("a".repeat(129));
    v.push("é".repeat(64));
    v.push("é".repeat(65));
    v.push("x ".repeat(100));
    v.push("line\n".repeat(20));
    v
}

const PIECES: &[&str] = &[
    "a", "b", "xyz", "0", "1", "9", " ", "  ", "\t", "\n", "\n", "\r", ":", ": ", " #", "#",
    "-", "- ", "?", ",", "[", "]", "{", "}", "&", "*", "!", "|", ">", "'", "\"", "%", "@", "`",
    "\\", "---", "...", ".", "e", "x", "0x", "0o", "+", "~", "null", "true", "é", "中", "😀",
    "\u{85}", "\u{2028}", "\u{2029}", "\u{feff}", "\u{7f}", "\u{0}", "\u{1b}", "\u{a0}",
    "\u{fffe}", "\u{e000}", "\u{9f}", "\u{d7ff}", "\u{1}",
];

fn random_string(rng: &mut Rng, whole: &[String]) -> String {
    if rng.chance(25) {
        return rng.pick(whole).clone();
    }
    let n = rng.below(7);
    let mut out = String::new();
    for _ in 0..n {
        out.push_str(rng.pick(PIECES));
    }
    if rng.chance(3) {
        out = out.repeat(1 + rng.below(40) as usize);
    }
    out
}

fn random_scalar(rng: &mut Rng, whole: &[String]) -> Node {
    match rng.below(10) {
        0 => Node::Null,
        1 => Node::Bool(rng.chance(50)),
        2 => Node::Int(match rng.below(3) {
            0 => rng.below(10) as i64,
            1 => -(rng.below(1000) as i64),
            _ => rng.next() as i64,
        }),
        _ => Node::Str(random_string(rng, whole)),
    }
}

fn random_node(rng: &mut Rng, whole: &[String], depth: u32) -> Node {
    if depth == 0 || rng.chance(40) {
        return random_scalar(rng, whole);
    }
    match rng.below(3) {
        0 => {
            let n = rng.below(4);
            Node::Seq((0..n).map(|_| random_node(rng, whole, depth - 1)).collect())
        }
        1 => {
            // `(index, line)` tuples, as in the renderer's diffs
            let n = rng.below(4);
            Node::Seq(
                (0..n)
                    .map(|i| {
                        Node::Seq(vec![Node::Int(i as i64), Node::Str(random_string(rng, whole))])
                    })
                    .collect(),
            )
        }
        _ => {
            let n = rng.below(4);
            let mut entries: Vec<(String, Node)> = vec![];
            for _ in 0..n {
                let key = random_string(rng, whole);
                if entries.iter().any(|(k, _)| *k == key) {
                    continue;
                }
                let value = random_node(rng, whole, depth - 1);
                entries.push((key, value));
            }
            Node::Map(entries)
        }
    }
}

fn case(node: &Node) {
    let mut j = String::new();
    json(node, &mut j);
    let yaml = serde_yaml::to_string(node).unwrap();
    println!("  ({}, {}),", mbt(&j), mbt(&yaml));
}

pub fn main() {
    let mut rng = Rng(0x7a41_1e5e_ed00_0001);
    println!("// Generated by scripts/oracle (yaml); DO NOT EDIT.\n");
    println!("///|\n/// (compact JSON tree, `serde_yaml::to_string` of the same serde data)");
    println!("let yaml_cases : Array[(String, String)] = [");
    let s = |v: &str| Node::Str(v.to_string());
    let fixed = vec![
        Node::Seq(vec![]),
        Node::Map(vec![]),
        Node::Null,
        Node::Bool(true),
        Node::Int(-3),
        Node::Seq(vec![Node::Seq(vec![]), Node::Map(vec![]), Node::Seq(vec![Node::Seq(vec![])])]),
        Node::Map(vec![
            ("a".into(), Node::Seq(vec![])),
            ("b".into(), Node::Map(vec![])),
            ("c".into(), Node::Seq(vec![s("x"), Node::Seq(vec![s("y"), Node::Map(vec![])])])),
            (
                "d".into(),
                Node::Map(vec![(
                    "e".into(),
                    Node::Seq(vec![Node::Map(vec![
                        ("f".into(), Node::Seq(vec![Node::Int(1), s("a\nb")])),
                        ("g".into(), s("a\n")),
                    ])]),
                )]),
            ),
        ]),
        Node::Seq(vec![Node::Map(vec![(
            "lines".into(),
            Node::Seq(vec![
                Node::Seq(vec![Node::Int(0), s("hello")]),
                Node::Seq(vec![Node::Int(1), s(" x\n")]),
            ]),
        )])]),
    ];
    for node in &fixed {
        case(node);
    }
    let whole = whole_strings();
    for w in &whole {
        case(&Node::Str(w.clone()));
        case(&Node::Map(vec![("k".into(), Node::Str(w.clone())), (w.clone(), Node::Int(1))]));
        case(&Node::Seq(vec![Node::Str(w.clone()), Node::Seq(vec![Node::Str(w.clone())])]));
        case(&Node::Map(vec![(
            w.clone(),
            Node::Seq(vec![Node::Map(vec![(w.clone(), Node::Str(w.clone()))])]),
        )]));
    }
    for _ in 0..2000 {
        let depth = 1 + rng.below(5) as u32;
        case(&random_node(&mut rng, &whole, depth));
    }
    println!("]");
}
