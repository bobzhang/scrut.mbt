// Test document and test case configuration (upstream src/config.rs).

///|
/// A configuration error.
pub(all) suberror ConfigError {
  ConfigError(String)
} derive(Debug)

///|
pub impl Show for ConfigError with fn output(self, logger) {
  let ConfigError(msg) = self
  logger.write_string(msg)
}

///|
pub(all) enum OutputStream {
  Stdout
  Stderr
  Combined
} derive(Eq, Debug)

///|
pub fn OutputStream::name(self : OutputStream) -> String {
  match self {
    Stdout => "stdout"
    Stderr => "stderr"
    Combined => "combined"
  }
}

///|
pub(all) enum TestMode {
  Output
  JsonSchema
} derive(Eq, Debug)

///|
/// The signal sent to detached processes at the end of a document.
pub(all) enum KillSignal {
  Disabled
  /// A signal by its short lowercase name (`term`, `int`, ...).
  Enabled(String)
} derive(Eq, Debug)

///|
/// Signal short names and their numbers common to Linux and macOS.
let signal_numbers : ReadOnlyArray[(String, Int)] = [
  ("hup", 1),
  ("int", 2),
  ("quit", 3),
  ("ill", 4),
  ("trap", 5),
  ("abrt", 6),
  ("fpe", 8),
  ("kill", 9),
  ("segv", 11),
  ("pipe", 13),
  ("alrm", 14),
  ("term", 15),
]

///|
let signal_names : ReadOnlyArray[String] = [
  "hup", "int", "quit", "ill", "trap", "abrt", "bus", "fpe", "kill", "usr1", "segv",
  "usr2", "pipe", "alrm", "term", "chld", "cont", "stop", "tstp", "ttin", "ttou",
  "urg", "xcpu", "xfsz", "vtalrm", "prof", "winch", "io", "sys",
]

///|
/// Rust's `str::parse::<i32>`: an optional sign and decimal digits.
fn parse_i32(s : String) -> Int? {
  let chars = s.to_array()
  let (neg, digits) = match chars {
    ['-', .. rest] => (true, rest)
    ['+', .. rest] => (false, rest)
    _ => (false, chars[:])
  }
  if digits.length() == 0 || digits.length() > 10 {
    return None
  }
  let mut v = 0L
  for c in digits {
    guard c >= '0' && c <= '9' else { return None }
    v = v * 10L + (c.to_int() - '0'.to_int()).to_int64()
  }
  let v = if neg { -v } else { v }
  if v < -2147483648L || v > 2147483647L {
    None
  } else {
    Some(v.to_int())
  }
}

///|
pub fn KillSignal::parse(value : String) -> KillSignal raise ConfigError {
  if value.to_lower() == "disabled" {
    return Disabled
  }
  if parse_i32(value) is Some(n) {
    for p in signal_numbers {
      if p.1 == n {
        return Enabled(p.0)
      }
    }
    raise ConfigError("Invalid integer signal value \{n}")
  }
  let upper = value.to_upper()
  let name = if upper.has_prefix("SIG") { upper } else { "SIG" + upper }
  let short = name[3:].to_owned().to_lower()
  if signal_names.contains(short) {
    Enabled(short)
  } else {
    raise ConfigError("Invalid signal name \{name}")
  }
}

///|
pub fn KillSignal::to_string(self : KillSignal) -> String {
  match self {
    Disabled => "disabled"
    Enabled(name) => name
  }
}

///|
/// Wait before running a test case: a duration, optionally ending early once
/// a path exists.
pub(all) struct Wait {
  timeout : Duration
  path : String?
} derive(Eq, Debug)

///|
/// Per test case configuration. `None` means "not set" (defaults apply).
pub(all) struct TestCaseConfig {
  detached : Bool?
  detached_kill_signal : KillSignal?
  fail_fast : Bool?
  /// Sorted by name.
  environment : Array[(String, String)]
  keep_crlf : Bool?
  output_stream : OutputStream?
  skip_document_code : Int?
  strip_ansi_escaping : Bool?
  timeout : Duration?
  wait : Wait?
  interpolated : Bool?
  mode : TestMode?
  /// scrut.mbt: data written to the program's stdin.
  stdin : String?
  /// scrut.mbt: working directory, relative to the document's.
  cwd : String?
} derive(Eq, Debug)

///|
pub let default_skip_document_code : Int = 80

///|
pub let default_document_timeout_secs : UInt64 = 900

///|
pub fn TestCaseConfig::empty() -> TestCaseConfig {
  {
    detached: None,
    detached_kill_signal: None,
    fail_fast: None,
    environment: [],
    keep_crlf: None,
    output_stream: None,
    skip_document_code: None,
    strip_ansi_escaping: None,
    timeout: None,
    wait: None,
    interpolated: None,
    mode: None,
    stdin: None,
    cwd: None,
  }
}

///|
pub fn TestCaseConfig::default_markdown() -> TestCaseConfig {
  {
    ..TestCaseConfig::empty(),
    output_stream: Some(Stdout),
    skip_document_code: Some(default_skip_document_code),
    detached_kill_signal: Some(Enabled("term")),
  }
}

