// Terminal detection with the rules of the `console` crate.

///|
extern "C" fn scrut_isatty(fd : Int) -> Int = "scrut_isatty"

///|
/// Whether standard output (1) or standard error (2) is a terminal.
pub fn is_terminal(fd : Int) -> Bool {
  scrut_isatty(fd) != 0
}

///|
/// Whether colors go to standard output: a terminal that is not `dumb`
/// with `NO_COLOR` unset and `CLICOLOR` not `0`, or `CLICOLOR_FORCE` set
/// to anything but `0`.
pub fn colors_enabled(env : Map[String, String]) -> Bool {
  let supported = is_terminal(1) &&
    !env.contains("NO_COLOR") &&
    env.get("TERM") != Some("dumb")
  (supported && env.get("CLICOLOR").unwrap_or("1") != "0") ||
  env.get("CLICOLOR_FORCE").unwrap_or("0") != "0"
}

///|
#borrow(out)
extern "C" fn scrut_local_timestamp(out : FixedArray[Byte]) -> Int = "scrut_local_timestamp"

///|
/// The current local time as `YYYY-MM-DDTHH:MM:SS`.
pub fn local_timestamp() -> String {
  let buf = FixedArray::make(20, b'\x00')
  let len = scrut_local_timestamp(buf)
  let s = StringBuilder()
  for i in 0..<len {
    s.write_char(buf[i].to_char())
  }
  s.to_string()
}
