#!/bin/zsh
# Builds a DMG signed with the Apple Development identity (team 74N9VPV9D6).
#
# This is NOT notarized - Gatekeeper will warn on first launch and users must
# approve the app in System Settings > Privacy & Security. Use tools/release.sh
# instead once a Developer ID Application certificate exists.
#
# Why the dev cert and not ad-hoc: the signature is stable across builds, so a
# user's Accessibility and Microphone grants survive app updates. Ad-hoc signing
# changes the CDHash every build and silently resets both.
set -euo pipefail

ROOT="${0:A:h:h}"
APP="$ROOT/.xcbuild/Build/Products/Release/Hlas.app"
DIST_DIR="$ROOT/dist"

cd "$ROOT"
swift test
xcodegen generate
xcodebuild -project Hlas.xcodeproj -scheme Hlas -configuration Release \
  -derivedDataPath .xcbuild -allowProvisioningUpdates build | grep -E "error|SUCCEEDED|FAILED"

codesign -vvv --strict "$APP"

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")"
DMG="$DIST_DIR/Hlas-$VERSION-arm64.dmg"
STAGING="$(mktemp -d "${TMPDIR:-/tmp}/hlas-unsigned.XXXXXX")"
trap 'rm -rf "$STAGING"' EXIT

mkdir -p "$DIST_DIR"
ditto "$APP" "$STAGING/Hlas.app"
ln -s /Applications "$STAGING/Applications"
cp "$ROOT/docs/FIRST-RUN.txt" "$STAGING/READ ME FIRST.txt"
rm -f "$DMG"
hdiutil create -volname Hlas -srcfolder "$STAGING" -ov -format UDZO "$DMG"

print "Ready: $DMG"
print "Not notarized - users must approve it in System Settings > Privacy & Security."
