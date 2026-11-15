#!/bin/sh
# Release-build check that the buffer's read and write paths make no runtime calls (HQ-432).
# Builds ResonanceCore with `-c release`, objdumps the buffer objects and fails on swift_beginAccess,
# swift_retain/release, allocation, locks or indirect calls reachable from write/render. Pass --no-build to reuse
# the last release build.
set -eu
cd "$(dirname "$0")/.."
exec python3 -I scripts/check-realtime.py "$@"
