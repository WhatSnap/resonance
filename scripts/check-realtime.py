#!/usr/bin/env python3
"""Proves the real-time buffer paths make no runtime calls (HQ-432).

Builds ResonanceCore in release, disassembles the buffer object files, and walks every call reachable from the
read and write entry points (direct calls, tail calls and relocated branches). It fails if that closure:

* calls anything outside the allowlist (memmove/memcpy/memset/bzero), which catches swift_beginAccess,
  swift_retain/release, swift_allocObject, malloc/free, locks, objc_msgSend and Atomics calls that were not inlined;
* makes an indirect call or branch (blr/br), which would be dynamic dispatch;
* names a forbidden symbol (listed explicitly, so the failure says what it found);
* or a root entry point is missing from the object file.

Usage: scripts/check-realtime.sh [--no-build]
"""
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
OBJ_DIR = ROOT / ".build" / "release" / "ResonanceCore.build"
OBJECTS = ["DriftCompensatedBuffer.swift.o", "SPSCRingBuffer.swift.o", "HALOutput.swift.o", "TapCapture.swift.o"]

# Entry points the producer and consumer threads call (demangled, simplified, prefix match).
ROOTS = [
    "DriftCompensatedBuffer.write(left:right:frameCount:hostTime:)",
    "DriftCompensatedBuffer.render(left:right:frameCount:hostTime:)",
    "DriftCompensatedBuffer.fillLevel.getter",
    "DriftCompensatedBuffer.underrunCount.getter",
    "DriftCompensatedBuffer.droppedChunkCount.getter",
    "DriftCompensatedBuffer.isPrimed.getter",
    "DriftCompensatedBuffer.currentRatio.getter",
    "DriftCompensatedBuffer.estimatedLevel.getter",
    "SPSCRingBuffer.write(left:right:frameCount:)",
    "SPSCRingBuffer.peek(left:right:maxFrames:)",
    "SPSCRingBuffer.advance(by:)",
    "SPSCRingBuffer.read(left:right:frameCount:)",
    "SPSCRingBuffer.fillLevel.getter",
    # HQ-433 engine callbacks: the capture IOProc and the output render callbacks.
    "TapCaptureContext.process(",
    "HALOutputContext.pull(",
    "@objc halOutputPullBuffer(",
    "@objc halOutputPullPitch(",
    "@objc tapCaptureIOProc(",
]
# Checked too when present (private helpers may be fully inlined and vanish).
OPTIONAL_ROOTS = [
    "DriftCompensatedBuffer.renderBlock(",
    "DriftCompensatedBuffer.estimateLevel(",
    "DriftCompensatedBuffer.prime(",
]
ALLOWED_EXTERNAL = {"_memmove", "_memcpy", "_memset", "_bzero", "___bzero",
                    "_AudioUnitRender", "_vDSP_maxmgv", "_mach_absolute_time", "___stack_chk_fail"}
FORBIDDEN = re.compile(
    r"swift_beginAccess|swift_endAccess|swift_retain|swift_release|swift_allocObject|swift_slowAlloc|"
    r"swift_slowDealloc|swift_once|_malloc|_calloc|_realloc|_free\b|os_unfair_lock|pthread_|NSLock|"
    r"objc_msgSend|dispatch_|Atomics"
)

FUNC_RE = re.compile(r"^[0-9a-f]+ <(.+)>:$")
RELOC_RE = re.compile(r"RELOC_BRANCH\w*\s+(\S+)")
DIRECT_RE = re.compile(r"\t(?:bl|b)\t0x[0-9a-f]+ <([^>+]+)>")
INDIRECT_RE = re.compile(r"\t(?:blr|br|braa|blraa|braaz|blraaz)\t")


def demangle(names):
    out = subprocess.run(["xcrun", "swift-demangle", "--simplified"], input="\n".join(names),
                         capture_output=True, text=True, check=True).stdout.splitlines()
    return dict(zip(names, out))


def parse(obj):
    """Returns {function: (set of call targets, indirect-branch count)} for one object file."""
    text = subprocess.run(["objdump", "-d", "-r", "--no-show-raw-insn", str(obj)],
                          capture_output=True, text=True, check=True).stdout
    funcs, cur = {}, None
    for line in text.splitlines():
        m = FUNC_RE.match(line)
        if m:
            cur = m.group(1)
            funcs[cur] = [set(), 0]
            continue
        if cur is None:
            continue
        for rx in (RELOC_RE, DIRECT_RE):
            m = rx.search(line)
            if m and m.group(1) != cur:
                funcs[cur][0].add(m.group(1))
        if INDIRECT_RE.search(line):
            funcs[cur][1] += 1
    return funcs


def main():
    if "--no-build" not in sys.argv:
        subprocess.run(["swift", "build", "-c", "release", "--target", "ResonanceCore"], cwd=ROOT, check=True,
                       stdout=subprocess.DEVNULL)
    funcs = {}
    for name in OBJECTS:
        path = OBJ_DIR / name
        if not path.exists():
            print(f"FAIL: missing {path}")
            return 1
        funcs.update(parse(path))
    names = demangle(sorted(set(funcs) | {t for f in funcs.values() for t in f[0]}))

    def find(prefix):
        return [f for f in funcs if names[f].startswith(prefix)]

    failures, roots = [], []
    for r in ROOTS:
        hits = find(r)
        if not hits:
            failures.append(f"root not found in object files: {r}")
        roots += hits
    for r in OPTIONAL_ROOTS:
        roots += find(r)

    seen, stack, parent = set(), list(roots), {}
    while stack:
        f = stack.pop()
        if f in seen:
            continue
        seen.add(f)
        targets, indirect = funcs.get(f, (set(), 0))
        if indirect:
            failures.append(f"{names[f]}: {indirect} indirect call/branch")
        for t in sorted(targets):
            if t in funcs:  # defined in the buffer objects: follow it
                parent.setdefault(t, f)
                stack.append(t)
            elif t not in ALLOWED_EXTERNAL or FORBIDDEN.search(t):
                failures.append(f"{names[f]} calls {names.get(t, t)} ({t})")

    print(f"Real-time closure: {len(seen)} functions from {len(roots)} roots")
    for f in sorted(seen, key=lambda f: names[f]):
        ext = sorted(names.get(t, t) for t in funcs[f][0] if t not in funcs)
        print(f"  {names[f]}" + (f"  -> {', '.join(ext)}" if ext else ""))
    if failures:
        print("FAIL:")
        for msg in failures:
            print(f"  {msg}")
        return 1
    print("PASS: no runtime, allocation, lock or indirect calls on the read/write paths")
    return 0


if __name__ == "__main__":
    sys.exit(main())
