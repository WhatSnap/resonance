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

# The volume shows the app icon (HQ-463): .VolumeIcon.icns at the root, hidden; the root's custom-icon flag is set
# on a read-write image below, because hdiutil does not carry it over from the source folder.
cp "Resources/AppIcon.icns" "${STAGING}/.VolumeIcon.icns"
SetFile -a V "${STAGING}/.VolumeIcon.icns" 2>/dev/null || chflags hidden "${STAGING}/.VolumeIcon.icns"

cat > "${STAGING}/README.txt" << 'README'
Resonance 2.0 (macOS 14.4 or later)

1. Drag Resonance.app to Applications and open it.
2. The first time, macOS blocks it because it is not notarized: open
   System Settings > Privacy & Security, scroll down, click Open Anyway
   next to Resonance, and confirm.
3. Allow audio recording when macOS asks (once).
4. Turn it on from the menu bar icon.
README

rm -f "${DMG_PATH}"
RW_DMG="${WORK_DIR}/rw.dmg"
MOUNT="${WORK_DIR}/mnt"
hdiutil create -volname "Resonance" -srcfolder "${STAGING}" -ov -format UDRW "${RW_DMG}" >&2
mkdir -p "${MOUNT}"
# -nobrowse: mounted out of sight, no Finder window, no desktop icon.
hdiutil attach -nobrowse -noautoopen -mountpoint "${MOUNT}" "${RW_DMG}" >&2
SetFile -a C "${MOUNT}" 2>/dev/null || true
hdiutil detach "${MOUNT}" >&2
hdiutil convert "${RW_DMG}" -format UDZO -o "${DMG_PATH}" >&2
rm -rf "${WORK_DIR}"

echo "${DMG_PATH}"
