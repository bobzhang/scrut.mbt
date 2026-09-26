// `scrut update`: re-run test documents and write them with expectations
// that match the current output (upstream src/bin/commands/update.rs).

///|
pub(all) struct UpdateArgs {
  paths : Array[String]
  markdown_languages : Array[String]
  output_suffix : String
  assume_yes : Bool
  match_cram : String
  match_markdown : String
  replace : Bool
  absolute_line_numbers : Bool
  max_multiline_matched_lines : Int
  /// Convert to this format instead of updating in place.
  convert : @document.ParserType?
  verbose : Bool
  global : GlobalArgs
}

///|
pub fn UpdateArgs::new(paths : Array[String]) -> UpdateArgs {
  {
    paths,
    markdown_languages: default_markdown_languages.iter().collect(),
    output_suffix: ".new",
    assume_yes: false,
    match_cram: default_match_cram,
    match_markdown: default_match_markdown,
    replace: false,
    absolute_line_numbers: false,
    max_multiline_matched_lines: @render.default_multiline_matched_lines,
    convert: None,
    verbose: false,
    global: GlobalArgs::default(),
  }
}

///|
/// Rust's `Debug` for a list of paths.
fn rust_debug_paths(paths : Array[String]) -> String {
  "[" + paths.map(rust_debug_string).join(", ") + "]"
}

///|
fn file_extension(t : @document.ParserType) -> String {
  match t {
    Cram => "t"
    Markdown => "md"
  }
}

///|
/// Run `scrut update`; returns the exit code.
pub async fn run_update(
  args : UpdateArgs,
  term : Terminal,
  confirm : async (String) -> Bool,
) -> Int {
  let parser = FileParser::new(
    args.match_markdown,
    args.match_cram,
    args.markdown_languages,
  )
  let tests = parser.find_and_parse("test", args.paths, args.global.cram_compat)
  if tests.is_empty() {
    (term.write_out)(
      "👋 No test documents found in \{rust_debug_paths(args.paths)}. Stopping.\n",
    )
    return 0
  }
  let document_config = args.global.to_document_config()
  let testcase_config = args.global.to_testcase_config()
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
  say("🔎 Found \{tests.length()} test document(s)")
  let mut count_updated = 0
  let mut count_unchanged = 0
  let mut count_skipped = 0
  for doc in tests {
    let config = doc.config.with_overrides_from(document_config)
    let result = with_test_environment(
      args.global.work_directory,
      args.global.keep_temporary_directories,
      env => {
        update_document(
          args, doc, config, testcase_config, env, s, say, confirm, term,
        )
      },
    )
    match result {
      Updated => count_updated += 1
      Unchanged => count_unchanged += 1
      SkippedDocument => count_skipped += 1
    }
  }
  say("")
  let summary_color = !args.global.no_color && term.colors && is_terminal(1)
  let p = @render.Painter::new(summary_color)
  let total = count_updated + count_skipped + count_unchanged
  let updated = if count_updated > 0 {
    p.green_bold("\{count_updated} updated")
  } else {
    p.green("\{count_updated} updated")
  }
  let skipped = if count_skipped > 0 {
    p.yellow_bold("\{count_skipped} skipped")
  } else {
    p.yellow("\{count_skipped} skipped")
  }
  let unchanged = if count_unchanged > 0 {
    p.magenta_bold("\{count_unchanged} unchanged")
  } else {
    p.magenta("\{count_unchanged} unchanged")
  }
  (term.write_out)(
    "\{p.underlined("Result")}: \{p.bold("\{total} document(s)")} of which \{updated}, \{skipped} and \{unchanged}\n",
  )
  0
}

///|
priv enum UpdateResult {
  Updated
  Unchanged
  SkippedDocument
}

///|
fn execution_failure(path : String, message : String) -> AppError {
  AppError(["failing in \{rust_debug_string(path)}: \{message}"])
}

