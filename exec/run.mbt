// Running one test case's command, without a shell.

///|
/// Where and how a document's test cases run (upstream executors/context.rs).
pub(all) struct Context {
  work_directory : String
  temp_directory : String
  /// The test document's path (as given).
  file : String
  config : @config.DocumentConfig
}

///|
fn is_windows() -> Bool {
  @async.platform is Windows
}

///|
fn path_separator() -> String {
  if is_windows() {
    ";"
  } else {
    ":"
  }
}

///|
fn has_directory(name : String) -> Bool {
  name.contains("/") || (is_windows() && name.contains("\\"))
}

///|
fn join_path(dir : String, name : String) -> String {
  if dir.is_empty() {
    name
  } else if dir.has_suffix("/") || (is_windows() && dir.has_suffix("\\")) {
    dir + name
  } else {
    dir + (if is_windows() { "\\" } else { "/" }) + name
  }
}

///|
fn env_get(env : Array[(String, String)], key : String) -> String? {
  for e in env {
    if e.0 == key || (is_windows() && e.0.to_upper() == key.to_upper()) {
      return Some(e.1)
    }
  }
  None
}

///|
fn env_set(env : Array[(String, String)], key : String, value : String) -> Unit {
  for i, e in env {
    if e.0 == key {
      env[i] = (key, value)
      return
    }
  }
  env.push((key, value))
}

///|
/// Why a program could not be run.
priv enum Lookup {
  Found(String)
  NotFound
  NotExecutable(String)
}

///|
/// Find a program like a shell does: names with a directory are used as is
/// (relative to `cwd`); others are searched on the child's `PATH`, trying
/// `PATHEXT` extensions on Windows.
async fn find_program(
  name : String,
  env : Array[(String, String)],
  cwd : String,
) -> Lookup {
  let candidates = (base : String) => {
    if !is_windows() {
      return [base]
    }
    let exts = env_get(env, "PATHEXT").unwrap_or(".COM;.EXE")
    let out = [base]
    for ext in exts.split(";") {
      let ext = ext.to_string().to_lower()
      // Batch files need `cmd.exe`: not directly executable.
      if ext == "" || ext == ".bat" || ext == ".cmd" {
        continue
      }
      if !base.to_lower().has_suffix(ext) {
        out.push(base + ext)
      }
    }
    out
  }
  let check = (path : String) => {
    if !@fs.exists(path) {
      return None
    }
    if @fs.kind(path) is Directory {
      return Some(NotExecutable(path))
    }
    if !is_windows() && !@fs.can_execute(path) {
      return Some(NotExecutable(path))
    }
    Some(Found(path))
  }
  if has_directory(name) {
    let base = if name.has_prefix("/") ||
      (is_windows() && name.length() > 1 && name[1:2] == ":") {
      name
    } else {
      join_path(cwd, name)
    }
    for c in candidates(base) {
      if check(c) is Some(r) {
        return r
      }
    }
    return NotFound
  }
  let mut not_executable : Lookup? = None
  for dir in env_get(env, "PATH").unwrap_or("").split(path_separator()) {
    let dir = dir.to_string()
    let dir = if dir.is_empty() { cwd } else { dir }
    for c in candidates(join_path(dir, name)) {
      match check(c) {
        Some(Found(_) as found) => return found
        Some(other) =>
          if not_executable is None {
            not_executable = Some(other)
          }
        None => ()
      }
    }
  }
  not_executable.unwrap_or(NotFound)
}

///|
/// The environment of a test case's program: the inherited environment,
/// the test case's `environment` (which holds scrut's variables), then the
/// command's own assignments.
pub fn process_environment(
  config : @config.TestCaseConfig,
  assignments : Array[(String, String)],
) -> Array[(String, String)] {
  let env = []
  for k, v in @sys.get_env_vars() {
    env.push((k, v))
  }
  for e in config.environment {
    env_set(env, e.0, e.1)
  }
  for e in assignments {
    env_set(env, e.0, e.1)
  }
  env
}

///|
async fn read_pipe(pipe : &@io.Reader, into : Buffer) -> Unit noraise {
  while true {
    let chunk = pipe.read_some() catch { _ => break }
    match chunk {
      Some(bytes) => into.write_bytes(bytes)
      None => break
    }
  }
}

///|
/// A failed start, reported like bash does (exit 127 or 126 and a message on
/// stderr).
fn start_failure(
  config : @config.TestCaseConfig,
  code : Int,
  message : String,
) -> Output {
  let bytes = @text.to_bytes(message + "\n")
  if config.output_stream is Some(Combined) {
    { ..Output::new(Code(code)), stdout: bytes, }
  } else {
    { ..Output::new(Code(code)), stderr: bytes, }
  }
}

