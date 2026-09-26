// Reading configuration from YAML (upstream deserializes with serde_yaml;
// unknown keys are ignored, as with `#[serde(default)]`).

///|
fn type_name(y : @yaml.Yaml) -> String {
  match y {
    Real(_, ..) => "floating point"
    Integer(_) => "integer"
    String(_) => "string"
    Boolean(_) => "boolean"
    Array(_) => "sequence"
    Map(_) => "map"
    Null => "unit"
    BadValue => "invalid value"
  }
}

///|
fn expect_bool(key : String, y : @yaml.Yaml) -> Bool raise ConfigError {
  match y {
    Boolean(b) => b
    _ =>
      raise ConfigError(
        "\{key}: invalid type: \{type_name(y)}, expected a boolean",
      )
  }
}

///|
/// A scalar as a string (serde_yaml reads plain scalars into strings).
fn expect_string(key : String, y : @yaml.Yaml) -> String raise ConfigError {
  match y {
    String(s) => s
    Integer(i) => i.to_string()
    Real(_, repr~) => repr
    Boolean(b) => b.to_string()
    _ =>
      raise ConfigError(
        "\{key}: invalid type: \{type_name(y)}, expected a string",
      )
  }
}

///|
fn expect_int(key : String, y : @yaml.Yaml) -> Int raise ConfigError {
  match y {
    Integer(i) if i >= -2147483648L && i <= 2147483647L => i.to_int()
    _ =>
      raise ConfigError("\{key}: invalid type: \{type_name(y)}, expected i32")
  }
}

///|
fn duration_opt(key : String, y : @yaml.Yaml) -> Duration? raise ConfigError {
  let s = expect_string(key, y)
  if s.is_empty() || s == "null" {
    return None
  }
  Some(parse_duration(s)) catch {
    DurationError(msg) => raise ConfigError("\{key}: \{msg}")
  }
}

///|
/// A test case configuration from a YAML mapping (`null` is empty).
pub fn test_case_config_from_yaml(
  y : @yaml.Yaml,
) -> TestCaseConfig raise ConfigError {
  let config = TestCaseConfig::empty()
  guard y is Map(m) else {
    if y is Null {
      return config
    }
    raise ConfigError(
      "invalid type: \{type_name(y)}, expected struct TestCaseConfig",
    )
  }
  let mut c = config
  for key, value in m {
    match key {
      "detached" => c = { ..c, detached: Some(expect_bool(key, value)), }
      "detached_kill_signal" => {
        let s = match value {
          Integer(i) => i.to_string()
          _ => expect_string(key, value)
        }
        c = {
          ..c,
          detached_kill_signal: Some(
            KillSignal::parse(s) catch {
              ConfigError(msg) => raise ConfigError("\{key}: \{msg}")
            },
          ),
        }
      }
      "fail_fast" => c = { ..c, fail_fast: Some(expect_bool(key, value)), }
      "environment" => {
        guard value is Map(env) else {
          raise ConfigError(
            "\{key}: invalid type: \{type_name(value)}, expected a map",
          )
        }
        let pairs = []
        for k, v in env {
          env_insert(pairs, k, expect_string("\{key}.\{k}", v))
        }
        c = { ..c, environment: pairs, }
      }
      "keep_crlf" => c = { ..c, keep_crlf: Some(expect_bool(key, value)), }
      "output_stream" => {
        let stream = match expect_string(key, value) {
          "stdout" => Stdout
          "stderr" => Stderr
          "combined" => Combined
          other =>
            raise ConfigError(
              "\{key}: unknown variant `\{other}`, expected one of `stdout`, `stderr`, `combined`",
            )
        }
        c = { ..c, output_stream: Some(stream), }
      }
      "skip_document_code" =>
        c = { ..c, skip_document_code: Some(expect_int(key, value)), }
      "strip_ansi_escaping" =>
        c = { ..c, strip_ansi_escaping: Some(expect_bool(key, value)), }
      "timeout" => c = { ..c, timeout: duration_opt(key, value), }
      "wait" => {
        let wait = match value {
          Map(w) => {
            guard w.get("timeout") is Some(t) else {
              raise ConfigError("\{key}: missing field `timeout`")
            }
            let text = expect_string("\{key}.timeout", t)
            let timeout = parse_duration(text) catch {
              DurationError(msg) => raise ConfigError("\{key}: \{msg}")
            }
            let path = match w.get("path") {
              Some(Null) | None => None
              Some(p) => Some(expect_string("\{key}.path", p))
            }
            { timeout, path, }
          }
          _ => {
            let text = expect_string(key, value)
            let timeout = parse_duration(text) catch {
              DurationError(msg) => raise ConfigError("\{key}: \{msg}")
            }
            { timeout, path: None, }
          }
        }
        c = { ..c, wait: Some(wait), }
      }
      "interpolated" =>
        c = { ..c, interpolated: Some(expect_bool(key, value)), }
      "mode" => {
        let mode = match expect_string(key, value) {
          "output" => Output
          "jsonschema" => JsonSchema
          other =>
            raise ConfigError(
              "\{key}: unknown variant `\{other}`, expected `output` or `jsonschema`",
            )
        }
        c = { ..c, mode: Some(mode), }
      }
      "stdin" => c = { ..c, stdin: Some(expect_string(key, value)), }
      "cwd" => c = { ..c, cwd: Some(expect_string(key, value)), }
      _ => ()
    }
  }
  c
}

///|
fn string_list(key : String, y : @yaml.Yaml) -> Array[String] raise ConfigError {
  match y {
    Array(items) => items.map(i => expect_string(key, i))
    _ =>
      raise ConfigError(
        "\{key}: invalid type: \{type_name(y)}, expected a sequence",
      )
  }
}

///|
/// A document configuration from a YAML mapping.
pub fn document_config_from_yaml(
  y : @yaml.Yaml,
) -> DocumentConfig raise ConfigError {
  guard y is Map(m) else {
    if y is Null {
      return DocumentConfig::empty()
    }
    raise ConfigError(
      "invalid type: \{type_name(y)}, expected struct DocumentConfig",
    )
  }
  let mut c = DocumentConfig::empty()
  for key, value in m {
    match key {
      "append" => c = { ..c, append: string_list(key, value), }
      "prepend" => c = { ..c, prepend: string_list(key, value), }
      "defaults" => c = { ..c, defaults: test_case_config_from_yaml(value), }
      "shell" => c = { ..c, shell: Some(expect_string(key, value)), }
      "total_timeout" => c = { ..c, total_timeout: duration_opt(key, value), }
      _ => ()
    }
  }
  c
}

///|
/// Parse YAML text (one document; empty text is `null`).
pub fn parse_yaml(text : String) -> @yaml.Yaml raise ConfigError {
  let docs = @yaml.Yaml::load_from_string(text) catch {
    e => raise ConfigError("invalid YAML: \{Repr(e)}")
  }
  match docs {
    [] => Null
    [doc, ..] => doc
  }
}
