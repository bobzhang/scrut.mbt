# Variables in double quotes

```scrut {environment: {GREETING: "hello world"}}
$ /usr/bin/printf '[%s]\n' "$GREETING" "${GREETING}!" "$UNSET"
[hello world]
[hello world!]
[]
```
