///|
fn show(cmd : String) -> String {
  try @argv.parse_command(cmd) catch {
    e => "error: \{e}"
  } noraise {
    c => "env=\{Repr(c.env)} argv=\{Repr(c.argv)}"
  }
}

///|
test "commands" {
  inspect(
    show("echo hello world"),
    content="env=[] argv=[\"echo\", \"hello\", \"world\"]",
  )
  inspect(
    show("FOO=bar X='a b' prog --x=1 \"q q\" ''"),
    content=(
      #|env=[("FOO", "bar"), ("X", "a b")] argv=["prog", "--x=1", "q q", ""]
    ),
  )
  inspect(show("\"X=y\" prog"), content="env=[] argv=[\"X=y\", \"prog\"]")
  inspect(
    show("prog a \\\n  b"),
    content="env=[] argv=[\"prog\", \"a\", \"b\"]",
  )
  inspect(
    show("prog 'multi\nline'"),
    content="env=[] argv=[\"prog\", \"multi\\nline\"]",
  )
  inspect(
    show("prog a\nother"),
    content="error: one command per test case: end continuation lines with `\\` to continue the command",
  )
  inspect(
    show("a | b"),
    content="error: pipes (`|`) are not supported (quote '|' to pass it literally)",
  )
  inspect(
    show("echo $HOME"),
    content=(
      #|error: unquoted `$` is not supported; write "$NAME" (in double quotes) to use a variable (quote '$' to pass it literally)
    ),
  )
  inspect(
    show("ls *.md"),
    content="error: glob patterns (`*`) are not supported (quote '*' to pass it literally)",
  )
  inspect(
    show("if true"),
    content="error: shell syntax (`if`) is not supported",
  )
  inspect(show("\"if\" x"), content="env=[] argv=[\"if\", \"x\"]")
  inspect(
    show("X=1"),
    content="error: no program to run: a command made only of assignments is not supported; use the `environment` configuration",
  )
  inspect(show("   "), content="error: empty command")
  inspect(
    show("cat < f"),
    content="error: redirections (`<`) are not supported; use the `stdin` configuration for input (quote '<' to pass it literally)",
  )
  inspect(show("echo 'unterminated"), content="error: unmatched single quote")
}

///|
fn show_env(cmd : String) -> String {
  let env = [("TESTDIR", "/t d"), ("FOO", "a b"), ("EMPTY", "")]
  try @argv.parse_command(cmd, env~) catch {
    e => "error: \{e}"
  } noraise {
    c => "env=\{Repr(c.env)} argv=\{Repr(c.argv)}"
  }
}

///|
test "variables in double quotes" {
  inspect(
    show_env("tool \"$TESTDIR/in.json\" \"${FOO}x\" \"$FOO_x\" \"$EMPTY\""),
    content=(
      #|env=[] argv=["tool", "/t d/in.json", "a bx", "", ""]
    ),
  )
  // Assignments see the environment before the command.
  inspect(
    show_env("OUT=\"$TESTDIR/out\" FOO=new tool \"$FOO\""),
    content=(
      #|env=[("OUT", "/t d/out"), ("FOO", "new")] argv=["tool", "a b"]
    ),
  )
  inspect(
    show_env("X=1 Y=\"$X\" tool"),
    content=(
      #|error: `$X` refers to `X` assigned earlier in the same command; use the `environment` configuration
    ),
  )
  inspect(
    show_env("tool $FOO"),
    content=(
      #|error: unquoted `$` is not supported; write "$NAME" (in double quotes) to use a variable (quote '$' to pass it literally)
    ),
  )
  inspect(
    show_env("tool \"$1\""),
    content=(
      #|error: `$1` is not supported: only $NAME and ${NAME} are supported (write \$ for a literal `$`)
    ),
  )
  inspect(
    show_env("tool \"${FOO:-x}\""),
    content=(
      #|error: `${FOO:-x}` is not supported: only $NAME and ${NAME} are supported
    ),
  )
  inspect(
    show_env("tool \"$RANDOM\""),
    content="error: `$RANDOM` is not supported: bash manages `RANDOM` itself",
  )
  inspect(
    show_env("tool \"\\$FOO\" '$FOO'"),
    content=(
      #|env=[] argv=["tool", "$FOO", "$FOO"]
    ),
  )
}