///|
/// Run a test case (with its effective configuration) and capture its
/// output.
pub async fn run_testcase(tc : @document.TestCase, context : Context) -> Output {
  let config = tc.config
  let command = @argv.parse_command(tc.shell_expression) catch {
    e =>
      return start_failure(
        config,
        2,
        "scrut: cannot run `\{tc.shell_expression}`: \{e}",
      )
  }
  let env = process_environment(config, command.env)
  let cwd = match config.cwd {
    Some(sub) => join_path(context.work_directory, sub)
    None => context.work_directory
  }
  let name = command.argv[0]
  let program = match find_program(name, env, cwd) {
    Found(p) => p
    NotFound => {
      let hint = if shell_builtins.contains(name) {
        " (`\{name}` is a shell built-in; scrut runs programs without a shell)"
      } else {
        ""
      }
      return start_failure(config, 127, "\{name}: command not found\{hint}")
    }
    NotExecutable(p) =>
      return start_failure(config, 126, "\{p}: Permission denied")
  }
  let extra_env : Map[String, String] = Map([])
  for e in env {
    extra_env[e.0] = e.1
  }
  let args = command.argv[1:].iter().collect()
  let started = @async.now()
  let combined = config.output_stream is Some(Combined)
  let out_buf = Buffer()
  let err_buf = Buffer()
  let (in_r, in_w) = @process.write_to_process() catch {
    e => return start_failure(config, 126, "\{name}: \{e}")
  }
  let (out_r, out_w) = @process.read_from_process() catch {
    e => return start_failure(config, 126, "\{name}: \{e}")
  }
  let (err_r, err_w) = if combined {
    (None, out_w)
  } else {
    let (r, w) = @process.read_from_process() catch {
      e => return start_failure(config, 126, "\{name}: \{e}")
    }
    (Some(r), w)
  }
  let timeout_ms = config.timeout.map(d => d.as_millis())
  let mut spawn_error : String? = None
  let status = @async.with_task_group(group => {
    let process = @process.spawn(
      group,
      program,
      args,
      extra_env~,
      inherit_env=false,
      stdin=in_r,
      stdout=out_w,
      stderr=err_w,
      cwd~,
      cancel_handler=@process.hard_cancel(),
    ) catch {
      e => {
        in_w.close()
        spawn_error = Some("\{name}: \{e}")
        return Unknown
      }
    }
    group.spawn_bg(() => {
      let data = config.stdin.unwrap_or("")
      if !data.is_empty() {
        in_w.write(data) catch {
          _ => ()
        }
      }
      in_w.close()
    })
    let readers = [group.spawn(() => read_pipe(out_r, out_buf))]
    if err_r is Some(r) {
      readers.push(group.spawn(() => read_pipe(r, err_buf)))
    }
    let code = match timeout_ms {
      Some(ms) => @async.with_timeout_opt(ms.to_int(), () => process.wait())
      None => Some(process.wait())
    }
    match code {
      Some(code) => {
        for r in readers {
          r.wait() catch {
            _ => ()
          }
        }
        if code >= 0 {
          Code(code)
        } else {
          // Killed by a signal: what bash would report.
          Code(128 - code)
        }
      }
      None => {
        process.cancel()
        ignore(process.wait())
        for r in readers {
          r.cancel()
        }
        Timeout(config.timeout.unwrap_or(@config.Duration::zero()))
      }
    }
  }) catch {
    e => return start_failure(config, 126, "\{name}: \{e}")
  }
  if spawn_error is Some(msg) {
    return start_failure(config, 126, msg)
  }
  {
    stdout: render_output(config, out_buf.to_bytes()),
    stderr: render_output(config, err_buf.to_bytes()),
    exit_code: status,
    env,
    duration_ms: Some(@async.now() - started),
  }
}

///|
/// Shell built-ins that are commonly written in tests.
let shell_builtins : ReadOnlyArray[String] = [
  "cd", "export", "unset", "source", ".", "alias", "set", "shopt", "trap", "exit",
  "read", "eval", "exec", "pushd", "popd", "type", "declare", "local",
]

///|
/// Start a detached test case's program: output discarded, not waited for.
/// It runs in `group` and receives its kill signal when the group ends
/// (the document is done); with `detached_kill_signal: disabled` it is left
/// running.
pub async fn[X] run_detached(
  group : @async.TaskGroup[X],
  tc : @document.TestCase,
  context : Context,
) -> Output {
  let config = tc.config
  let command = @argv.parse_command(tc.shell_expression) catch {
    e =>
      return start_failure(config, 2, "scrut: cannot run `\{tc.shell_expression}`: \{e}")
  }
  let env = process_environment(config, command.env)
  let cwd = match config.cwd {
    Some(sub) => join_path(context.work_directory, sub)
    None => context.work_directory
  }
  let name = command.argv[0]
  let program = match find_program(name, env, cwd) {
    Found(p) => p
    NotFound => return start_failure(config, 127, "\{name}: command not found")
    NotExecutable(p) => return start_failure(config, 126, "\{p}: Permission denied")
  }
  let extra_env : Map[String, String] = Map([])
  for e in env {
    extra_env[e.0] = e.1
  }
  let args : Array[String] = command.argv[1:].iter().collect()
  let null_device = if is_windows() { "NUL" } else { "/dev/null" }
  let result = try {
    let (in_r, in_w) = @process.write_to_process()
    in_w.close()
    let out = @process.redirect_to_file(null_device)
    let err = @process.redirect_to_file(null_device)
    match config.detached_kill_signal {
      Some(Disabled) => {
        ignore(
          @process.spawn_orphan(
            program,
            args,
            extra_env~,
            inherit_env=false,
            stdin=in_r,
            stdout=out,
            stderr=err,
            cwd~,
          ),
        )
      }
      signal => {
        let handler = match signal {
          Some(Enabled("kill")) => @process.hard_cancel()
          Some(Enabled("int")) =>
            @process.graceful_cancel(timeout=2000, signal=SIGINT)
          Some(Enabled("hup")) =>
            @process.graceful_cancel(timeout=2000, signal=SIGHUP)
          _ => @process.graceful_cancel(timeout=2000, signal=SIGTERM)
        }
        ignore(
          @process.spawn(
            group,
            program,
            args,
            extra_env~,
            inherit_env=false,
            stdin=in_r,
            stdout=out,
            stderr=err,
            cwd~,
            cancel_handler=handler,
            no_wait=true,
          ),
        )
      }
    }
    None
  } catch {
    e => Some(e.to_string())
  }
  match result {
    Some(msg) => start_failure(config, 126, "\{name}: \{msg}")
    None => Output::new(Detached)
  }
}
