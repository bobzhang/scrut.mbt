// Checks against tables generated from Rust's globset, std::path and
// std::str (scripts/oracle, mode `misc`).

///|
/// The tables are generated on Unix (`\` escapes, `/` separates).
test "globs match like globset" {
  if @async.platform is Windows {
    return
  }
  let failures = []
  for case in glob_cases {
    let (pattern, compiles, paths) = case
    let glob = try @app.Glob::new(pattern) catch {
      _ => None
    } noraise {
      g => Some(g)
    }
    match glob {
      None => if compiles { failures.push("\{pattern}: want compiled") }
      Some(g) => {
        if !compiles {
          failures.push("\{pattern}: want error")
          continue
        }
        for entry in paths {
          if g.is_match(entry.0) != entry.1 {
            failures.push("\{pattern} on \{entry.0}: want \{entry.1}")
          }
        }
      }
    }
  }
  if !failures.is_empty() {
    fail(
      "\{failures.length()} differ:\n" +
      failures[:failures.length().min(20)].to_owned().join("\n"),
    )
  }
}

///|
test "paths behave like std::path" {
  if @async.platform is Windows {
    return
  }
  let failures = []
  for case in path_cases {
    let (path, parent, name, stem, ext) = case
    let got = (
      @app.path_parent(path).unwrap_or("<none>"),
      @app.path_file_name(path).unwrap_or(""),
      @app.path_file_stem(path).unwrap_or(""),
      @app.path_extension(path).unwrap_or("<none>"),
    )
    if got != (parent, name, stem, ext) {
      failures.push(
        "\{path}: want \{Repr((parent, name, stem, ext))}, got \{Repr(got)}",
      )
    }
  }
  if !failures.is_empty() {
    fail(
      "\{failures.length()} differ:\n" +
      failures[:failures.length().min(20)].to_owned().join("\n"),
    )
  }
}

///|
fn from_hex(s : String) -> Bytes {
  let digit = (c : Char) => {
    if c >= 'a' {
      c.to_int() - 'a'.to_int() + 10
    } else {
      c.to_int() - '0'.to_int()
    }
  }
  let chars = s.to_array()
  Bytes::makei(chars.length() / 2, i => {
    (digit(chars[2 * i]) * 16 + digit(chars[2 * i + 1])).to_byte()
  })
}

///|
test "UTF-8 errors read like Rust's" {
  let failures = []
  for case in utf8_cases {
    let (hex, want) = case
    let got = @text.rust_utf8_error(from_hex(hex)).unwrap_or("<ok>")
    if got != want {
      failures.push("\{hex}: want \{want}, got \{got}")
    }
  }
  if !failures.is_empty() {
    fail(
      "\{failures.length()} differ:\n" +
      failures[:failures.length().min(20)].to_owned().join("\n"),
    )
  }
}