///|
pub fn TestCaseConfig::default_cram() -> TestCaseConfig {
  {
    ..TestCaseConfig::empty(),
    output_stream: Some(Combined),
    keep_crlf: Some(true),
    skip_document_code: Some(default_skip_document_code),
  }
}

///|
pub fn TestCaseConfig::is_empty(self : TestCaseConfig) -> Bool {
  self.output_stream is None &&
  self.keep_crlf is None &&
  self.timeout is None &&
  self.detached is None &&
  self.fail_fast is None &&
  self.wait is None &&
  self.skip_document_code is None &&
  self.strip_ansi_escaping is None &&
  self.environment.is_empty() &&
  self.interpolated is None &&
  self.mode is None &&
  self.stdin is None &&
  self.cwd is None
}

///|
fn[T] or_else(a : T?, b : T?) -> T? {
  match a {
    Some(_) => a
    None => b
  }
}

///|
/// Sorted-map insertion (later values overwrite, like `BTreeMap::insert`).
fn env_insert(
  env : Array[(String, String)],
  key : String,
  value : String,
) -> Unit {
  for i, e in env {
    if e.0 == key {
      env[i] = (key, value)
      return
    }
    if @text.compare_utf8(e.0, key) > 0 {
      env.insert(i, (key, value))
      return
    }
  }
  env.push((key, value))
}

///|
/// Fill unset fields from `defaults`. Environments are merged with the
/// defaults' values winning on duplicate names (as upstream's
/// `chain(..).collect()` into a `BTreeMap`).
pub fn TestCaseConfig::with_defaults_from(
  self : TestCaseConfig,
  defaults : TestCaseConfig,
) -> TestCaseConfig {
  let environment = []
  for e in self.environment {
    env_insert(environment, e.0, e.1)
  }
  for e in defaults.environment {
    env_insert(environment, e.0, e.1)
  }
  {
    output_stream: or_else(self.output_stream, defaults.output_stream),
    keep_crlf: or_else(self.keep_crlf, defaults.keep_crlf),
    timeout: or_else(self.timeout, defaults.timeout),
    environment,
    detached: or_else(self.detached, defaults.detached),
    detached_kill_signal: or_else(
      self.detached_kill_signal,
      defaults.detached_kill_signal,
    ),
    fail_fast: or_else(self.fail_fast, defaults.fail_fast),
    wait: or_else(self.wait, defaults.wait),
    skip_document_code: or_else(
      self.skip_document_code,
      defaults.skip_document_code,
    ),
    strip_ansi_escaping: or_else(
      self.strip_ansi_escaping,
      defaults.strip_ansi_escaping,
    ),
    interpolated: or_else(self.interpolated, defaults.interpolated),
    mode: or_else(self.mode, defaults.mode),
    stdin: or_else(self.stdin, defaults.stdin),
    cwd: or_else(self.cwd, defaults.cwd),
  }
}

///|
pub fn TestCaseConfig::with_overrides_from(
  self : TestCaseConfig,
  overrides : TestCaseConfig,
) -> TestCaseConfig {
  overrides.with_defaults_from(self)
}

///|
/// Add environment variables (overwriting).
pub fn TestCaseConfig::with_environment(
  self : TestCaseConfig,
  env : Array[(String, String)],
) -> TestCaseConfig {
  let environment = self.environment.copy()
  for e in env {
    env_insert(environment, e.0, e.1)
  }
  { ..self, environment, }
}

///|
pub fn TestCaseConfig::skip_document_code_or_default(
  self : TestCaseConfig,
) -> Int {
  self.skip_document_code.unwrap_or(default_skip_document_code)
}

///|
pub fn TestCaseConfig::is_json_schema(self : TestCaseConfig) -> Bool {
  self.mode is Some(JsonSchema)
}

///|
/// Per document configuration.
pub(all) struct DocumentConfig {
  append : Array[String]
  defaults : TestCaseConfig
  prepend : Array[String]
  shell : String?
  total_timeout : Duration?
} derive(Eq, Debug)

///|
pub fn DocumentConfig::empty() -> DocumentConfig {
  {
    append: [],
    defaults: TestCaseConfig::empty(),
    prepend: [],
    shell: None,
    total_timeout: None,
  }
}

///|
pub fn DocumentConfig::default_markdown() -> DocumentConfig {
  {
    ..DocumentConfig::empty(),
    total_timeout: Some(Duration::from_secs(default_document_timeout_secs)),
  }
}

///|
pub fn DocumentConfig::default_cram() -> DocumentConfig {
  DocumentConfig::default_markdown()
}

///|
pub fn DocumentConfig::with_defaults_from(
  self : DocumentConfig,
  defaults : DocumentConfig,
) -> DocumentConfig {
  {
    append: defaults.append + self.append,
    prepend: self.prepend + defaults.prepend,
    defaults: self.defaults.with_defaults_from(defaults.defaults),
    shell: or_else(self.shell, defaults.shell),
    total_timeout: or_else(self.total_timeout, defaults.total_timeout),
  }
}

///|
pub fn DocumentConfig::with_overrides_from(
  self : DocumentConfig,
  overrides : DocumentConfig,
) -> DocumentConfig {
  overrides.with_defaults_from(self)
}
