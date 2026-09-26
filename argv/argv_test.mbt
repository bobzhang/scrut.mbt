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
  inspect(show("echo hello world"), content="env=[] argv=[\"echo\", \"hello\", \"world\"]")
  inspect(
    show("FOO=bar X='a b' prog --x=1 \"q q\" ''"),
    content=(
      #|env=[("FOO", "bar"), ("X", "a b")] argv=["prog", "--x=1", "q q", ""]
    ),
  )
  inspect(show("\"X=y\" prog"), content="env=[] argv=[\"X=y\", \"prog\"]")
  inspect(show("prog a \\\n  b"), content="env=[] argv=[\"prog\", \"a\", \"b\"]")
  inspect(show("prog 'multi\nline'"), content="env=[] argv=[\"prog\", \"multi\\nline\"]")
  inspect(show("prog a\nother"), content="error: one command per test case: end continuation lines with `\\` to continue the command")
  inspect(show("a | b"), content="error: pipes (`|`) are not supported (quote '|' to pass it literally)")
  inspect(show("echo $HOME"), content=(
    #|error: variable expansion (`$`) is not supported; use the `environment` configuration (quote '$' to pass it literally)
  ))
  inspect(show("ls *.md"), content="error: glob patterns (`*`) are not supported (quote '*' to pass it literally)")
  inspect(show("if true"), content="error: shell syntax (`if`) is not supported")
  inspect(show("\"if\" x"), content="env=[] argv=[\"if\", \"x\"]")
  inspect(show("X=1"), content="error: no program to run: a command made only of assignments is not supported; use the `environment` configuration")
  inspect(show("   "), content="error: empty command")
  inspect(show("cat < f"), content="error: redirections (`<`) are not supported; use the `stdin` configuration for input (quote '<' to pass it literally)")
  inspect(show("echo 'unterminated"), content="error: unmatched single quote")
}
