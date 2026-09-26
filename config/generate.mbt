// Configuration helpers for generating test documents (upstream
// `TestCaseConfig::{without_environment, diff, to_yaml_one_liner}`).

///|
/// The configuration without the given variables (where they have the given
/// values).
pub fn TestCaseConfig::without_environment(
  self : TestCaseConfig,
  env : Array[(String, String)],
) -> TestCaseConfig {
  let environment = self.environment.filter(e => {
    !env.iter().any(x => x.0 == e.0 && x.1 == e.1)
  })
  { ..self, environment, }
}

///|
/// What differs from `other` (`empty()` when nothing does). Like upstream,
/// `detached_kill_signal` is not compared.
pub fn TestCaseConfig::diff(
  self : TestCaseConfig,
  other : TestCaseConfig,
) -> TestCaseConfig {
  let environment = if self.environment != other.environment {
    // As upstream (despite its comment): variables of `self`, except those
    // `other` has with a different value.
    self.environment.filter(e => {
      !other.environment.iter().any(o => o.0 == e.0 && o.1 != e.1)
    })
  } else {
    []
  }
  {
    ..TestCaseConfig::empty(),
    output_stream: if self.output_stream != other.output_stream {
      self.output_stream
    } else {
      None
    },
    keep_crlf: if self.keep_crlf != other.keep_crlf {
      self.keep_crlf
    } else {
      None
    },
    timeout: if self.timeout != other.timeout {
      self.timeout
    } else {
      None
    },
    detached: if self.detached != other.detached {
      self.detached
    } else {
      None
    },
    fail_fast: if self.fail_fast != other.fail_fast {
      self.fail_fast
    } else {
      None
    },
    skip_document_code: if self.skip_document_code != other.skip_document_code {
      self.skip_document_code
    } else {
      None
    },
    strip_ansi_escaping: if self.strip_ansi_escaping !=
      other.strip_ansi_escaping {
      self.strip_ansi_escaping
    } else {
      None
    },
    interpolated: if self.interpolated != other.interpolated {
      self.interpolated
    } else {
      None
    },
    wait: if self.wait != other.wait {
      self.wait
    } else {
      None
    },
    mode: if self.mode != other.mode {
      self.mode
    } else {
      None
    },
    environment,
    stdin: if self.stdin != other.stdin {
      self.stdin
    } else {
      None
    },
    cwd: if self.cwd != other.cwd {
      self.cwd
    } else {
      None
    },
  }
}

///|
/// The configuration as a one line YAML mapping (`{key: value, ...}`), for
/// the opening line of a Markdown code block.
pub fn TestCaseConfig::to_yaml_one_liner(self : TestCaseConfig) -> String {
  let out = []
  if self.output_stream is Some(s) {
    out.push("output_stream: \{s.name()}")
  }
  if self.keep_crlf is Some(v) {
    out.push("keep_crlf: \{v}")
  }
  if self.timeout is Some(t) {
    out.push("timeout: \{t}")
  }
  if self.detached is Some(v) {
    out.push("detached: \{v}")
  }
  if self.fail_fast is Some(v) {
    out.push("fail_fast: \{v}")
  }
  if self.skip_document_code is Some(v) {
    out.push("skip_document_code: \{v}")
  }
  if self.strip_ansi_escaping is Some(v) {
    out.push("strip_ansi_escaping: \{v}")
  }
  if self.interpolated is Some(v) {
    out.push("interpolated: \{v}")
  }
  if self.wait is Some(wait) {
    match wait.path {
      Some(path) => out.push("wait: {timeout: \{wait.timeout}, path: \{path}}")
      None => out.push("wait: \{wait.timeout}")
    }
  }
  if !self.environment.is_empty() {
    let vars = self.environment.map(e => "\{e.0}: \"\{e.1}\"")
    out.push("environment: {\{vars.join(", ")}}")
  }
  if self.mode is Some(m) {
    out.push(
      "mode: " +
      (match m {
        Output => "output"
        JsonSchema => "jsonschema"
      }),
    )
  }
  if self.stdin is Some(s) {
    out.push("stdin: \{@text.json_quote(s)}")
  }
  if self.cwd is Some(s) {
    out.push("cwd: \{@text.json_quote(s)}")
  }
  "{" + out.join(", ") + "}"
}
