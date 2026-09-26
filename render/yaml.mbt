// YAML outcomes (upstream `YamlRenderer`: `serde_yaml::to_string`, i.e.
// serde_yaml 0.9.34 driving the unsafe-libyaml 0.2.11 emitter with
// unicode output, unlimited width and two-space indentation).
//
// The emitter below follows libyaml's block states. Flow style only ever
// appears for empty collections (`[]` and `{}`), so no scalar is written
// at a flow level, and with an unlimited width nothing is folded.

///|
priv struct YamlEmitter {
  buf : StringBuilder
  mut indent : Int
  indents : Array[Int]
  /// Characters written on the current line.
  mut column : Int
  /// The last character written is whitespace.
  mut whitespace : Bool
  /// Only indentation has been written on the current line.
  mut indention : Bool
  mut mapping_context : Bool
  mut simple_key_context : Bool
}

///|
fn YamlEmitter::new() -> YamlEmitter {
  {
    buf: StringBuilder(),
    indent: -1,
    indents: [],
    column: 0,
    whitespace: true,
    indention: true,
    mapping_context: false,
    simple_key_context: false,
  }
}

///|
let yaml_best_indent = 2

///|
fn YamlEmitter::put(self : YamlEmitter, c : Char) -> Unit {
  self.buf.write_char(c)
  self.column += 1
}

///|
fn YamlEmitter::put_break(self : YamlEmitter) -> Unit {
  self.buf.write_char('\n')
  self.column = 0
}

///|
/// libyaml's `WRITE_BREAK`: `\n` becomes the line break, other breaks are
/// copied.
fn YamlEmitter::write_break(self : YamlEmitter, c : Char) -> Unit {
  if c == '\n' {
    self.put_break()
  } else {
    self.buf.write_char(c)
    self.column = 0
  }
}

///|
fn YamlEmitter::increase_indent(
  self : YamlEmitter,
  flow : Bool,
  indentless : Bool,
) -> Unit {
  self.indents.push(self.indent)
  if self.indent < 0 {
    self.indent = if flow { yaml_best_indent } else { 0 }
  } else if !indentless {
    self.indent += yaml_best_indent
  }
}

///|
fn YamlEmitter::pop_indent(self : YamlEmitter) -> Unit {
  self.indent = self.indents.pop().unwrap()
}

///|
fn YamlEmitter::write_indent(self : YamlEmitter) -> Unit {
  let indent = if self.indent >= 0 { self.indent } else { 0 }
  if !self.indention ||
    self.column > indent ||
    (self.column == indent && !self.whitespace) {
    self.put_break()
  }
  while self.column < indent {
    self.put(' ')
  }
  self.whitespace = true
  self.indention = true
}

///|
fn YamlEmitter::write_indicator(
  self : YamlEmitter,
  indicator : String,
  need_whitespace : Bool,
  is_whitespace : Bool,
  is_indention : Bool,
) -> Unit {
  if need_whitespace && !self.whitespace {
    self.put(' ')
  }
  for c in indicator {
    self.put(c)
  }
  self.whitespace = is_whitespace
  self.indention = self.indention && is_indention
}

///|
fn YamlEmitter::emit_node(
  self : YamlEmitter,
  node : @text.JsonValue,
  mapping~ : Bool,
  simple_key~ : Bool,
) -> Unit {
  self.mapping_context = mapping
  self.simple_key_context = simple_key
  match node {
    JNull => self.emit_scalar("null", Plain)
    JBool(b) => self.emit_scalar(if b { "true" } else { "false" }, Plain)
    JNumber(n) => self.emit_scalar(n, Plain)
    JString(s) => self.emit_scalar(s, infer_scalar_style(s))
    JArray([]) => self.emit_empty_flow("[", "]")
    JObject([]) => self.emit_empty_flow("{", "}")
    JArray(items) => self.emit_block_sequence(items)
    JObject(entries) => self.emit_block_mapping(entries)
  }
}

