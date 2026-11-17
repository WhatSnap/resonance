#!/bin/bash
# Builds Resonance.app (release, ad-hoc signed) into a folder. Does not install, open or run it.
# Usage: scripts/build-app.sh [output-dir]   (default: .build/app)
# Prints the .app path on the last line.
set -euo pipefail
cd "$(dirname "$0")/.."

OUT_DIR="${1:-.build/app}"
APP_DIR="${OUT_DIR}/Resonance.app"

swift build -c release --product Resonance >&2

rm -rf "${APP_DIR}"
mkdir -p "${APP_DIR}/Contents/MacOS" "${APP_DIR}/Contents/Resources"
cp ".build/release/Resonance" "${APP_DIR}/Contents/MacOS/Resonance"
chmod +x "${APP_DIR}/Contents/MacOS/Resonance"

# The one Info.plist (HQ-435): Resources/Info.plist.
cp "Resources/Info.plist" "${APP_DIR}/Contents/Info.plist"
plutil -lint "${APP_DIR}/Contents/Info.plist" >&2

# The app icon (HQ-463), rendered by scripts/render-icon.py; Info.plist names it (CFBundleIconFile).
cp "Resources/AppIcon.icns" "${APP_DIR}/Contents/Resources/AppIcon.icns"

# A bundle with no sealed resource can show as "damaged"; AppIcon.icns is that resource, and the ad-hoc signature
# covers the whole bundle.
xattr -cr "${APP_DIR}" || true
codesign --force --deep --sign - "${APP_DIR}" >&2
codesign --verify --deep --strict "${APP_DIR}" >&2

echo "$(cd "${OUT_DIR}" && pwd)/Resonance.app"
