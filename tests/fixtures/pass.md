# Passing tests

```scrut
$ scrut-testbin.exe echo hello
hello
```

Output rules: globs, regexes, escapes and optional lines.

```scrut
$ scrut-testbin.exe print 'line 1\nline 2\n\tindented\n'
line * (glob)
line \d (regex)
\tindented (escaped)
not printed (?)
```
