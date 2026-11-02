#!/bin/bash
# Publishes the update feed for the release just built. Signs build/release/GhostlyAssistant-<version>.dmg with the
# Sparkle EdDSA key from the login Keychain, embeds the "What's changed" part of the release notes, writes
# build/updates/appcast.xml and uploads both files to the GitHub release v<version>.
# Installed apps read https://github.com/<repo>/releases/latest/download/appcast.xml, so the feed goes live
# once that release is published and marked Latest.
#
# Usage: scripts/publish-update.sh [notes.md] [--no-upload]
#   notes.md     the release notes; by default the body of the GitHub release v<version> (create it first)
#   --no-upload  only write build/updates/appcast.xml
# Needs a Release app built with -derivedDataPath build (Sparkle's tools come from its packages) and the DMG.
set -euo pipefail
cd "$(dirname "$0")/.."

REPO=viacheslav-rashchevskyi/GhostlyAssistant
APP=build/Build/Products/Release/GhostlyAssistant.app
BIN=build/SourcePackages/artifacts/sparkle/Sparkle/bin
OUT=build/updates

NOTES_FILE=""
UPLOAD=1
for arg in "$@"; do
  case "$arg" in
    --no-upload) UPLOAD=0 ;;
    *) NOTES_FILE=$arg ;;
  esac
done

[ -d "$APP" ] || { echo "error: build the Release app first ($APP)"; exit 1; }
[ -x "$BIN/generate_appcast" ] || { echo "error: Sparkle tools not found in $BIN — build with -derivedDataPath build"; exit 1; }
VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP/Contents/Info.plist")
DMG=build/release/GhostlyAssistant-$VERSION.dmg
[ -f "$DMG" ] || { echo "error: make the DMG first (scripts/make-dmg.sh → $DMG)"; exit 1; }

if [ -n "$NOTES_FILE" ]; then
  NOTES=$(cat "$NOTES_FILE")
else
  NOTES=$(gh release view "v$VERSION" -R "$REPO" --json body -q .body)
fi
# The update window shows only "What's changed"; install steps and checksums are for people downloading the DMG.
CHANGES=$(printf '%s\n' "$NOTES" | awk '
  /^## / { if (found) exit; if (tolower($0) ~ /^## what.s changed/) { found = 1; next } }
  found { print }
')
[ -n "$(printf '%s' "$CHANGES" | tr -d '[:space:]')" ] || CHANGES=$NOTES

rm -rf "$OUT"
mkdir -p "$OUT"
cp "$DMG" "$OUT/"
printf '%s\n' "$CHANGES" > "$OUT/GhostlyAssistant-$VERSION.md"
"$BIN/generate_appcast" \
  --embed-release-notes \
  --maximum-deltas 0 \
  --download-url-prefix "https://github.com/$REPO/releases/download/v$VERSION/" \
  --link "https://github.com/$REPO/releases" \
  "$OUT"
echo "$OUT/appcast.xml"

if [ "$UPLOAD" = 1 ]; then
  # The DMG goes up again too: the signature in the feed is for these exact bytes.
  gh release upload "v$VERSION" "$DMG" "$OUT/appcast.xml" -R "$REPO" --clobber
  echo "$(basename "$DMG") and appcast.xml uploaded to release v$VERSION"
fi
