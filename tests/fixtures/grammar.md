# Shell syntax is rejected

A command runs one program, without a shell. Anything a shell would
interpret fails with exit code 2 and a hint.

```scrut {output_stream: stderr}
$ /bin/echo a | /usr/bin/wc -l
scrut: cannot run `/bin/echo a | /usr/bin/wc -l`: pipes (`|`) are not supported (quote '|' to pass it literally)
[2]
```

```scrut {output_stream: stderr}
$ /bin/echo $HOME
scrut: cannot run `/bin/echo $HOME`: unquoted `$` is not supported; write "$NAME" (in double quotes) to use a variable (quote '$' to pass it literally)
[2]
```

```scrut {output_stream: stderr}
$ /bin/ls *.md
scrut: cannot run `/bin/ls *.md`: glob patterns (`*`) are not supported (quote '*' to pass it literally)
[2]
```

Shell built-ins are not programs:

```scrut {output_stream: stderr}
$ export FOO=bar
export: command not found (`export` is a shell built-in; scrut runs programs without a shell)
[127]
```