///|
async fn update_document(
  args : UpdateArgs,
  doc : ParsedTestFile,
  config : @config.DocumentConfig,
  testcase_config : @config.TestCaseConfig,
  env : TestEnvironment,
  s : @render.Painter,
  say : async (String) -> Unit,
  confirm : async (String) -> Bool,
  term : Terminal,
) -> UpdateResult {
  if doc.testcases.is_empty() {
    say(
      "⏩ \{s.blue(doc.path)}: skipped, because no testcases were found in the document",
    )
    return SkippedDocument
  }
  // Upstream checks `prepend` twice (not `append`).
  if !config.prepend.is_empty() {
    say(
      "⏩ \{s.blue(doc.path)}: skipped, because 'prepend' or 'append' are currently not supported in update",
    )
    return SkippedDocument
  }
  let is_cram = doc.parser_type is Cram
  let (work_directory, env_vars) = env.init_test_file(doc.path, is_cram)
  let testcases = doc.testcases.map(tc => {
    ..tc,
    config: tc.config
    .with_overrides_from(testcase_config)
    .with_environment(env_vars),
  })
  let context : @exec.Context = {
    work_directory,
    temp_directory: env.tmp_directory,
    file: doc.path,
    config,
  }
  let execution = try {
    if is_cram {
      @exec.execute_script(testcases, context)
    } else {
      @exec.execute_document(testcases, context)
    }
  } catch {
    @exec.ExecutionError(msg) => raise execution_failure(doc.path, msg)
    e => raise e
  }
  let outputs = match execution {
    Completed(outputs) => outputs
    SkippedAt(index) => {
      let code = match testcases.get(index) {
        Some(tc) => tc.config.skip_document_code_or_default()
        None => @config.default_skip_document_code
      }
      say(
        "⏩ \{s.blue(doc.path)}: skipped, because testcase #\{index + 1} ended in exit code \{code}",
      )
      return SkippedDocument
    }
    TimedOut(index~, total~, ..) =>
      raise execution_failure(
        doc.path,
        if total {
          "timeout in executing"
        } else {
          "timeout in executing shell expression of test \{index + 1}"
        },
      )
    FailedAt(index~, ..) =>
      raise execution_failure(
        doc.path,
        "test \{index + 1} failed with fail_fast enabled",
      )
  }
  let escaping = args.global.output_escaping(doc.parser_type)
  let outcomes : Array[@render.Outcome] = []
  for i, tc in testcases {
    guard outputs.get(i) is Some(output) else { break }
    outcomes.push({
      location: Some(doc.path),
      output,
      testcase: { ..tc, config: tc.config.without_environment(env_vars), },
      format: doc.parser_type,
      escaping,
      result: @exec.validate(tc, output),
    })
  }
  let conversion = match args.convert {
    Some(c) if c != doc.parser_type => Some(c)
    _ => None
  }
  let content = read_document(doc.path)
  let updated = try {
    match conversion {
      Some(Cram) => @generate.cram_testcases(outcomes)
      Some(Markdown) =>
        @generate.markdown_testcases(outcomes, args.markdown_languages[0])
      None =>
        match doc.parser_type {
          Markdown =>
            @generate.update_markdown(
              content,
              outcomes,
              args.markdown_languages,
            )
          Cram => @generate.update_cram(content, outcomes)
        }
    }
  } catch {
    @generate.GenerateError(messages) => {
      let what = if conversion is Some(_) { "conversion" } else { "update" }
      raise AppError(
        [
          "generating \{what} for testcases in document \{rust_debug_string(doc.path)}",
          ..messages,
        ],
      )
    }
  }
  if updated == content {
    if args.verbose {
      say(
        "👍 \{s.blue(doc.path)}: keep as-is, no changes in document content",
      )
    }
    return Unchanged
  }
  // The changes, on stderr.
  let renderer = @render.PrettyRenderer::new(
    color=!args.global.no_color && term.colors,
    absolute_line_numbers=args.absolute_line_numbers,
    summarize=false,
    max_multiline_matched_lines=args.max_multiline_matched_lines,
  )
  (term.write_err)(
    @render.render_pretty(renderer, outcomes, styled=term.colors),
  )
  let output_path = match conversion {
    // Upstream converts to the file stem: in the current directory.
    Some(c) =>
      with_extension(
        path_file_stem(doc.path).unwrap_or(doc.path),
        file_extension(c),
      )
    None =>
      if args.replace {
        doc.path
      } else {
        let extension = match path_extension(doc.path) {
          Some(ext) => ext + args.output_suffix
          None => args.output_suffix
        }
        with_extension(doc.path, extension)
      }
  }
  let exists = @fs.exists(output_path) catch { _ => false }
  if !args.assume_yes && exists {
    let confirmed = confirm(
      "Overwrite existing document \{s.blue(output_path)}?",
    )
    if !confirmed {
      say(
        "👎 \{s.red(doc.path)}: keep as-is, chosen not to overwrite document",
      )
      return SkippedDocument
    }
  }
  @fs.write_file(output_path, updated, create_mode=CreateOrTruncate) catch {
    e =>
      raise AppError([
        "overwrite existing document in \{rust_debug_string(doc.path)}",
        "\{e}",
      ])
  }
  if output_path == doc.path {
    say(
      "✍️ \{s.green(doc.path)}: overwritten document with updated contents",
    )
  } else {
    say(
      "🌟 \{s.green(doc.path)}: updated document contents written to \{s.blue(output_path)}",
    )
  }
  Updated
}

///|
/// A document's text as parsed (CRLF line endings replaced).
async fn read_document(path : String) -> String {
  let data = @fs.read_file(path)
  @text.utf8_string(@text.replace_crlf(data.binary())).unwrap_or("")
}
