# scrut.mbt

A MoonBit port of [facebookincubator/scrut](https://github.com/facebookincubator/scrut)
(MIT): CLI tests written as Markdown (`.md`) or Cram (`.t`) documents, where a
command is followed by its expected output.

The goal is to bootstrap `moon cram`: the test engine behind `moon cram` is
written in MoonBit itself, on the native backend with `moonbitlang/async`
for processes, pipes and the file system.

## Design: commands, not shell scripts

Unlike upstream, commands are **not run by a shell**. A `$ ...` line is split
into a program and its arguments, and the program is executed directly. There
are no pipes, redirections, variable expansion, globbing or shell state
carried between test cases.

This makes tests deterministic and portable: there is no dependency on bash
or any other shell, and the same documents run on Linux, macOS and
**Windows**. Processes are spawned with `moonbitlang/async/process`, which
uses `posix_spawn` on Unix and `CreateProcessW` (with correct argument
quoting) on Windows. It fits `moon cram`'s purpose of testing a project's own
executables.

Upstream is checked out in `.repos/scrut` (git-ignored) for reference and as
an oracle for the parts that carry over: document parsing, expectation rules
and output rendering.
