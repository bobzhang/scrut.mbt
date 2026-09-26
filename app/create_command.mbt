// `scrut create`: run a command and write a test document for it (upstream
// src/bin/commands/create.rs).

///|
pub(all) struct CreateArgs {
  /// The command's words (`["-"]`: read the command from stdin).
  command : Array[String]
  format : @document.ParserType
  /// Where to write the document (`-`: stdout).
  output : String
  title : String
  global : GlobalArgs
}

///|
pub fn CreateArgs::new(command : Array[String]) -> CreateArgs {
  {
    command,
    format: Markdown,
    output: "-",
    title: "Command executes successfully",
    global: GlobalArgs::default(),
  }
}

///|
/// Run `scrut create`; `read_stdin` supplies the command for `-`.
pub async fn run_create(
  args : CreateArgs,
  term : Terminal,
  read_stdin : async () -> String,
) -> Int {
  let expression = if args.command == ["-"] {
    // Rust's `BufRead::lines`: without line endings.
    let text = read_stdin()
    @document.rust_lines(text).join("\n")
  } else {
    args.command.join(" ")
  }
  with_test_environment(
    args.global.work_directory,
    args.global.keep_temporary_directories,
    env => create_document(args, expression, env, term),
  )
}

///|
async fn create_document(
  args : CreateArgs,
  expression : String,
  env : TestEnvironment,
  term : Terminal,
) -> Int {
  let is_cram = args.format is Cram
  let test_file_path = path_join(env.work_directory, "testfile.tmp")
  let (work_directory, env_vars) = env.init_test_file(test_file_path, is_cram)
  let (document_config, testcase_config) = if is_cram {
    (
      @config.DocumentConfig::default_cram(),
      @config.TestCaseConfig::default_cram(),
    )
  } else {
    (
      @config.DocumentConfig::default_markdown(),
      @config.TestCaseConfig::default_markdown(),
    )
  }
  let testcase_config = testcase_config
    .with_overrides_from(args.global.to_testcase_config())
    .with_environment(env_vars)
  let testcase : @document.TestCase = {
    title: "",
    shell_expression: expression,
    body: Output([]),
    exit_code: None,
    line_number: 0,
    config: testcase_config,
  }
  let context : @exec.Context = {
    work_directory,
    temp_directory: env.tmp_directory,
    file: "testfile.tmp",
    config: document_config.with_overrides_from(
      args.global.to_document_config(),
    ),
  }
  let execution = @exec.execute_script([testcase], context) catch {
    @exec.ExecutionError(msg) => raise AppError([msg])
    e => raise e
  }
  let output = match execution {
    Completed(outputs) => outputs[0]
    SkippedAt(index) => raise AppError(["skipped test \{index + 1}"])
    TimedOut(..) => raise AppError(["timeout in executing"])
    FailedAt(index~, ..) =>
      raise AppError(["test \{index + 1} failed with fail_fast enabled"])
  }
  let testcase = {
    ..testcase,
    title: args.title,
    config: testcase_config.without_environment(env_vars),
  }
  let outcome : @render.Outcome = {
    location: None,
    output,
    testcase,
    format: args.format,
    escaping: args.global.output_escaping(args.format),
    result: @exec.validate(testcase, output),
  }
  let generated = try {
    match args.format {
      Markdown =>
        @generate.markdown_testcases([outcome], default_markdown_languages[0])
      Cram => @generate.cram_testcases([outcome])
    }
  } catch {
    @generate.GenerateError(messages) =>
      raise AppError(["generate formatted test document content", ..messages])
  }
  let s = @render.Painter::new(!args.global.no_color && term.colors)
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
  if args.output == "-" {
    say("✍️ \{s.bold("STDOUT")}: Writing generated test document")
    (term.write_out)(generated)
  } else {
    say("✍️ \{s.blue(args.output)}: Writing generated test document")
    @fs.write_file(args.output, generated, create_mode=CreateOrTruncate) catch {
      e => raise AppError(["write to output", "\{e}"])
    }
  }
  0
}
