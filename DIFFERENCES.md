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
- **`shell` / `--shell` / `TESTSHELL`** are accepted but have no effect.
- **Cram documents** run like Markdown documents, one process per test case,
  instead of in a single shell session.
- **Directories are scanned in sorted order** (upstream uses file system
  order).
- **A scrut code block containing only comments** yields no test case
  (upstream panics).

## Known (library limits)

- **YAML configuration with duplicate keys** is rejected. serde_yaml accepts
  duplicates of fields it ignores.
- **Regex expectations use `moonbitlang/regexp`** behind a translation from
  Rust `regex` syntax. Not yet supported: inline flags (`(?i)`) and character
  class set operations (`[a-z&&[^x]]`). `\d`, `\w` and `\s` are ASCII-only.
  Word boundaries next to non-BMP characters use a workaround for a
  `moonbitlang/regexp` panic.
