// Path operations with the semantics of Rust's `std::path::Path`, which
// upstream uses for locations, file names and generated file names.

///|
fn is_separator(c : Char) -> Bool {
  c == '/' || (is_windows() && c == '\\')
}

///|
/// A path's components that `Path::components` yields: `.` only as the
/// first component of a relative path, no empty components. Each is
/// (start, end) in the path's characters.
priv struct Components {
  chars : Array[Char]
  has_root : Bool
  parts : Array[(Int, Int)]
}

///|
fn components(path : String) -> Components {
  let chars = path.to_array()
  let has_root = chars.length() > 0 && is_separator(chars[0])
  let parts = []
  let mut start = 0
  for i in 0..<=chars.length() {
    if i == chars.length() || is_separator(chars[i]) {
      let len = i - start
      let is_dot = len == 1 && chars[start] == '.'
      if len > 0 && (!is_dot || (start == 0 && !has_root)) {
        parts.push((start, i))
      }
      start = i + 1
    }
  }
  { chars, has_root, parts, }
}

///|
fn Components::text(self : Components, part : (Int, Int)) -> String {
  String::from_array(self.chars[part.0:part.1])
}

///|
/// Rust's `Path::parent` (`None` for a root or an empty path).
pub fn path_parent(path : String) -> String? {
  let c = components(path)
  guard c.parts.length() > 0 else { return None }
  let n = c.parts.length()
  if n >= 2 {
    Some(String::from_array(c.chars[:c.parts[n - 2].1]))
  } else if c.has_root {
    Some(String::from_array(c.chars[:1]))
  } else {
    Some("")
  }
}

///|
/// Rust's `Path::file_name` (`None` when the path ends in `..`, `.` or a
/// root).
pub fn path_file_name(path : String) -> String? {
  let c = components(path)
  guard c.parts.last() is Some(last) else { return None }
  let name = c.text(last)
  if name == ".." || (name == "." && last.0 == 0) {
    None
  } else {
    Some(name)
  }
}

///|
/// Rust's `rsplit_file_at_dot`: (stem, extension).
fn split_file_at_dot(name : String) -> (String, String?) {
  if name == ".." {
    return (name, None)
  }
  match name.rev_find(".") {
    Some(i) if i > 0 => (name[:i].to_owned(), Some(name[i + 1:].to_owned()))
    _ => (name, None)
  }
}

///|
/// Rust's `Path::file_stem`.
pub fn path_file_stem(path : String) -> String? {
  path_file_name(path).map(name => split_file_at_dot(name).0)
}

///|
/// Rust's `Path::extension`.
pub fn path_extension(path : String) -> String? {
  path_file_name(path).bind(name => split_file_at_dot(name).1)
}

///|
/// Rust's `Path::with_extension` (unchanged when there is no file name).
pub fn with_extension(path : String, extension : String) -> String {
  let c = components(path)
  guard c.parts.last() is Some(last) && path_file_name(path) is Some(name) else {
    return path
  }
  let stem = split_file_at_dot(name).0
  let base = String::from_array(c.chars[:last.0]) + stem
  if extension.is_empty() {
    base
  } else {
    base + "." + extension
  }
}
