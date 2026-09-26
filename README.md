# scrut.mbt

A MoonBit port of [facebookincubator/scrut](https://github.com/facebookincubator/scrut)
(MIT): CLI tests written as Markdown (`.md`) or Cram (`.t`) documents, where a
command is followed by its expected output.

The goal is to bootstrap `moon cram`: the test engine behind `moon cram` is
written in MoonBit itself, on the native backend with `moonbitlang/async`
for processes, pipes and the file system.

````markdown
# Greeting

```scrut
$ my-tool greet "World"
Hello, World!
```

```scrut {environment: {LANG: "de"}}
$ my-tool greet --from "$TESTDIR/names.txt"
Hallo, * (glob+)
[1]
```
````

## Usage

```
moon build --target native --release
_build/native/release/build/cmd/scrut/scrut.exe test tests/
```

- `scrut test <paths>...` runs documents (directories are searched for
  `*.md`, `*.markdown`, `*.scrut`, `*.t` and `*.cram`) and reports failures.
  The exit code is 50 when a test case fails.
  - `-r pretty|diff|json|yaml|junit` picks the report format.
  - `--absolute-line-numbers` uses line numbers of the document.
  - `-e ascii|unicode` sets how output is escaped.
- `scrut update <paths>...` re-runs documents and writes them with
  expectations that match the current output:
  - `<name>.md.new` by default;
  - `--replace` to overwrite the documents;
  - `--convert cram|markdown` to convert them.
- `scrut create <command>` runs a command and prints a test document for it.

scrut also builds for the wasm backend (`moon build --target wasm`) and runs
under `moonrun`, as `moonx` runs published tools. It can test such tools
too: `$ moonx cli/jq ".a"` is an ordinary command (see
[tests/moonx.md](tests/moonx.md)).

The flags and the configuration keys (`environment`, `timeout`,
`output_stream`, `detached`, `wait`, `skip_document_code`, `fail_fast`, ...)
are upstream's. See the
[upstream documentation](https://facebookincubator.github.io/scrut/).

## Design: commands, not shell scripts

Unlike upstream, commands are **not run by a shell**. A `$ ...` line is split
into a program and its arguments, and the program is executed directly:

- Words are split with POSIX quoting: `'...'`, `"..."` and `\`. Leading
  `NAME=value` words set environment variables for the program.
- Variables expand **inside double quotes only**: `"$TESTDIR/fixture.json"`,
  `"${TMPDIR}"`. Unset variables are empty.
- Everything else a shell would interpret is an error with a hint: pipes,
  redirections, `;`, `&&`, globs, unquoted `$`, `~` and subshells. So a
  command that is accepted means exactly the same to bash.
- Nothing carries over between test cases. There is no `cd` or `export`;
  use the `cwd` and `environment` configuration, and `stdin` for input.
- A missing program exits with 127, a program that is not executable with
  126, and a program killed by a signal with 128+n, as in bash.

This makes tests deterministic and portable: there is no dependency on bash
or any other shell, and the same documents run on Linux, macOS and
**Windows**. Processes are spawned with `moonbitlang/async/process`, which
uses `posix_spawn` on Unix and `CreateProcessW` (with correct argument
quoting) on Windows. It fits `moon cram`'s purpose of testing a project's own
executables.

See [PLAN.md](PLAN.md) for the full grammar and
[DIFFERENCES.md](DIFFERENCES.md) for every difference from upstream.

## Verification

Upstream is checked out in `.repos/scrut` (git-ignored) and serves as an
oracle:

- `scripts/oracle` (Rust, linking upstream's crate) generates the test
  tables for:
  - escaping and ANSI stripping;
  - expectation rules;
  - the Unicode tables of the regex compiler, and its character classes
    and whole patterns, against the regex crate;
  - the diff algorithm;
  - document parsing;
  - globs, paths and UTF-8 errors.
- `scripts/argv_oracle.py` checks the tokenizer against bash's word
  splitting and expansion.
- `scripts/cli_oracle.py` generates random shell-free documents and
  compares `scrut test` (every renderer) and `scrut update` with the
  upstream binary byte for byte.
