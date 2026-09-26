# The scrut command line

These tests run the scrut binary named by `SCRUT_BIN` on the documents in
`fixtures/` (see `scripts/selftest.sh`).

## Passing documents

```scrut
$ "$SCRUT_BIN" test "$TESTDIR/fixtures/pass.md" "$TESTDIR/fixtures/cram.t" "$TESTDIR/fixtures/variables.md"
Result: 3 document(s) with 5 testcase(s): 5 succeeded, 0 failed and 0 skipped
```

## Failures are reported with a diff, exit code 50

```scrut
$ "$SCRUT_BIN" test "$TESTDIR/fixtures/fail.md"
// =============================================================================
// @ */tests/fixtures/fail.md:4 (glob)
// -----------------------------------------------------------------------------
// # Failing tests
// -----------------------------------------------------------------------------
// $ /bin/echo world
// =============================================================================

1     | - hello
   1  | + world


// =============================================================================
// @ */tests/fixtures/fail.md:9 (glob)
// -----------------------------------------------------------------------------
// $ /bin/sh -c 'exit 3'
// =============================================================================

unexpected exit code
  expected: 0
  actual:   3

## STDOUT
## STDERR


Result: 1 document(s) with 2 testcase(s): 0 succeeded, 2 failed and 0 skipped
[50]
```

## Shell syntax is rejected with a hint

See `fixtures/grammar.md` for the messages.

```scrut
$ "$SCRUT_BIN" test "$TESTDIR/fixtures/grammar.md"
Result: 1 document(s) with 4 testcase(s): 4 succeeded, 0 failed and 0 skipped
```

## Missing documents are an error

```scrut {output_stream: stderr}
$ "$SCRUT_BIN" test does-not-exist.md
Error: read contents from test document path(s)

Caused by:
    path `does-not-exist.md` does not exist
[1]
```

## Machine readable reports

```scrut
$ "$SCRUT_BIN" test --renderer diff "$TESTDIR/fixtures/fail.md"
--- */tests/fixtures/fail.md (glob)
+++ */tests/fixtures/fail.md.new (glob)
@@ -5 +5 @@ malformed output: Failing tests
-hello
+world
@@ -10,0 +10 @@ invalid exit code: 
+[3]
[50]
```

## Creating a test from a command

````scrut
$ "$SCRUT_BIN" create --title "Say hello" -- /bin/echo hello
# Say hello

```scrut
$ /bin/echo hello
hello
```
````

```scrut
$ "$SCRUT_BIN" create --format cram -- /bin/echo hello
Command executes successfully
  $ /bin/echo hello
  hello
```
