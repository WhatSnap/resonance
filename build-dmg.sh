#!/bin/bash
#═══════════════════════════════════════════════════════════════
# Resonance Build & Package Script v2
# Creates Resonance-1.0.dmg with bundled BlackHole installer
#═══════════════════════════════════════════════════════════════

set -euo pipefail

echo "🔧 Building Resonance..."

# Variables
APP_NAME="Resonance"
VERSION="1.0"
DESKTOP_PATH="$HOME/Desktop"
APP_DIR="${DESKTOP_PATH}/${APP_NAME}.app"
DMG_PATH="${DESKTOP_PATH}/${APP_NAME}-${VERSION}.dmg"
DMG_STAGING="${DESKTOP_PATH}/${APP_NAME}-DMG-Staging"
BLACKHOLE_PKG_URL="https://existential.audio/downloads/BlackHole2ch-0.6.1.pkg"
BLACKHOLE_PKG_SHA256="c829afa041a9f6e1b369c01953c8f079740dd1f02421109855829edc0d3c1988"
BLACKHOLE_PKG_FILENAME="BlackHole2ch-0.6.1.pkg"

# Steps 1-2: build and sign the app bundle (scripts/build-app.sh holds the Info.plist and signing).
echo "📦 Building app bundle..."
"$(dirname "$0")/scripts/build-app.sh" "${DESKTOP_PATH}" >/dev/null

# Step 3: Download BlackHole
echo "⬇️ Downloading BlackHole audio driver..."
BLACKHOLE_PKG="${DESKTOP_PATH}/${BLACKHOLE_PKG_FILENAME}"

sha256_file() {
    shasum -a 256 "$1" | awk '{print $1}'
}

download_blackhole() {
    local dest="$1"
    curl -fL \
        --retry 5 \
        --retry-connrefused \
        --connect-timeout 10 \
        --max-time 180 \
        "${BLACKHOLE_PKG_URL}" \
        -o "${dest}"
}

needs_download=true
if [ -f "${BLACKHOLE_PKG}" ]; then
    if [ ! -s "${BLACKHOLE_PKG}" ]; then
        echo "⚠️  Existing BlackHole pkg is 0 bytes; re-downloading..."
    else
        existing_sha="$(sha256_file "${BLACKHOLE_PKG}")"
        if [ "${existing_sha}" = "${BLACKHOLE_PKG_SHA256}" ]; then
            needs_download=false
            echo "✅ BlackHole pkg already present and verified."
        else
            echo "⚠️  Existing BlackHole pkg sha256 mismatch; re-downloading..."
            echo "    expected: ${BLACKHOLE_PKG_SHA256}"
            echo "    found:    ${existing_sha}"
        fi
    fi
fi

if [ "${needs_download}" = true ]; then
    echo "    Source: ${BLACKHOLE_PKG_URL}"
    download_blackhole "${BLACKHOLE_PKG}"
    if [ ! -s "${BLACKHOLE_PKG}" ]; then
        echo "❌ Download failed (0 bytes): ${BLACKHOLE_PKG}"
        exit 1
    fi
    downloaded_sha="$(sha256_file "${BLACKHOLE_PKG}")"
    if [ "${downloaded_sha}" != "${BLACKHOLE_PKG_SHA256}" ]; then
        echo "❌ Downloaded BlackHole pkg sha256 mismatch."
        echo "    expected: ${BLACKHOLE_PKG_SHA256}"
        echo "    found:    ${downloaded_sha}"
        echo "    file:     ${BLACKHOLE_PKG}"
        exit 1
    fi
    echo "✅ Downloaded and verified BlackHole pkg."
fi

# Step 4: Create DMG staging
echo "💿 Creating DMG..."
rm -rf "${DMG_STAGING}"
mkdir -p "${DMG_STAGING}"

# Copy app
cp -R "${APP_DIR}" "${DMG_STAGING}/"

# Copy BlackHole installer
cp "${BLACKHOLE_PKG}" "${DMG_STAGING}/Install BlackHole Audio Driver.pkg"

# Applications symlink
ln -s /Applications "${DMG_STAGING}/Applications"

# Create comprehensive README
cat > "${DMG_STAGING}/README - START HERE.txt" << 'README'
════════════════════════════════════════════════════════════════
   RESONANCE - 432Hz Audio Converter
   Installation Guide
════════════════════════════════════════════════════════════════

STEP 1: Install Audio Driver (Required - First Time Only)
─────────────────────────────────────────────────────────────────
Double-click "Install BlackHole Audio Driver.pkg" and follow
the prompts. This installs a virtual audio device that allows
Resonance to capture and process your system audio.

   → You may need to enter your password
   → Restart your Mac after installation


STEP 2: Install Resonance App
─────────────────────────────────────────────────────────────────
Drag "Resonance.app" to the Applications folder.


STEP 3: Configure Audio (First Time Only)
─────────────────────────────────────────────────────────────────
1. Open "Audio MIDI Setup" (search in Spotlight)
2. Click the "+" button at bottom left
3. Select "Create Multi-Output Device"
4. Check ONLY:
   ☑ BlackHole 2ch
5. Right-click the Multi-Output Device → "Use This Device for Sound Output"
   (Or simply select "BlackHole 2ch" directly in System Settings → Sound)


STEP 4: Use Resonance
─────────────────────────────────────────────────────────────────
1. Open Resonance from Applications
2. Click the waveform icon in your menu bar
3. Select "BlackHole 2ch" as the input device
4. Click "Enable"
5. Play any audio - it will now be converted to 432Hz!


TROUBLESHOOTING
─────────────────────────────────────────────────────────────────
• "BlackHole not found" error
  → Make sure you installed the BlackHole driver (Step 1)
  → Restart your Mac after installing

• No audio output
  → Check that Multi-Output Device (or BlackHole 2ch) is set as system output
  → Ensure Resonance is "Enabled" in the menu bar

• App won't open
  → If macOS says “Resonance is damaged and can’t be opened”:
     1) Open Terminal
     2) Run:
        xattr -dr com.apple.quarantine /Applications/Resonance.app
     3) Try opening Resonance again
  → Otherwise: Right-click the app → Open → Click "Open" in the dialog


ABOUT 432Hz
─────────────────────────────────────────────────────────────────
432Hz is considered the natural frequency of the universe.
Converting audio from standard 440Hz tuning to 432Hz creates
a more harmonious, relaxing listening experience aligned with
sacred geometry and natural vibration.

════════════════════════════════════════════════════════════════
   Return to the original harmony. 🌀
════════════════════════════════════════════════════════════════
README

# Create DMG
rm -f "${DMG_PATH}"
hdiutil create -volname "Resonance" \
    -srcfolder "${DMG_STAGING}" \
    -ov -format UDZO \
    "${DMG_PATH}"

# Cleanup
rm -rf "${DMG_STAGING}"

echo ""
echo "✅ Build complete!"
echo ""
echo "📍 DMG location: ${DMG_PATH}"
echo ""
echo "DMG contains:"
echo "   • Resonance.app"
echo "   • Install BlackHole Audio Driver.pkg"
echo "   • README - START HERE.txt"
echo ""
