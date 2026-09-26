# Passing tests

```scrut
$ /bin/echo hello
hello
```

Output rules: globs, regexes, escapes and optional lines.

```scrut
$ /usr/bin/printf 'line 1\nline 2\n\tindented\n'
line * (glob)
line \d (regex)
\tindented (escaped)
not printed (?)
```
