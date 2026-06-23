#!/usr/bin/env bash
#
# Build SessionSweep and wrap the SPM executable into a real macOS .app
# bundle (Info.plist + bundle layout) so it gets a Dock icon, a window, and a
# menu bar. No Xcode required — only Command Line Tools (swift + codesign).
#
# Usage:  scripts/build-app.sh [release|debug]   (default: release)
set -euo pipefail

cd "$(dirname "$0")/.."

CONFIG="${1:-release}"
APP_NAME="SessionSweep"            # SPM target/executable name
BUNDLE_ID="com.local.sessionsweep"
DISPLAY_NAME="SessionSweep"        # product name shown in Finder/Dock
VERSION="0.1.0"                    # marketing version (CFBundleShortVersionString)
BUILD="202606"                     # build number (CFBundleVersion), YYYYMM

echo "==> swift build ($CONFIG)"
swift build -c "$CONFIG"

BIN_PATH="$(swift build -c "$CONFIG" --show-bin-path)"
APP_DIR="build/${APP_NAME}.app"
MACOS_DIR="${APP_DIR}/Contents/MacOS"
RES_DIR="${APP_DIR}/Contents/Resources"

echo "==> assembling ${APP_DIR}"
rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RES_DIR"
cp "${BIN_PATH}/${APP_NAME}" "${MACOS_DIR}/${APP_NAME}"

# Keep Spotlight from indexing the build output, so the dev .app here never
# shows up alongside the installed copy in /Applications (Launchpad/search).
touch build/.metadata_never_index

echo "==> generating app icon"
# Render the 1024px PNG (only if missing) and build a multi-size .icns.
ICON_PNG="build/icon-1024.png"
[ -f "$ICON_PNG" ] || swift scripts/make-icon.swift "$ICON_PNG"
scripts/make-icns.sh "$ICON_PNG" "${RES_DIR}/AppIcon.icns"

cat > "${APP_DIR}/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>            <string>${APP_NAME}</string>
    <key>CFBundleDisplayName</key>     <string>${DISPLAY_NAME}</string>
    <key>CFBundleIdentifier</key>      <string>${BUNDLE_ID}</string>
    <key>CFBundleVersion</key>         <string>${BUILD}</string>
    <key>CFBundleShortVersionString</key> <string>${VERSION}</string>
    <key>CFBundleExecutable</key>      <string>${APP_NAME}</string>
    <key>CFBundleIconFile</key>        <string>AppIcon</string>
    <key>CFBundlePackageType</key>     <string>APPL</string>
    <key>LSMinimumSystemVersion</key>  <string>14.0</string>
    <key>NSHighResolutionCapable</key> <true/>
    <!-- Regular app: shows in Dock and owns a menu bar. -->
    <key>LSUIElement</key>             <false/>
</dict>
</plist>
PLIST

echo "==> ad-hoc code signing"
# Ad-hoc signature (-) is enough to run locally without notarization.
codesign --force --deep --sign - "$APP_DIR"

echo "==> done: ${APP_DIR}"
echo "    open it with:  open '${APP_DIR}'"
