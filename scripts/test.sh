#!/bin/sh
# Runs the test suite. On a Mac with only Command Line Tools (no Xcode), SwiftPM cannot find
# the Testing framework by itself, so its search path and rpath are passed here.
# Extra arguments go straight to `swift test` (e.g. scripts/test.sh --filter PitchMode).
set -eu
cd "$(dirname "$0")/.."
F=/Library/Developer/CommandLineTools/Library/Developer/Frameworks
L=/Library/Developer/CommandLineTools/Library/Developer/usr/lib
if [ -d "$F/Testing.framework" ]; then
  exec swift test -Xswiftc -F"$F" -Xlinker -F"$F" -Xlinker -rpath -Xlinker "$F" \
    -Xlinker -rpath -Xlinker "$L" "$@"
fi
exec swift test "$@"
