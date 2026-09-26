// A portable stand-in for the shell tools tests use, so the same test
// documents run on every platform. Commands can be chained with `+`:
//
//   scrut-testbin print 'a\n' + stderr 'b\n' + exit 3
//
// - `echo WORD...`: the words and a line feed
// - `print TEXT`: TEXT with `\n`, `\t`, `\r`, `\\` and `\xNN` escapes
// - `stderr TEXT`: the same on standard error
// - `cat`: standard input to standard output
// - `env NAME...`: the variables' values, one per line (empty if unset)
// - `pwd`: the current directory
// - `ls [DIR]`: directory entries, sorted, one per line
// - `sleep MS`: wait
// - `exit CODE`: stop with the exit code

///|
fn unescape(text : String) -> Bytes {
  let out = Buffer()
  let chars = text.to_array()
  let mut i = 0
  let hex = (c : Char) => {
    match c {
      '0'..='9' => c.to_int() - '0'.to_int()
      'a'..='f' => c.to_int() - 'a'.to_int() + 10
      'A'..='F' => c.to_int() - 'A'.to_int() + 10
      _ => -1
    }
  }
  while i < chars.length() {
    let c = chars[i]
    if c == '\\' && i + 1 < chars.length() {
      match chars[i + 1] {
        'n' => {
          out.write_byte(b'\n')
          i += 2
          continue
        }
        't' => {
          out.write_byte(b'\t')
          i += 2
          continue
        }
        'r' => {
          out.write_byte(b'\r')
          i += 2
          continue
        }
        '\\' => {
          out.write_byte(b'\\')
          i += 2
          continue
        }
        'x' if i + 3 < chars.length() &&
          hex(chars[i + 2]) >= 0 &&
          hex(chars[i + 3]) >= 0 => {
          out.write_byte((hex(chars[i + 2]) * 16 + hex(chars[i + 3])).to_byte())
          i += 4
          continue
        }
        _ => ()
      }
    }
    out.write_string_utf8(c.to_string())
    i += 1
  }
  out.to_bytes()
}

///|
async fn run(command : Array[String]) -> Int? {
  match command {
    [] => None
    ["echo", .. words] => {
      @stdio.stdout.write(words.join(" ") + "\n")
      None
    }
    ["print", text] => {
      @stdio.stdout.write(unescape(text))
      None
    }
    ["stderr", text] => {
      @stdio.stderr.write(unescape(text))
      None
    }
    ["cat"] => {
      @stdio.stdout.write(@stdio.stdin.read_all())
      None
    }
    ["env", .. names] => {
      let env = @env.get_env_vars()
      for name in names {
        @stdio.stdout.write(env.get(name).unwrap_or("") + "\n")
      }
      None
    }
    ["pwd"] => {
      @stdio.stdout.write(@fs.realpath(".") + "\n")
      None
    }
    ["ls", .. dir] => {
      let dir = dir.get(0).unwrap_or(".")
      for entry in @fs.readdir(dir, include_hidden=true, sort=true) {
        @stdio.stdout.write(entry + "\n")
      }
      None
    }
    ["sleep", ms] => {
      @async.sleep(@string.parse_int(ms))
      None
    }
    ["exit", code] => Some(@string.parse_int(code))
    _ => {
      @stdio.stderr.write(
        "scrut-testbin: unknown command: \{command.join(" ")}\n",
      )
      Some(2)
    }
  }
}

///|
async fn main {
  let args = @env.args()[1:].to_owned()
  let mut start = 0
  for i in 0..<=args.length() {
    if i == args.length() || args[i] == "+" {
      if run(args[start:i].to_owned()) is Some(code) {
        @sys.exit(code)
      }
      start = i + 1
    }
  }
}
