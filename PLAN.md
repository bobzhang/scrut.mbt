# scrut.mbt: porting plan

## Goal

A MoonBit port of [facebookincubator/scrut](https://github.com/facebookincubator/scrut)
(upstream `bab94fb`, 0.4.3, in `.repos/scrut`), shipped as a native CLI
(`scrut test|update|create`). Later it replaces the engine behind `moon cram`.

**Compatibility policy.** Documents keep upstream's syntax (Markdown and Cram
test documents, expectation rules, inline configuration), and output matches
upstream (the `pretty`, `diff`, `json`/`yaml` and `junit` renderers, and
`update`). The one intentional difference is execution: there is no shell.

## Execution without a shell

A test case's `$ ...` line, plus its `> ...` continuation lines, is tokenized
into argv. The program is then spawned directly with `moonbitlang/async/process`
(`posix_spawn` on Unix, `CreateProcessW` on Windows).

### Tokenizer

The tokenizer uses POSIX quoting only. Its semantics are those of Python's
`shlex.split` in POSIX mode (with `punctuation_chars` off).

- Whitespace separates words. Newlines from continuation lines count as
  whitespace, and a backslash followed by a newline continues the line.
- `'...'` is fully literal.
- `"..."` is literal, except for `\"`, `\\`, `` \` ``, `\$` and a
  backslash-newline.
- Outside quotes, a backslash escapes the next character.
- Adjacent parts concatenate: `a"b c"'d'` is the single word `ab cd`.
- Nothing is expanded: no `$VAR`, `~`, globbing or command substitution.
- Leading `NAME=value` words (with `NAME` matching `[A-Za-z_][A-Za-z0-9_]*`)
  set environment variables for that process, as in sh.
- Unquoted shell operators are errors, with an actionable message: `|`, `&`,
  `;`, `<`, `>`, `(`, `)`, `` ` ``, and `$(`. A lone `$` or `$VAR` is also an
  error, because it would expand in a shell ("variable expansion is not
  supported; quote it with '...' to pass it literally").

  The consequence: every accepted command means the same thing under bash.
  That keeps upstream scrut usable as an oracle, and keeps documents
  copy-paste compatible with a terminal.

### Program lookup

- A program name without a path separator is looked up on `PATH`. On Windows,
  `PATHEXT` is also tried, as Rust's `which` does.
- Relative names that contain a separator are resolved against the working
  directory.

### Environment and files

Each test case gets a fresh environment, built in this order:

1. The inherited environment.
2. Upstream's fixed variables: `TESTDIR`, `TESTFILE`, `TMPDIR`,
   `SCRUT_TEST=path:line`, `CDPATH=`, `COLUMNS=80`, `GREP_OPTIONS=`,
   `LANG=C`, `LANGUAGE=C`, `LC_ALL=C` and `TZ=GMT`. With `--cram-compat` or
   for `.t` files, also `CRAMTMP`, `TMP` and `TEMP`. `TESTSHELL` and `SHELL`
   are dropped.
3. The document defaults, then the test case's `environment`.
4. The command's leading `NAME=value` words.

Nothing carries over between test cases (there is no shell state). The
working directory is per document (a temporary directory, or
`--work-directory`), as upstream.

### New configuration

These are the per-test-case settings a shell used to provide:

- `stdin: <string>`: data written to the process's stdin (default: empty,
  then closed).
- `cwd: <relative path>`: the working directory inside the document's work
  directory (a replacement for `cd`).

### Carried-over configuration

Kept with upstream semantics:

- **Timeouts and detached processes:** `timeout`, `total_timeout`,
  `detached` and `detached_kill_signal`. Kill signals only apply on Unix;
  Windows uses `TerminateProcess`.
- **Flow control:** `wait` (a sleep, or polling for a path),
  `skip_document_code` (80), and `fail_fast`.
