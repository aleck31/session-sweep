#!/usr/bin/env bash
#
# One-shot installer: build SessionSweep, package it into a .app, and install
# it to /Applications. Run from anywhere:
#
#     ./scripts/install.sh
#
# Pass --user to install into ~/Applications instead of /Applications (no sudo).
set -euo pipefail

cd "$(dirname "$0")/.."

APP_NAME="SessionSweep"
SRC_APP="build/${APP_NAME}.app"

# Choose install destination.
DEST_DIR="/Applications"
if [ "${1:-}" = "--user" ]; then
    DEST_DIR="${HOME}/Applications"
    mkdir -p "$DEST_DIR"
fi
DEST_APP="${DEST_DIR}/${APP_NAME}.app"

# 1. Build + package (delegates to the existing script — no duplicated logic).
echo "==> building ${APP_NAME}…"
./scripts/build-app.sh release

if [ ! -d "$SRC_APP" ]; then
    echo "error: build did not produce ${SRC_APP}" >&2
    exit 1
fi

# 2. If the app is running, quit it so the bundle can be replaced cleanly.
if pgrep -f "${APP_NAME}.app/Contents/MacOS/${APP_NAME}" >/dev/null 2>&1; then
    echo "==> quitting running ${APP_NAME}…"
    osascript -e "quit app \"${APP_NAME}\"" 2>/dev/null || pkill -f "MacOS/${APP_NAME}" || true
    sleep 1
fi

# 3. Install — replace any existing copy. Use sudo only if the dir isn't writable.
echo "==> installing to ${DEST_APP}…"
SUDO=""
if [ ! -w "$DEST_DIR" ]; then
    echo "    (${DEST_DIR} needs elevated permissions — you may be prompted)"
    SUDO="sudo"
fi
$SUDO rm -rf "$DEST_APP"
$SUDO cp -R "$SRC_APP" "$DEST_APP"

# 4. Refresh Launch Services + Dock so the new icon/version shows immediately.
echo "==> refreshing icon cache…"
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister \
    -f "$DEST_APP" >/dev/null 2>&1 || true
killall Dock >/dev/null 2>&1 || true

echo
echo "✅ Installed: ${DEST_APP}"
echo "   Launch from Spotlight/Launchpad, or:  open '${DEST_APP}'"
echo
echo "ℹ️  First launch on a machine that didn't build it may be blocked by"
echo "   Gatekeeper (ad-hoc signed, not notarized). If so: right-click the app"
echo "   → Open → confirm once."
