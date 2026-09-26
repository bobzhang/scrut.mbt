# The scrut command line

These tests run `scrut.exe` on the documents in `fixtures/`, with the
built `scrut.exe` and `scrut-testbin.exe` (a portable stand-in for shell
tools) on `PATH` (see `scripts/selftest.sh`).

## Passing documents

```scrut
$ scrut.exe test "$TESTDIR/fixtures/pass.md" "$TESTDIR/fixtures/cram.t" "$TESTDIR/fixtures/variables.md"
Result: 3 document(s) with 6 testcase(s): 6 succeeded, 0 failed and 0 skipped
```

## Failures are reported with a diff, exit code 50

```scrut
$ scrut.exe test "$TESTDIR/fixtures/fail.md"
// =============================================================================
// @ */tests/fixtures/fail.md:4 (glob)
// -----------------------------------------------------------------------------
// # Failing tests
// -----------------------------------------------------------------------------
// $ scrut-testbin.exe echo world
// =============================================================================

1     | - hello
   1  | + world


// =============================================================================
// @ */tests/fixtures/fail.md:9 (glob)
// -----------------------------------------------------------------------------
// $ scrut-testbin.exe exit 3
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
$ scrut.exe test "$TESTDIR/fixtures/grammar.md"
Result: 1 document(s) with 4 testcase(s): 4 succeeded, 0 failed and 0 skipped
```

## Missing documents are an error

```scrut {output_stream: stderr}
$ scrut.exe test does-not-exist.md
Error: read contents from test document path(s)

Caused by:
    path `does-not-exist.md` does not exist
[1]
```

## Machine readable reports

```scrut
$ scrut.exe test --renderer diff "$TESTDIR/fixtures/fail.md"
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
$ scrut.exe create --title "Say hello" -- scrut-testbin.exe echo hello
# Say hello

```scrut
$ scrut-testbin.exe echo hello
hello
```
````

```scrut
$ scrut.exe create --format cram -- scrut-testbin.exe echo hello
Command executes successfully
  $ scrut-testbin.exe echo hello
  hello
```