- **Output handling:** `output_stream` (`stdout`, `stderr` or `combined`;
  combined means one pipe for both streams, so the interleaving matches what
  the terminal shows), `keep_crlf`, `strip_ansi_escaping`, and `interpolated`
  (`$VAR` in expectations, resolved from the test case's environment).
- **Composition:** `prepend`, `append` and `defaults`.

Dropped: `shell` / `--shell` (accepted and ignored, with a warning), and
`TESTSHELL`.

`mode: jsonschema` comes last (phase 6), using an existing MoonBit JSON
Schema validator.

## Architecture (packages)

| package | contents (upstream source) |
|---|---|
| `argv` | tokenizer, operator detection, env prefix, `PATH`/`PATHEXT` lookup |
| `text` | byte-string helpers: newline handling (`newline.rs`), escaping (`escaping.rs`), ANSI stripping, `unescape_tabs`, escaped filters |
| `rules` | `Rule` variants: equal, no-eol, escaped, glob (wildmatch), cram-glob, regex (with the regex fix-ups); the expectation grammar |
| `config` | `TestCaseConfig` and `DocumentConfig` via `moonbit-community/yaml`; durations (humantime subset); precedence (CLI > test case > document defaults > format default) |
| `parser` | the line parser, Markdown and Cram parsers (`parsers/*`) |
| `diff` | `DiffTool` (`diff.rs`), exactly upstream's greedy algorithm |
| `exec` | execution (async): per-document context, temporary directories, env, timeouts, detached/wait, skip/fail_fast, output capture, CRLF/ANSI processing |
| `render` | `pretty`, `diff` (unified), `json`, `yaml` and `junit` renderers |
| `generate` | `update` (rewriting Markdown and Cram documents) and `create` |
| `cmd/scrut` | the CLI (core `argparse`), with upstream's subcommands, flags and exit codes (0, 1, 50) |

### Regex dialect

Upstream uses Rust's `regex` crate (RE2 syntax, unanchored matching over
bytes). We use `moonbitlang/regexp`, behind a translation shim that:

- applies upstream's fix-ups (`cleanup_unrecognized_escape_sequences`,
  `escape_misused_repetition_quantifier`, `escape_misused_character_class`);
- anchors the pattern as `^...$`;
- rewrites `\xHH`, `\x{H..}`, `[[:class:]]` and `\Q...\E`.

Inline flags (`(?i)` and friends) and class set operations are rejected with a
clear error for now, and will be added to `moonbitlang/regexp` upstream.

## Testing

1. **Unit tests** per package, ported from upstream's inline tests (7.8k lines
   of Rust tests: the parsers, rules, diff, renderers and generators).
2. **Property tests** with `moonbitlang/core/quickcheck`:
   - the tokenizer against a model;
   - diff invariants (every output line is accounted for exactly once);
   - an escaping round trip.
3. **Tokenizer oracle:** `python3 -c 'shlex.split(...)'` on random command
   strings; must agree on accepted inputs.
4. **CLI oracle:** the upstream binary (`.repos/scrut/target/release/scrut`,
   built with Rust 1.97.1, with a local `build.rs` fix) runs generated
   documents whose commands are shell-free (`printf`, `cat`, a test-helper
   program).
   - Compared byte for byte: stdout of `test` under every renderer (after
     normalising temporary paths and timings), the exit code, and documents
     after `update`.
   - Documents are generated with random expectations: every rule kind and
     quantifier, escapes, optional and multiline matches, wrong exit codes,
     CRLF, no-eol output, titles and comments, in both Markdown and Cram.
5. **Selftests:** upstream's `selftest/` documents, after rewriting their
   bash-only parts, run under the MoonBit CLI.
6. **Windows:** CI on `windows-latest` runs the unit tests and the selftests
   that don't need Unix-only programs.

## Phases

1. `argv`, `text`, `rules` and `diff`, with tests (pure, no I/O).
2. `config` and `parser` (Markdown and Cram), matched against upstream's
   parser output (`--renderer json` shows parsed test cases).
3. `exec`: process running, env, timeouts, temporary directories, detached,
   wait.
4. `render` (pretty, diff, json, yaml, junit), then `scrut test` end to end
   against the oracle.
5. `generate`: `update` and `create`, against the oracle.
6. `mode: jsonschema`, Windows CI, docs; hand over to `moon cram`.
