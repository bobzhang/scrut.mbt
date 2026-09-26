#!/bin/sh
# Build scrut and run its own tests (tests/*.md) with it.
set -e
cd "$(dirname "$0")/.."
moon build --target native --release
SCRUT_BIN="$PWD/_build/native/release/build/cmd/scrut/scrut.exe"
export SCRUT_BIN
exec "$SCRUT_BIN" test tests/*.md "$@"
