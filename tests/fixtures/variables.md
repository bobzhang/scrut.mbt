# Variables in double quotes

```scrut {environment: {GREETING: "hello world"}}
$ scrut-testbin.exe echo "[$GREETING]" "[${GREETING}!]" "[$UNSET]"
[hello world] [hello world!] []
```

Assignments before the program set its environment:

```scrut
$ NAME="scrut" scrut-testbin.exe env NAME
scrut
```
