///|
fn global_flags() -> Array[@argparse.FlagArg] {
  [
    FlagArg(
      "cram-compat",
      short='C',
      global=true,
      about="Be as compatible as possible with Cram: CRAM* environment variables, Cram glob rules, combined output and kept CRLF.",
    ),
    FlagArg(
      "combine-output",
      negatable=true,
      global=true,
      about="Combine STDOUT and STDERR into a single stream (per default only STDOUT is considered).",
    ),
    FlagArg(
      "keep-output-crlf",
      negatable=true,
      global=true,
      about="Keep CRLF line endings in outputs (per default they are converted to LF).",
    ),
    FlagArg(
      "keep-temporary-directories",
      global=true,
      conflicts_with=["work-directory"],
      about="Do not remove temporary directories after test execution.",
    ),
    FlagArg("no-color", global=true, about="Disable colo(u)r output."),
    FlagArg("no-colour", global=true, hidden=true),
  ]
}

///|
fn global_options() -> Array[@argparse.OptionArg] {
  [
    OptionArg(
      "escaping",
      short='e',
      global=true,
      about="Output escaping: `unicode` (default for Markdown) or `ascii` (default for Cram).",
    ),
    OptionArg(
      "shell",
      short='s',
      global=true,
      about="Accepted for compatibility and ignored: scrut runs programs without a shell.",
    ),
    OptionArg(
      "work-directory",
      short='w',
      global=true,
      about="Directory to run the tests in (per default a temporary directory per test document).",
    ),
    OptionArg(
      "timeout-seconds",
      global=true,
      about="Timeout in seconds for the whole execution of a document (0 for unlimited; default 900).",
    ),
  ]
}

///|
fn test_command() -> @argparse.Command {
  Command(
    "test",
    about="Run tests from files or directories",
    flags=[
      FlagArg("debug", hidden=true),
      FlagArg(
        "absolute-line-numbers",
        about="Use line numbers of the test document instead of relative ones.",
      ),
      FlagArg(
        "verbose",
        about="Print information that is not a warning or error.",
      ),
    ],
    options=[
      OptionArg(
        "prepend-test-file-paths",
        short='P',
        action=Append,
        about="Test documents to run before each test document (UNSTABLE).",
      ),
      OptionArg(
        "append-test-file-paths",
        short='A',
        action=Append,
        about="Test documents to run after each test document (UNSTABLE).",
      ),
      OptionArg("markdown-languages", action=Append, hidden=true),
      OptionArg(
        "match-cram",
        default_values=[@app.default_match_cram],
        about="Glob that identifies Cram documents.",
      ),
      OptionArg(
        "match-markdown",
        default_values=[@app.default_match_markdown],
        about="Glob that identifies Markdown documents.",
      ),
      OptionArg(
        "renderer",
        short='r',
        default_values=["auto"],
        about="Result format: auto, pretty, diff, json, yaml or junit.",
      ),
      OptionArg(
        "max-multiline-matched-lines",
        default_values=[@render.default_multiline_matched_lines.to_string()],
        about="Lines shown of multiline matches in failures (pretty renderer).",
      ),
    ],
    positionals=[
      PositionArg(
        "test_file_paths",
        num_args=ValueRange(lower=0),
        about="Test documents or directories",
      ),
    ],
  )
}

///|
fn root_command() -> @argparse.Command {
  Command(
    "scrut",
    about="A testing toolkit to scrutinize CLI applications",
    version=@lib.version,
    flags=global_flags(),
    options=global_options(),
    subcommands=[test_command()],
    subcommand_required=true,
  )
}

///|
suberror UsageError {
  UsageError(String)
}

///|
fn value(m : @argparse.Matches, name : String) -> String? {
  match m.values.get(name) {
    Some(vs) if vs.length() > 0 => Some(vs[vs.length() - 1])
    _ => None
  }
}

///|
fn values(m : @argparse.Matches, name : String) -> Array[String] {
  m.values.get(name).unwrap_or([])
}

///|
fn flag(m : @argparse.Matches, name : String) -> Bool {
  m.flags.get(name).unwrap_or(false)
}

