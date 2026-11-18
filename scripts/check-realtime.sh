#!/bin/sh
# Release-build check that the buffer's read and write paths (HQ-432) and the engine's IO callbacks (HQ-433)
# make no runtime calls.
# Builds ResonanceCore with `-c release`, objdumps the buffer objects and fails on swift_beginAccess,
# swift_retain/release, allocation, locks or indirect calls reachable from write/render. Pass --no-build to reuse
# the last release build.
set -eu
cd "$(dirname "$0")/.."
exec python3 -I scripts/check-realtime.py "$@"
