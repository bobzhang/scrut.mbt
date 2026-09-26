// `scrut test`: run test documents and report (upstream
// src/bin/commands/test.rs).

///|
/// Options shared by all commands (upstream `GlobalParameters`).
pub(all) struct GlobalArgs {
  cram_compat : Bool
  /// `--combine-output` / `--no-combine-output` (the last one given).
  combine_output : Bool?
  /// `--keep-output-crlf` / `--no-keep-output-crlf` (the last one given).
  keep_output_crlf : Bool?
  escaping : @text.Escaper?
  /// Accepted for compatibility; scrut runs programs without a shell.
  shell : String?
  work_directory : String?
  keep_temporary_directories : Bool
  timeout_seconds : UInt64?
  no_color : Bool
}

///|
pub fn GlobalArgs::default() -> GlobalArgs {
  {
    cram_compat: false,
    combine_output: None,
    keep_output_crlf: None,
    escaping: None,
    shell: None,
    work_directory: None,
    keep_temporary_directories: false,
    timeout_seconds: None,
    no_color: false,
  }
}

///|
/// Document configuration from the command line.
fn GlobalArgs::to_document_config(self : GlobalArgs) -> @config.DocumentConfig {
  {
    ..@config.DocumentConfig::empty(),
    shell: self.shell,
    total_timeout: self.timeout_seconds.map(@config.Duration::from_secs),
  }
}

///|
/// Test case configuration from the command line.
fn GlobalArgs::to_testcase_config(self : GlobalArgs) -> @config.TestCaseConfig {
  {
    ..@config.TestCaseConfig::empty(),
    output_stream: self.combine_output.map(c => {
      if c {
        Combined
      } else {
        Stdout
      }
    }),
    keep_crlf: self.keep_output_crlf,
  }
}

///|
fn GlobalArgs::output_escaping(
  self : GlobalArgs,
  parser : @document.ParserType,
) -> @text.Escaper {
  match self.escaping {
    Some(e) => e
    None =>
      match parser {
        Markdown => Unicode
        Cram => Ascii
      }
  }
}

///|
pub(all) enum RendererKind {
  Auto
  Pretty
  Diff
  Json
  Yaml
  Junit
} derive(Eq, Debug)

///|
pub(all) struct TestArgs {
  paths : Array[String]
  prepend : Array[String]
  append : Array[String]
  markdown_languages : Array[String]
  match_cram : String
  match_markdown : String
  renderer : RendererKind
  absolute_line_numbers : Bool
  max_multiline_matched_lines : Int
  verbose : Bool
  global : GlobalArgs
}

///|
pub fn TestArgs::new(paths : Array[String]) -> TestArgs {
  {
    paths,
    prepend: [],
    append: [],
    markdown_languages: default_markdown_languages.iter().collect(),
    match_cram: default_match_cram,
    match_markdown: default_match_markdown,
    renderer: Auto,
    absolute_line_numbers: false,
    max_multiline_matched_lines: @render.default_multiline_matched_lines,
    verbose: false,
    global: GlobalArgs::default(),
  }
}

///|
/// Where a command writes: the report on `stdout`, progress messages on
/// `stderr` (only shown on a terminal, like upstream's progress bar).
pub(all) struct Terminal {
  write_out : async (String) -> Unit
  write_err : async (String) -> Unit
  /// Whether stdout gets colors (a color terminal, see `colors_enabled`).
  colors : Bool
  /// Whether progress messages are shown (stderr is a terminal).
  progress : Bool
}

///|
/// The exit code for failed validations.
pub let validation_failed_exit_code : Int = 50

///|
fn prefix_with_directory(
  prefix : String,
  paths : Array[String],
) -> Array[String] {
  paths.map(p => path_join(prefix, p))
}

///|
/// Run `scrut test`; returns the exit code (0, or 50 when a test case
/// failed). Other failures raise.
pub async fn run_test(args : TestArgs, term : Terminal) -> Int {
  let parser = FileParser::new(
    args.match_markdown,
    args.match_cram,
    args.markdown_languages,
  )
  let cram_compat = args.global.cram_compat
  let tests = parser.find_and_parse("test", args.paths, cram_compat)
  let outcomes : Array[@render.Outcome] = []
  let mut count_failed = 0
  let document_config = {
    ..@config.DocumentConfig::empty(),
    append: args.append,
    prepend: args.prepend,
  }.with_defaults_from(args.global.to_document_config())
  let testcase_config = args.global.to_testcase_config()
  let current = current_directory()
  let color = !args.global.no_color && term.colors
  let s = @render.Painter::new(color)
  let say = async fn(msg : String) {
    if term.progress {
      let msg = if args.global.no_color {
        @render.strip_colors(msg)
      } else {
        msg
      }
      (term.write_err)(msg + "\n")
    }
  }
  say("🔎 Found \{s.bold(tests.length().to_string())} test document(s)")
  for doc in tests {
    let test_directory = path_parent(doc.path).unwrap_or(current)
    let config = {
      ..doc.config,
      append: prefix_with_directory(test_directory, doc.config.append),
      prepend: prefix_with_directory(test_directory, doc.config.prepend),
    }.with_overrides_from(document_config)
    let env = TestEnvironment::new(
      args.global.work_directory,
      args.global.keep_temporary_directories,
    )
    let result = run_document(
      args, parser, doc, config, testcase_config, env, outcomes, s, say,
    ) catch {
      e => {
        env.cleanup()
        raise e
      }
    }
    env.cleanup()
    count_failed += result
  }
  say("")
  let rendered = match args.renderer {
    Auto | Pretty => {
      let renderer = @render.PrettyRenderer::new(
        color~,
        absolute_line_numbers=args.absolute_line_numbers,
        max_multiline_matched_lines=args.max_multiline_matched_lines,
      )
      @render.render_pretty(renderer, outcomes, styled=term.colors)
    }
    Diff =>
      @render.render_diff(outcomes) catch {
        @render.RenderError(msg) => raise AppError([msg])
      }
    Json => @render.render_json(outcomes)
    Yaml => @render.render_yaml(outcomes)
    Junit =>
      @render.render_junit(
        outcomes,
        base_directory=current,
        timestamp=local_timestamp(),
        styled=term.colors,
      )
  }
  (term.write_out)(rendered)
  if count_failed > 0 {
    validation_failed_exit_code
  } else {
    0
  }
}

