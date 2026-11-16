#!/bin/bash
# Packages Resonance 2.0 into a DMG: the app, an Applications link and a short README.
# The app is built by scripts/build-app.sh (the one build path, HQ-435). No driver, no Audio MIDI Setup.
# Usage: ./build-dmg.sh [output-dir]   (default: ~/Desktop). Prints the DMG path on the last line.
set -euo pipefail
cd "$(dirname "$0")"

OUT_DIR="${1:-$HOME/Desktop}"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Resources/Info.plist)"
WORK_DIR=".build/dmg"
STAGING="${WORK_DIR}/staging"
DMG_PATH="${OUT_DIR}/Resonance-${VERSION}.dmg"

rm -rf "${WORK_DIR}"
mkdir -p "${STAGING}" "${OUT_DIR}"

APP_PATH="$(scripts/build-app.sh "${WORK_DIR}" | tail -n 1)"
cp -R "${APP_PATH}" "${STAGING}/"
ln -s /Applications "${STAGING}/Applications"

cat > "${STAGING}/README.txt" << 'README'
Resonance 2.0 (macOS 14.4 or later)

1. Drag Resonance.app to Applications and open it.
2. Allow audio recording when macOS asks (once).
3. Turn it on from the menu bar icon.

If macOS says the app is damaged or can't be opened: right-click it, choose Open, then Open again.
README

rm -f "${DMG_PATH}"
hdiutil create -volname "Resonance" -srcfolder "${STAGING}" -ov -format UDZO "${DMG_PATH}" >&2
rm -rf "${WORK_DIR}"

echo "${DMG_PATH}"
