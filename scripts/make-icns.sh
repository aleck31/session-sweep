#!/usr/bin/env bash
#
# Build AppIcon.icns from a 1024x1024 PNG using only system tools
# (sips + iconutil) — no Xcode required.
#
# Usage:  scripts/make-icns.sh <src-1024.png> <out.icns>
set -euo pipefail

SRC="${1:?source png required}"
OUT="${2:?output icns path required}"

WORK="$(mktemp -d)/AppIcon.iconset"
mkdir -p "$WORK"

# macOS iconset expects these exact names/sizes (1x and 2x for each).
gen() { sips -z "$1" "$1" "$SRC" --out "$WORK/$2" >/dev/null; }
gen 16    icon_16x16.png
gen 32    icon_16x16@2x.png
gen 32    icon_32x32.png
gen 64    icon_32x32@2x.png
gen 128   icon_128x128.png
gen 256   icon_128x128@2x.png
gen 256   icon_256x256.png
gen 512   icon_256x256@2x.png
gen 512   icon_512x512.png
gen 1024  icon_512x512@2x.png

iconutil -c icns "$WORK" -o "$OUT"
echo "wrote $OUT"
