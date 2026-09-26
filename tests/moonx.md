# Testing `moonx` command-line tools

Tools published on mooncakes run with `moonx <package>`. scrut runs them
like any other program: `moonx` is found on `PATH`.

```scrut
$ moonx cli/echo hello world
hello world
```

```scrut
$ moonx cli/printf "%s=%d\n" answer 42
answer=42
```

Input comes from the `stdin` configuration (there are no pipes):

```scrut {stdin: "banana\napple\ncherry\n"}
$ moonx cli/sort
apple
banana
cherry
```

```scrut {stdin: "{\"a\": [1, 2, 3]}"}
$ moonx cli/jq ".a | length"
3
```

Exit codes:

```scrut
$ moonx cli/false
[1]
```
