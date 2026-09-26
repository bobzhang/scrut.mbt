// Terminal styling with the escape sequences of the `console` crate, which
// upstream renders with.

///|
/// A text style: an optional foreground color (ANSI number 0-7, `bright`
/// for the 256-color bright variant) and attributes (a bit set: bold is bit
/// 0, underlined bit 3).
priv struct Style {
  enabled : Bool
  fg : Int?
  bright : Bool
  attrs : Int
}

///|
fn style(enabled : Bool) -> Style {
  { enabled, fg: None, bright: false, attrs: 0, }
}

///|
fn Style::fg(self : Style, color : Int) -> Style {
  { ..self, fg: Some(color), }
}

///|
fn Style::black(self : Style) -> Style {
  self.fg(0)
}

///|
fn Style::red(self : Style) -> Style {
  self.fg(1)
}

///|
fn Style::green(self : Style) -> Style {
  self.fg(2)
}

///|
fn Style::yellow(self : Style) -> Style {
  self.fg(3)
}

///|
fn Style::blue(self : Style) -> Style {
  self.fg(4)
}

///|
fn Style::magenta(self : Style) -> Style {
  self.fg(5)
}

///|
fn Style::cyan(self : Style) -> Style {
  self.fg(6)
}

///|
fn Style::white(self : Style) -> Style {
  self.fg(7)
}

///|
fn Style::bright(self : Style) -> Style {
  { ..self, bright: true, }
}

///|
fn Style::bold(self : Style) -> Style {
  { ..self, attrs: self.attrs | 1, }
}

///|
fn Style::underlined(self : Style) -> Style {
  { ..self, attrs: self.attrs | (1 << 3), }
}

///|
/// `text` with the style applied (as is when styling is disabled).
fn Style::paint(self : Style, text : String) -> String {
  if !self.enabled {
    return text
  }
  let buf = StringBuilder()
  let mut reset = false
  if self.fg is Some(c) {
    if self.bright {
      buf.write_string("\u{1b}[38;5;\{c + 8}m")
    } else {
      buf.write_string("\u{1b}[\{c + 30}m")
    }
    reset = true
  }
  for bit in 0..<9 {
    if (self.attrs & (1 << bit)) != 0 {
      buf.write_string("\u{1b}[\{bit + 1}m")
      reset = true
    }
  }
  buf.write_string(text)
  if reset {
    buf.write_string("\u{1b}[0m")
  }
  buf.to_string()
}

///|
/// Remove ANSI escape sequences (upstream `strip_colors`).
pub fn strip_colors(text : String) -> String {
  @text.lossy_string(@text.strip_ansi(@text.to_bytes(text)))
}

///|
/// Styling for messages outside the renderers.
pub struct Painter {
  color : Bool
}

///|
pub fn Painter::new(color : Bool) -> Painter {
  { color, }
}

///|
pub fn Painter::bold(self : Painter, text : String) -> String {
  style(self.color).bold().paint(text)
}

///|
pub fn Painter::red(self : Painter, text : String) -> String {
  style(self.color).red().paint(text)
}

///|
pub fn Painter::red_bold(self : Painter, text : String) -> String {
  style(self.color).red().bold().paint(text)
}

///|
pub fn Painter::green(self : Painter, text : String) -> String {
  style(self.color).green().paint(text)
}

///|
pub fn Painter::green_bold(self : Painter, text : String) -> String {
  style(self.color).green().bold().paint(text)
}

///|
pub fn Painter::blue(self : Painter, text : String) -> String {
  style(self.color).blue().paint(text)
}

///|
pub fn Painter::yellow(self : Painter, text : String) -> String {
  style(self.color).yellow().paint(text)
}

///|
pub fn Painter::yellow_bold(self : Painter, text : String) -> String {
  style(self.color).yellow().bold().paint(text)
}

///|
pub fn Painter::magenta(self : Painter, text : String) -> String {
  style(self.color).magenta().paint(text)
}

///|
pub fn Painter::magenta_bold(self : Painter, text : String) -> String {
  style(self.color).magenta().bold().paint(text)
}

///|
pub fn Painter::underlined(self : Painter, text : String) -> String {
  style(self.color).underlined().paint(text)
}