///|
fn YamlEmitter::emit_empty_flow(
  self : YamlEmitter,
  open : String,
  close : String,
) -> Unit {
  self.write_indicator(open, true, true, false)
  self.increase_indent(true, false)
  self.pop_indent()
  self.write_indicator(close, false, false, false)
}

///|
fn YamlEmitter::emit_block_sequence(
  self : YamlEmitter,
  items : Array[@text.JsonValue],
) -> Unit {
  self.increase_indent(false, self.mapping_context && !self.indention)
  for item in items {
    self.write_indent()
    self.write_indicator("-", true, false, true)
    self.emit_node(item, mapping=false, simple_key=false)
  }
  self.pop_indent()
}

///|
fn YamlEmitter::emit_block_mapping(
  self : YamlEmitter,
  entries : Array[(String, @text.JsonValue)],
) -> Unit {
  self.increase_indent(false, false)
  for entry in entries {
    let (key, value) = entry
    self.write_indent()
    // `yaml_emitter_check_simple_key`
    let analysis = analyze_scalar(key)
    if !analysis.multiline && analysis.length <= 128 {
      self.emit_node(JString(key), mapping=true, simple_key=true)
      self.write_indicator(":", false, false, false)
    } else {
      self.write_indicator("?", true, false, true)
      self.emit_node(JString(key), mapping=true, simple_key=false)
      self.write_indent()
      self.write_indicator(":", true, false, true)
    }
    self.emit_node(value, mapping=true, simple_key=false)
  }
  self.pop_indent()
}

///|
/// What `yaml_emitter_analyze_scalar` finds out about a scalar (the parts
/// that matter outside flow collections).
priv struct ScalarAnalysis {
  chars : Array[Char]
  /// UTF-8 length.
  length : Int
  multiline : Bool
  block_plain_allowed : Bool
  single_quoted_allowed : Bool
  block_allowed : Bool
}

///|
/// libyaml's `IS_PRINTABLE` (on UTF-8 lead bytes, here as code points).
fn yaml_printable(c : Char) -> Bool {
  let v = c.to_int()
  v == 0x0A ||
  (v >= 0x20 && v <= 0x7E) ||
  (v >= 0xA0 && v <= 0xD7FF) ||
  (v >= 0xE000 && v <= 0xFFFD && v != 0xFEFF) ||
  (v >= 0x10000 && v <= 0x10FFFF)
}

///|
fn yaml_break(c : Char) -> Bool {
  c is ('\r' | '\n' | '\u{85}' | '\u{2028}' | '\u{2029}')
}

///|
fn utf8_width(c : Char) -> Int {
  let v = c.to_int()
  if v < 0x80 {
    1
  } else if v < 0x800 {
    2
  } else if v < 0x10000 {
    3
  } else {
    4
  }
}

