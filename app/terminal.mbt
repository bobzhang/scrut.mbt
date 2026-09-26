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
