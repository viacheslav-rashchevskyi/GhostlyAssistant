#!/bin/bash
# Builds the styled installer: build/release/GhostlyAssistant-<version>.dmg
# Needs dmgbuild (pip install dmgbuild) and a built Release app.
set -euo pipefail
cd "$(dirname "$0")/.."

APP=build/Build/Products/Release/GhostlyAssistant.app
[ -d "$APP" ] || { echo "error: build the Release app first ($APP)"; exit 1; }
command -v dmgbuild >/dev/null || { echo "error: dmgbuild not found — pip install dmgbuild"; exit 1; }

VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP/Contents/Info.plist")
OUT=build/release/GhostlyAssistant-$VERSION.dmg
mkdir -p build/release
rm -f "$OUT"

dmgbuild -s assets/dmg/settings.py -D app="$APP" -D background=assets/dmg/background.tiff "GhostlyAssistant" "$OUT"
codesign --sign "Apple Development" --timestamp=none "$OUT"
hdiutil verify "$OUT" >/dev/null

echo "$OUT"
shasum -a 256 "$OUT"
