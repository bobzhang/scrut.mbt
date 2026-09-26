#!/bin/sh
# Build scrut and run its own tests (tests/*.md) with it. The built scrut.exe
# and scrut-testbin.exe are put first on PATH.
set -e
cd "$(dirname "$0")/.."
moon build --target native --release
build="$PWD/_build/native/release/build/cmd"
PATH="$build/scrut:$build/scrut-testbin:$PATH"
export PATH
exec scrut.exe test tests/*.md "$@"
