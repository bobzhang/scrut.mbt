// Work and temporary directories and the variables every test case sees
// (upstream src/bin/utils/environment.rs).

///|
priv enum DirectoryKind {
  /// Created by scrut and removed afterwards.
  Ephemeral
  /// Given by the user: never removed.
  UserProvided
  /// Created by scrut and kept (`--keep-temporary-directories`).
  Kept
}

///|
/// The directories one test document runs in.
priv struct TestEnvironment {
  work_directory : String
  work_kind : DirectoryKind
  tmp_directory : String
  tmp_kind : DirectoryKind
  /// Names of per-document work directories already used.
  names : Map[String, Unit]
}

///|
async fn make_temp_dir(parent : String, prefix : String) -> String {
  for attempt in 0..<1000 {
    let suffix = (@async.now() * 7919L + attempt.to_int64()) % 0xFFFFFFL
    let path = path_join(parent, "\{prefix}\{suffix.to_string(radix=16)}")
    let exists = @fs.exists(path)
    if !exists {
      @fs.mkdir(path, permission=0o700)
      return path
    }
  }
  raise AppError(["create temporary directory in \{parent}"])
}

///|
async fn TestEnvironment::new(
  work_directory : String?,
  keep_temporary_directories : Bool,
) -> TestEnvironment {
  let names = Map([])
  if keep_temporary_directories {
    let work = @fs.tmpdir(prefix="execution") catch {
      e => raise AppError(["create temporary working directory", "\{e}"])
    }
    let tmp = @fs.tmpdir(prefix="temp") catch {
      e => raise AppError(["create temporary working directory", "\{e}"])
    }
    return {
      work_directory: work,
      work_kind: Kept,
      tmp_directory: tmp,
      tmp_kind: Kept,
      names,
    }
  }
  match work_directory {
    Some(directory) => {
      let tmp = make_temp_dir(directory, "temp.") catch {
        e =>
          raise AppError([
            "create temporary tmp directory in given work directory",
            "\{e}",
          ])
      }
      {
        work_directory: directory,
        work_kind: UserProvided,
        tmp_directory: tmp,
        tmp_kind: Ephemeral,
        names,
      }
    }
    None => {
      let work = @fs.tmpdir(prefix="execution") catch {
        e => raise AppError(["create temporary working directory", "\{e}"])
      }
      let tmp = path_join(work, "__tmp")
      @fs.mkdir(tmp) catch {
        e =>
          raise AppError([
            "create tmp directory in temporary work directory",
            "\{e}",
          ])
      }
      {
        work_directory: work,
        work_kind: Ephemeral,
        tmp_directory: tmp,
        tmp_kind: UserProvided,
        names,
      }
    }
  }
}

///|
/// Remove what scrut created (upstream does this on drop).
async fn TestEnvironment::cleanup(self : TestEnvironment) -> Unit noraise {
  if self.tmp_kind is Ephemeral {
    @fs.rmdir(self.tmp_directory, recursive=true) catch {
      _ => ()
    }
  }
  if self.work_kind is Ephemeral {
    @fs.rmdir(self.work_directory, recursive=true) catch {
      _ => ()
    }
  }
}

///|
/// A name for a document's work directory that is not taken yet (upstream
/// `UniqueNamer`).
async fn TestEnvironment::next_name(
  self : TestEnvironment,
  name : String,
) -> String {
  let taken = async fn(candidate : String) -> Bool {
    self.names.contains(candidate) ||
    (@fs.exists(path_join(self.work_directory, candidate)) catch { _ => false })
  }
  let mut next = name
  let mut counter = 1
  if taken(next) {
    next = "\{name}-\{counter}"
    while taken(next) {
      counter += 1
      next = "\{name}-\{counter}"
    }
  }
  self.names[next] = ()
  next
}

///|
/// The work directory and environment variables for one test document.
async fn TestEnvironment::init_test_file(
  self : TestEnvironment,
  test_file_path : String,
  cram_compat : Bool,
) -> (String, Array[(String, String)]) {
  let file_name = path_file_name(test_file_path)
  if file_name.is_empty() || file_name == "." || file_name == ".." {
    raise AppError([
      "split test document file path \{rust_debug_string(test_file_path)} into components",
      "path is not a file",
    ])
  }
  let parent = path_parent(test_file_path)
  let directory = if parent.is_empty() {
    current_directory()
  } else {
    @fs.realpath(parent) catch {
      e =>
        raise AppError([
          "split test document file path \{rust_debug_string(test_file_path)} into components",
          "split path",
          "\{e}",
        ])
    }
  }
  let work_directory = match self.work_kind {
    UserProvided => self.work_directory
    Ephemeral | Kept => {
      let path = path_join(self.work_directory, self.next_name(file_name))
      let exists = @fs.exists(path)
      if !exists {
        @fs.mkdir(path) catch {
          e => raise AppError(["create working directory", "\{e}"])
        }
      }
      path
    }
  }
  let tmp = self.tmp_directory
  let env = [
    ("TESTDIR", directory),
    ("TESTFILE", file_name),
    ("TMPDIR", tmp),
    ("LANG", "C"),
    ("LANGUAGE", "C"),
    ("LC_ALL", "C"),
    ("TZ", "GMT"),
    ("COLUMNS", "80"),
    ("CDPATH", ""),
    ("GREP_OPTIONS", ""),
  ]
  if cram_compat {
    env.push(("CRAMTMP", self.work_directory))
    env.push(("TMP", tmp))
    env.push(("TEMP", tmp))
  }
  (work_directory, env)
}

///|
/// The process's current directory.
pub async fn current_directory() -> String {
  @fs.realpath(".") catch {
    _ => "."
  }
}
