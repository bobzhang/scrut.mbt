# Differences from upstream scrut

scrut.mbt matches upstream scrut 0.4.3 (`bab94fb`) wherever the oracle tests
compare them. This file lists every intentional or known difference.

## Intentional

- **No shell.** Commands are tokenized into argv and executed directly. See
  PLAN.md, "Decisions after review", for the grammar and rejected syntax.
  - Nothing carries over between test cases: no exported variables, no
    `cd`.
  - Use the `environment` and `cwd` configuration instead, and `stdin` for
    input.
- **Interpolation** (`interpolated: true`) resolves `$VAR` from the
  environment passed to the program, not from a shell's environment after
  execution.
- **`shell` / `--shell`** are accepted but have no effect, and `TESTSHELL`
  is not set.
- **Cram documents** (and any document with `--cram-compat`) run one process
  per test case instead of one bash script, with upstream's script
  semantics otherwise:
  - consistent configuration is required across test cases;
  - there is only the total timeout;
  - `fail_fast` and `strip_ansi_escaping` do not apply;
  - no environment is captured for interpolation.

  The output shown for a timed-out Cram document leaves out upstream's
  random divider text.
- **Directories are scanned in sorted order** (upstream uses file system
  order).
- **A scrut code block containing only comments** yields no test case
  (upstream panics).
- **Trailing whitespace highlighting** in failure output splits at the right
  character when the whitespace is not ASCII. Upstream mixes byte and
  character offsets there, and panics or highlights too little.
- **Detached kill signals** other than `term`, `int`, `hup` and `kill` fall
  back to `term`.
- **Command line:**
  - `-P`/`-A` take one path each; repeat the flag for more.
  - Errors are printed as `Error: ...` without a log timestamp.
  - On a terminal, progress messages are printed line by line instead of
    with a progress bar.

## Known (library limits)

- **YAML configuration with duplicate keys** is rejected. serde_yaml accepts
  duplicates of fields it ignores.
- **Regex expectations use `moonbitlang/regexp`** behind a translation from
  Rust `regex` syntax. Not yet supported: inline flags (`(?i)`) and character
  class set operations (`[a-z&&[^x]]`).
  - `.`, `\d`, `\w` and `\s` are expanded to Rust's Unicode definitions,
    except `\W`, `\S` and `\D` inside a bracketed class.
  - Word boundaries (`\b`) use ASCII word characters.
  - Word boundaries next to non-BMP characters use a workaround for a
    `moonbitlang/regexp` panic.
  - Output that is not valid UTF-8 is matched part by part, as upstream's
    byte regexes do.
