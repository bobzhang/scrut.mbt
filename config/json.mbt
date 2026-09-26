///|
fn opt_bool(
  entries : Array[(String, @text.JsonValue)],
  key : String,
  v : Bool?,
) -> Unit {
  if v is Some(b) {
    entries.push((key, JBool(b)))
  }
}

///|
/// The configuration as upstream serializes it (serde field order,
/// `skip_serializing_if` rules).
pub fn TestCaseConfig::to_json(self : TestCaseConfig) -> @text.JsonValue {
  let e : Array[(String, @text.JsonValue)] = []
  opt_bool(e, "detached", self.detached)
  if self.detached_kill_signal is Some(s) {
    e.push(("detached_kill_signal", JString(s.to_string())))
  }
  opt_bool(e, "fail_fast", self.fail_fast)
  if !self.environment.is_empty() {
    e.push(
      ("environment", JObject(self.environment.map(p => (p.0, JString(p.1))))),
    )
  }
  opt_bool(e, "keep_crlf", self.keep_crlf)
  if self.output_stream is Some(s) {
    e.push(("output_stream", JString(s.name())))
  }
  if self.skip_document_code is Some(c) {
    e.push(("skip_document_code", JNumber(c.to_string())))
  }
  opt_bool(e, "strip_ansi_escaping", self.strip_ansi_escaping)
  if self.timeout is Some(t) {
    e.push(("timeout", JString(t.to_string())))
  }
  if self.wait is Some(w) {
    e.push(
      (
        "wait",
        JObject([
          ("timeout", JString(w.timeout.to_string())),
          (
            "path",
            match w.path {
              Some(p) => JString(p)
              None => JNull
            },
          ),
        ]),
      ),
    )
  }
  opt_bool(e, "interpolated", self.interpolated)
  if self.mode is Some(m) {
    e.push(
      (
        "mode",
        JString(
          match m {
            Output => "output"
            JsonSchema => "jsonschema"
          },
        ),
      ),
    )
  }
  if self.stdin is Some(s) {
    e.push(("stdin", JString(s)))
  }
  if self.cwd is Some(s) {
    e.push(("cwd", JString(s)))
  }
  JObject(e)
}

///|
pub fn DocumentConfig::to_json(self : DocumentConfig) -> @text.JsonValue {
  let e : Array[(String, @text.JsonValue)] = []
  if !self.append.is_empty() {
    e.push(("append", JArray(self.append.map(p => JString(p)))))
  }
  if !self.defaults.is_empty() {
    e.push(("defaults", self.defaults.to_json()))
  }
  if !self.prepend.is_empty() {
    e.push(("prepend", JArray(self.prepend.map(p => JString(p)))))
  }
  if self.shell is Some(s) {
    e.push(("shell", JString(s)))
  }
  // Upstream skips only the default (900s) timeout; an unset one is
  // rendered as the string "null".
  match self.total_timeout {
    Some(t) if t == Duration::from_secs(default_document_timeout_secs) => ()
    Some(t) => e.push(("total_timeout", JString(t.to_string())))
    None => e.push(("total_timeout", JString("null")))
  }
  JObject(e)
}
