#!/bin/bash
# Checks build-dmg.sh's failure paths (HQ-472). Runs the real build twice into a scratch folder; slow (release build).
#  1. A step that fails after the attach (the first `hdiutil detach` fails, as when the volume is busy) leaves no
#     mounted image: `hdiutil info` no longer lists the read-write image.
#  2. With SetFile hidden from PATH, the build prints exactly one "build-dmg: warning:" line and still makes the DMG.
# Mounts only its own image, out of sight (-nobrowse); never touches other volumes. No window, no app launch.
# Usage: scripts/test-build-dmg.sh
set -uo pipefail
cd "$(dirname "$0")/.."
ROOT="$(pwd)"
RW_DMG="${ROOT}/.build/dmg/rw.dmg"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/resonance-dmg-test.XXXXXX")"
FAILS=0

pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*"; FAILS=$((FAILS + 1)); }

# Is our read-write image attached? (Matches this repo's image path only.)
our_image_attached() { hdiutil info | grep -F "image-path" | grep -qF "${RW_DMG}"; }

# Safety net: if the script under test leaves our image mounted, detach it here (only ours), so each run starts clean.
detach_ours() {
  if our_image_attached; then
    hdiutil info | awk -v img="${RW_DMG}" '
      /^image-path/ { mine = index($0, img) > 0 }
      mine && /^\/dev\/disk[0-9]+[ \t]/ { print $1; mine = 0 }' |
      while read -r dev; do hdiutil detach -force "${dev}" >/dev/null 2>&1; done
  fi
}
cleanup() { detach_ours; rm -rf "${TMP}"; }
trap cleanup EXIT

if our_image_attached; then
  echo "Our image is already attached before the test; detach it first: ${RW_DMG}" >&2
  exit 2
fi

# --- 1. Failure after the attach -----------------------------------------------------------------------------------
SHIM="${TMP}/shim"
mkdir -p "${SHIM}"
cat > "${SHIM}/hdiutil" << SHIMEOF
#!/bin/bash
# Fails the first detach (without detaching), passes everything else to the real hdiutil.
if [ "\${1:-}" = "detach" ] && [ ! -e "${TMP}/detach-failed" ]; then
  touch "${TMP}/detach-failed"
  echo "hdiutil: couldn't unmount (forced by test)" >&2
  exit 16
fi
exec /usr/bin/hdiutil "\$@"
SHIMEOF
chmod +x "${SHIM}/hdiutil"

PATH="${SHIM}:${PATH}" ./build-dmg.sh "${TMP}/out1" > "${TMP}/run1.out" 2> "${TMP}/run1.err"
status=$?
if [ "${status}" -eq 0 ]; then
  fail "build-dmg.sh succeeded although a step after the attach failed"
elif [ ! -e "${TMP}/detach-failed" ]; then
  fail "the forced failure never ran (the build stopped before the attach); see ${TMP}/run1.err"
  tail -n 20 "${TMP}/run1.err"
elif our_image_attached; then
  fail "the read-write image is still mounted after the failure (hdiutil info lists ${RW_DMG})"
else
  pass "a failure after the attach leaves no mounted image (hdiutil info)"
fi
detach_ours

# --- 2. SetFile hidden from PATH -------------------------------------------------------------------------------------
# Every PATH folder that holds SetFile is replaced by a mirror of it without SetFile.
NEWPATH=""
i=0
IFS=: read -r -a DIRS <<< "${PATH}"
for d in "${DIRS[@]}"; do
  if [ -n "${d}" ] && [ -e "${d}/SetFile" ]; then
    i=$((i + 1))
    m="${TMP}/mirror${i}"
    mkdir -p "${m}"
    for f in "${d}"/*; do
      [ "$(basename "${f}")" = "SetFile" ] || ln -s "${f}" "${m}/"
    done
    d="${m}"
  fi
  NEWPATH="${NEWPATH:+${NEWPATH}:}${d}"
done

if PATH="${NEWPATH}" command -v SetFile > /dev/null; then
  fail "could not hide SetFile from PATH"
else
  PATH="${NEWPATH}" ./build-dmg.sh "${TMP}/out2" > "${TMP}/run2.out" 2> "${TMP}/run2.err"
  status=$?
  warnings="$(grep -c '^build-dmg: warning:' "${TMP}/run2.err")"
  dmg="$(tail -n 1 "${TMP}/run2.out")"
  if [ "${status}" -ne 0 ]; then
    fail "build-dmg.sh failed without SetFile (exit ${status})"
    tail -n 20 "${TMP}/run2.err"
  elif [ ! -f "${dmg}" ]; then
    fail "no DMG was produced without SetFile"
  elif [ "${warnings}" -ne 1 ]; then
    fail "expected one 'build-dmg: warning:' line without SetFile, got ${warnings}"
  else
    pass "without SetFile: one warning line ($(grep '^build-dmg: warning:' "${TMP}/run2.err")), DMG produced"
  fi
  if our_image_attached; then fail "the read-write image is still mounted after the SetFile-less build"; fi
fi

[ "${FAILS}" -eq 0 ] && echo "All build-dmg checks passed." || echo "${FAILS} build-dmg check(s) failed."
exit $((FAILS > 0))
