// Terminal detection with the rules of the `console` crate. On the wasm
// backend (e.g. under `moonx`) there is no way to ask whether a stream is a
// terminal: it counts as none, so colors need `CLICOLOR_FORCE`.

///|
#cfg(target="native")
extern "C" fn scrut_isatty(fd : Int) -> Int = "scrut_isatty"

///|
#cfg(not(target="native"))
fn scrut_isatty(_fd : Int) -> Int {
  0
}

///|
/// Whether standard output (1) or standard error (2) is a terminal.
pub fn is_terminal(fd : Int) -> Bool {
  scrut_isatty(fd) != 0
}

///|
#cfg(target="native")
extern "C" fn scrut_enable_ansi(fd : Int) -> Int = "scrut_enable_ansi"

///|
#cfg(not(target="native"))
fn scrut_enable_ansi(_fd : Int) -> Int {
  1
}

///|
/// Whether colors go to standard output: a terminal that is not `dumb`
/// with `NO_COLOR` unset and `CLICOLOR` not `0`, or `CLICOLOR_FORCE` set
/// to anything but `0`.
pub fn colors_enabled(env : Map[String, String]) -> Bool {
  let supported = is_terminal(1) &&
    !env.contains("NO_COLOR") &&
    env.get("TERM") != Some("dumb") &&
    scrut_enable_ansi(1) != 0
  (supported && env.get("CLICOLOR").unwrap_or("1") != "0") ||
  env.get("CLICOLOR_FORCE").unwrap_or("0") != "0"
}

///|
#cfg(target="native")
#borrow(out)
extern "C" fn scrut_local_timestamp(out : FixedArray[Byte]) -> Int = "scrut_local_timestamp"

///|
/// The current local time as `YYYY-MM-DDTHH:MM:SS`.
#cfg(target="native")
pub fn local_timestamp() -> String? {
  let buf = FixedArray::make(20, b'\x00')
  let len = scrut_local_timestamp(buf)
  let s = StringBuilder()
  for i in 0..<len {
    s.write_char(buf[i].to_char())
  }
  Some(s.to_string())
}

///|
/// The current time on the wasm backend, which has no time zone: UTC.
#cfg(not(target="native"))
pub fn local_timestamp() -> String? {
  Some(utc_timestamp(@async.now() / 1000L))
}

///|
/// A Unix time as `YYYY-MM-DDTHH:MM:SS` in UTC (civil-from-days, Howard
/// Hinnant's algorithm).
pub fn utc_timestamp(seconds : Int64) -> String {
  let days = if seconds >= 0L {
    seconds / 86400L
  } else {
    (seconds - 86399L) / 86400L
  }
  let secs = seconds - days * 86400L
  let z = days + 719468L
  let era = (if z >= 0L { z } else { z - 146096L }) / 146097L
  let doe = z - era * 146097L
  let yoe = (doe - doe / 1460L + doe / 36524L - doe / 146096L) / 365L
  let doy = doe - (365L * yoe + yoe / 4L - yoe / 100L)
  let mp = (5L * doy + 2L) / 153L
  let day = doy - (153L * mp + 2L) / 5L + 1L
  let month = if mp < 10L { mp + 3L } else { mp - 9L }
  let year = yoe + era * 400L + (if month <= 2L { 1L } else { 0L })
  let two = (v : Int64) => if v < 10L { "0\{v}" } else { v.to_string() }
  "\{year}-\{two(month)}-\{two(day)}T\{two(secs / 3600L)}:\{two(secs % 3600L / 60L)}:\{two(secs % 60L)}"
}