///|
fn analyze_scalar(value : String) -> ScalarAnalysis {
  let chars : Array[Char] = value.iter().collect()
  let n = chars.length()
  let length = chars.fold(init=0, (acc, c) => acc + utf8_width(c))
  if n == 0 {
    return {
      chars,
      length,
      multiline: false,
      block_plain_allowed: true,
      single_quoted_allowed: true,
      block_allowed: false,
    }
  }
  // `IS_BLANKZ` at an index; the end of the string reads as NUL.
  let blankz = (i : Int) => {
    i >= n || chars[i] is (' ' | '\t' | '\u{0}') || yaml_break(chars[i])
  }
  let mut block_indicators = false
  let mut line_breaks = false
  let mut special_characters = false
  let mut leading_space = false
  let mut leading_break = false
  let mut trailing_space = false
  let mut trailing_break = false
  let mut break_space = false
  let mut space_break = false
  let mut previous_space = false
  let mut previous_break = false
  if value.has_prefix("---") || value.has_prefix("...") {
    block_indicators = true
  }
  let mut preceded_by_whitespace = true
  let mut followed_by_whitespace = blankz(1)
  for i, c in chars {
    if i == 0 {
      match c {
        '#'
        | ','
        | '['
        | ']'
        | '{'
        | '}'
        | '&'
        | '*'
        | '!'
        | '|'
        | '>'
        | '\''
        | '"'
        | '%'
        | '@'
        | '`' => block_indicators = true
        '?' | ':' => if followed_by_whitespace { block_indicators = true }
        '-' => if followed_by_whitespace { block_indicators = true }
        _ => ()
      }
    } else {
      match c {
        ':' => if followed_by_whitespace { block_indicators = true }
        '#' => if preceded_by_whitespace { block_indicators = true }
        _ => ()
      }
    }
    if !yaml_printable(c) {
      special_characters = true
    }
    if yaml_break(c) {
      line_breaks = true
    }
    if c == ' ' {
      if i == 0 {
        leading_space = true
      }
      if i == n - 1 {
        trailing_space = true
      }
      if previous_break {
        break_space = true
      }
      previous_space = true
      previous_break = false
    } else if yaml_break(c) {
      if i == 0 {
        leading_break = true
      }
      if i == n - 1 {
        trailing_break = true
      }
      if previous_space {
        space_break = true
      }
      previous_space = false
      previous_break = true
    } else {
      previous_space = false
      previous_break = false
    }
    preceded_by_whitespace = blankz(i)
    if i + 1 < n {
      followed_by_whitespace = blankz(i + 2)
    }
  }
  let mut block_plain_allowed = true
  let mut single_quoted_allowed = true
  let mut block_allowed = true
  if leading_space || leading_break || trailing_space || trailing_break {
    block_plain_allowed = false
  }
  if trailing_space {
    block_allowed = false
  }
  if break_space {
    block_plain_allowed = false
    single_quoted_allowed = false
  }
  if space_break || special_characters {
    block_plain_allowed = false
    single_quoted_allowed = false
    block_allowed = false
  }
  if line_breaks || block_indicators {
    block_plain_allowed = false
  }
  {
    chars,
    length,
    multiline: line_breaks,
    block_plain_allowed,
    single_quoted_allowed,
    block_allowed,
  }
}

///|
fn YamlEmitter::emit_scalar(
  self : YamlEmitter,
  value : String,
  requested : ScalarStyle,
) -> Unit {
  let analysis = analyze_scalar(value)
  // `yaml_emitter_select_scalar_style`
  let mut style = if requested == Any { Plain } else { requested }
  if self.simple_key_context && analysis.multiline {
    style = DoubleQuoted
  }
  if style == Plain {
    if !analysis.block_plain_allowed {
      style = SingleQuoted
    }
    if analysis.length == 0 && self.simple_key_context {
      style = SingleQuoted
    }
  }
  if style == SingleQuoted && !analysis.single_quoted_allowed {
    style = DoubleQuoted
  }
  if style == Literal && (!analysis.block_allowed || self.simple_key_context) {
    style = DoubleQuoted
  }
  self.increase_indent(true, false)
  match style {
    Plain => self.write_plain(analysis)
    SingleQuoted => self.write_single_quoted(analysis)
    Literal => self.write_literal(analysis)
    _ => self.write_double_quoted(analysis)
  }
  self.pop_indent()
}

///|
fn YamlEmitter::write_plain(self : YamlEmitter, a : ScalarAnalysis) -> Unit {
  if !self.whitespace && a.length != 0 {
    self.put(' ')
  }
  let mut breaks = false
  for c in a.chars {
    if c == ' ' {
      self.put(c)
    } else if yaml_break(c) {
      if !breaks && c == '\n' {
        self.put_break()
      }
      self.write_break(c)
      self.indention = true
      breaks = true
    } else {
      if breaks {
        self.write_indent()
      }
      self.put(c)
      self.indention = false
      breaks = false
    }
  }
  self.whitespace = false
  self.indention = false
}

///|
fn YamlEmitter::write_single_quoted(
  self : YamlEmitter,
  a : ScalarAnalysis,
) -> Unit {
  self.write_indicator("'", true, false, false)
  let mut breaks = false
  for c in a.chars {
    if c == ' ' {
      self.put(c)
    } else if yaml_break(c) {
      if !breaks && c == '\n' {
        self.put_break()
      }
      self.write_break(c)
      self.indention = true
      breaks = true
    } else {
      if breaks {
        self.write_indent()
      }
      if c == '\'' {
        self.put('\'')
      }
      self.put(c)
      self.indention = false
      breaks = false
    }
  }
  if breaks {
    self.write_indent()
  }
  self.write_indicator("'", false, false, false)
  self.whitespace = false
  self.indention = false
}

