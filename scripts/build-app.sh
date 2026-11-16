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

cat > "${APP_DIR}/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>Resonance</string>
    <key>CFBundleDisplayName</key>
    <string>Resonance</string>
    <key>CFBundleIdentifier</key>
    <string>com.resonance.app</string>
    <key>CFBundleVersion</key>
    <string>2.0.0</string>
    <key>CFBundleShortVersionString</key>
    <string>2.0</string>
    <key>CFBundleExecutable</key>
    <string>Resonance</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.4</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSAudioCaptureUsageDescription</key>
    <string>Resonance retunes the audio your Mac plays, so it needs to capture that audio.</string>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
</dict>
</plist>
PLIST

# A bundle with no sealed resource can show as "damaged"; one resource plus an ad-hoc signature of the whole
# bundle avoids that.
echo "Resonance Resources" > "${APP_DIR}/Contents/Resources/Resonance.txt"
xattr -cr "${APP_DIR}" || true
codesign --force --deep --sign - "${APP_DIR}" >&2
codesign --verify --deep --strict "${APP_DIR}" >&2

echo "$(cd "${OUT_DIR}" && pwd)/Resonance.app"