///|
fn parse_uint(name : String, text : String) -> UInt64 raise UsageError {
  guard text.length() > 0 && text.iter().all(c => c >= '0' && c <= '9') else {
    raise UsageError(
      "invalid value '\{text}' for '--\{name}': invalid digit found in string",
    )
  }
  let mut v = 0UL
  for c in text {
    let next = v * 10UL + (c.to_int() - '0'.to_int()).to_uint64()
    if next / 10UL != v {
      raise UsageError(
        "invalid value '\{text}' for '--\{name}': number too large",
      )
    }
    v = next
  }
  v
}

///|
fn global_args(m : @argparse.Matches) -> @app.GlobalArgs raise UsageError {
  let escaping : @text.Escaper? = match value(m, "escaping") {
    None => None
    Some("ascii") => Some(Ascii)
    Some("unicode") => Some(Unicode)
    Some(other) =>
      raise UsageError(
        "invalid value '\{other}' for '--escaping <ESCAPING>'\n  [possible values: ascii, unicode]",
      )
  }
  {
    cram_compat: flag(m, "cram-compat"),
    combine_output: m.flags.get("combine-output"),
    keep_output_crlf: m.flags.get("keep-output-crlf"),
    escaping,
    shell: value(m, "shell"),
    work_directory: value(m, "work-directory"),
    keep_temporary_directories: flag(m, "keep-temporary-directories"),
    timeout_seconds: match value(m, "timeout-seconds") {
      Some(t) => Some(parse_uint("timeout-seconds", t))
      None => None
    },
    no_color: flag(m, "no-color") || flag(m, "no-colour"),
  }
}

///|
fn test_args(m : @argparse.Matches) -> @app.TestArgs raise UsageError {
  let renderer : @app.RendererKind = match value(m, "renderer") {
    None | Some("auto") => Auto
    Some("pretty") => Pretty
    Some("diff") => Diff
    Some("json") => Json
    Some("yaml") => Yaml
    Some("junit") => Junit
    Some(other) =>
      raise UsageError(
        "invalid value '\{other}' for '--renderer <RENDERER>'\n  [possible values: auto, pretty, diff, json, yaml, junit]",
      )
  }
  let languages = values(m, "markdown-languages")
  {
    ..@app.TestArgs::new(values(m, "test_file_paths")),
    prepend: values(m, "prepend-test-file-paths"),
    append: values(m, "append-test-file-paths"),
    markdown_languages: if languages.is_empty() {
      @app.default_markdown_languages.iter().collect()
    } else {
      languages
    },
    match_cram: value(m, "match-cram").unwrap_or(@app.default_match_cram),
    match_markdown: value(m, "match-markdown").unwrap_or(
      @app.default_match_markdown,
    ),
    renderer,
    absolute_line_numbers: flag(m, "absolute-line-numbers"),
    max_multiline_matched_lines: match value(m, "max-multiline-matched-lines") {
      Some(t) => parse_uint("max-multiline-matched-lines", t).to_int()
      None => @render.default_multiline_matched_lines
    },
    verbose: flag(m, "verbose"),
    global: global_args(m),
  }
}

///|
async fn write_stdout(text : String) -> Unit {
  @stdio.stdout.write(text)
}

///|
async fn write_stderr(text : String) -> Unit {
  @stdio.stderr.write(text)
}

///|
async fn main {
  let env = @sys.get_env_vars()
  let argv = @sys.get_cli_args()
  let matches = root_command().parse(argv=argv[1:], env~)
  let term : @app.Terminal = {
    write_out: write_stdout,
    write_err: write_stderr,
    colors: @app.colors_enabled(env),
    progress: @app.is_terminal(2),
  }
  let code = try {
    match matches.subcommand {
      Some(("test", sub)) => @app.run_test(test_args(sub), term)
      _ => {
        @stdio.stderr.write(root_command().render_help())
        2
      }
    }
  } catch {
    UsageError(msg) => {
      @stdio.stderr.write(
        "error: \{msg}\n\nFor more information, try '--help'.\n",
      )
      2
    }
    e => {
      @stdio.stderr.write("Error: \{e}\n")
      1
    }
  }
  @sys.exit(code)
}