///|
fn hex_upper(v : Int) -> Char {
  if v < 10 {
    Int::unsafe_to_char('0'.to_int() + v)
  } else {
    Int::unsafe_to_char('A'.to_int() + v - 10)
  }
}

///|
fn YamlEmitter::write_double_quoted(
  self : YamlEmitter,
  a : ScalarAnalysis,
) -> Unit {
  self.write_indicator("\"", true, false, false)
  for c in a.chars {
    if !yaml_printable(c) || yaml_break(c) || c == '"' || c == '\\' {
      self.put('\\')
      match c {
        '\u{0}' => self.put('0')
        '\u{7}' => self.put('a')
        '\u{8}' => self.put('b')
        '\t' => self.put('t')
        '\n' => self.put('n')
        '\u{b}' => self.put('v')
        '\u{c}' => self.put('f')
        '\r' => self.put('r')
        '\u{1b}' => self.put('e')
        '"' => self.put('"')
        '\\' => self.put('\\')
        '\u{85}' => self.put('N')
        '\u{a0}' => self.put('_')
        '\u{2028}' => self.put('L')
        '\u{2029}' => self.put('P')
        _ => {
          let v = c.to_int()
          let (letter, width) = if v <= 0xFF {
            ('x', 2)
          } else if v <= 0xFFFF {
            ('u', 4)
          } else {
            ('U', 8)
          }
          self.put(letter)
          for k = (width - 1) * 4; k >= 0; k = k - 4 {
            self.put(hex_upper((v >> k) & 15))
          }
        }
      }
    } else {
      self.put(c)
    }
  }
  self.write_indicator("\"", false, false, false)
  self.whitespace = false
  self.indention = false
}

///|
/// `yaml_emitter_write_block_scalar_hints`: an indentation indicator when
/// the text starts with a space or break, and the chomping indicator.
fn YamlEmitter::write_block_scalar_hints(
  self : YamlEmitter,
  chars : Array[Char],
) -> Unit {
  let n = chars.length()
  if n > 0 && (chars[0] == ' ' || yaml_break(chars[0])) {
    self.write_indicator(yaml_best_indent.to_string(), false, false, false)
  }
  let chomp = if n == 0 || !yaml_break(chars[n - 1]) {
    "-"
  } else if n == 1 || yaml_break(chars[n - 2]) {
    "+"
  } else {
    ""
  }
  if chomp != "" {
    self.write_indicator(chomp, false, false, false)
  }
}

///|
fn YamlEmitter::write_literal(self : YamlEmitter, a : ScalarAnalysis) -> Unit {
  self.write_indicator("|", true, false, false)
  self.write_block_scalar_hints(a.chars)
  self.put_break()
  self.indention = true
  self.whitespace = true
  let mut breaks = true
  for c in a.chars {
    if yaml_break(c) {
      self.write_break(c)
      self.indention = true
      breaks = true
    } else {
      if breaks {
        self.write_indent()
      }
      self.put(c)
      self.indention = false
      breaks = false
    }
  }
}

///|
/// A serialized tree as `serde_yaml::to_string` writes it: one implicit
/// document, block collections, and a final line break.
pub fn json_to_yaml(value : @text.JsonValue) -> String {
  let emitter = YamlEmitter::new()
  emitter.emit_node(value, mapping=false, simple_key=false)
  // DOCUMENT-END (implicit)
  emitter.write_indent()
  emitter.buf.to_string()
}

///|
/// All outcomes as YAML (upstream `YamlRenderer`).
pub fn render_yaml(outcomes : Array[Outcome]) -> String {
  json_to_yaml(@text.JArray(outcomes.map(o => o.to_json())))
}