///|
/// Run one document; returns the number of failed test cases.
async fn run_document(
  args : TestArgs,
  parser : FileParser,
  doc : ParsedTestFile,
  config : @config.DocumentConfig,
  testcase_config : @config.TestCaseConfig,
  env : TestEnvironment,
  outcomes : Array[@render.Outcome],
  s : @render.Painter,
  say : async (String) -> Unit,
) -> Int {
  let cram_compat = args.global.cram_compat
  let prepend_tests = if config.prepend.is_empty() {
    []
  } else {
    parser.find_and_parse("prepend test", config.prepend, cram_compat)
  }
  let append_tests = if config.append.is_empty() {
    []
  } else {
    parser.find_and_parse("append test", config.append, cram_compat)
  }
  let testcases : Array[@document.TestCase] = []
  for t in prepend_tests {
    testcases.append(t.testcases)
  }
  testcases.append(doc.testcases)
  for t in append_tests {
    testcases.append(t.testcases)
  }
  let is_cram = doc.parser_type is Cram || cram_compat
  let (work_directory, env_vars) = env.init_test_file(doc.path, is_cram)
  let testcases = testcases.map(tc => {
    ..tc,
    config: tc.config
    .with_overrides_from(testcase_config)
    .with_environment(env_vars),
  })
  let escaping = args.global.output_escaping(doc.parser_type)
  let context : @exec.Context = {
    work_directory,
    temp_directory: env.tmp_directory,
    file: doc.path,
    config,
  }
  let outcome = (tc : @document.TestCase, output, result) => @render.Outcome::{
    location: Some(doc.path),
    output,
    testcase: tc,
    format: doc.parser_type,
    escaping,
    result,
  }
  let empty_output = @exec.Output::new(Unknown)
  // Outcomes of the test cases that ran, then the ones that did not as
  // skipped (upstream `handle_early_termination`).
  let early = (outputs : Array[@exec.Output], timed_out : Bool) => {
    let mut failed = 0
    for i, output in outputs {
      if i >= testcases.length() {
        break
      }
      let tc = testcases[i]
      let result = if timed_out && output.exit_code is Timeout(_) {
        Err(@exec.TestCaseError::Timeout)
      } else {
        @exec.validate(tc, output)
      }
      if result is Err(_) {
        failed += 1
      }
      outcomes.push(outcome(tc, output, result))
    }
    for tc in testcases[outputs.length().min(testcases.length()):] {
      outcomes.push(outcome(tc, empty_output, Err(Skipped)))
    }
    failed
  }
  let execution = try {
    if is_cram {
      @exec.execute_script(testcases, context)
    } else {
      @exec.execute_document(testcases, context)
    }
  } catch {
    @exec.ExecutionError(msg) =>
      raise AppError(["failing in \{rust_debug_string(doc.path)}: \{msg}"])
    e => raise e
  }
  match execution {
    SkippedAt(index) => {
      for tc in testcases {
        outcomes.push(outcome(tc, empty_output, Err(Skipped)))
      }
      let code = match testcases.get(index) {
        Some(tc) => tc.config.skip_document_code_or_default()
        None => @config.default_skip_document_code
      }
      say(
        "⏩ \{s.blue(doc.path)}: skipped, because testcase #\{index + 1} ended in exit code \{code}",
      )
      0
    }
    TimedOut(index~, total~, outputs~) => {
      let failed = early(outputs, true)
      let (location, timeout) = if total {
        ("per-document timeout", config.total_timeout)
      } else {
        (
          "per-testcase timeout in testcase #\{index + 1}",
          testcases.get(index).bind(tc => tc.config.timeout),
        )
      }
      let timeout = match timeout {
        Some(t) => t.to_string()
        None => "<undef>"
      }
      say(
        "⌛️ \{s.red(doc.path)}: execution timed out after \{timeout} at \{location}",
      )
      failed
    }
    FailedAt(index~, outputs~) => {
      let failed = early(outputs, false)
      say(
        "⚡ \{s.red(doc.path)}: stopped at testcase #\{index + 1} due to fail_fast",
      )
      failed
    }
    Completed(outputs) => {
      let mut failed = 0
      let mut success = 0
      for i, output in outputs {
        if i >= testcases.length() {
          break
        }
        if output.exit_code is Detached {
          continue
        }
        let tc = testcases[i]
        let result = @exec.validate(tc, output)
        if result is Err(_) {
          failed += 1
        } else {
          success += 1
        }
        outcomes.push(outcome(tc, output, result))
      }
      let total = failed + success
      if failed > 0 {
        say(
          "❌ \{s.red(doc.path)}: failed \{s.red_bold(failed.to_string())} out of \{s.bold(total.to_string())} testcase\{if total == 1 { "" } else { "s" }}",
        )
      } else if args.verbose {
        say(
          "✅ \{s.green(doc.path)}: passed \{s.green_bold(success.to_string())} testcase\{if success == 1 { "" } else { "s" }}",
        )
      }
      failed
    }
  }
}
