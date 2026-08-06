#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h}"
BUILD_DIR="$ROOT/.release"
APP="$BUILD_DIR/Build/Products/Distribution/Hlas.app"
DIST_DIR="$ROOT/dist"
NOTARY_PROFILE="${NOTARY_PROFILE:-HlasNotary}"
IDENTITY="${DEVELOPER_ID_IDENTITY:-Developer ID Application}"

if ! security find-identity -v -p codesigning | grep -Fq 'Developer ID Application:'; then
  print -u2 'No Developer ID Application certificate found. Create one in Apple Developer first.'
  exit 1
fi

if ! xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null 2>&1; then
  print -u2 "Notary credentials '$NOTARY_PROFILE' are missing."
  print -u2 'Store them with: xcrun notarytool store-credentials HlasNotary --apple-id <email> --team-id <team-id>'
  exit 1
fi

cd "$ROOT"
xcodegen generate
xcodebuild -project Hlas.xcodeproj -scheme Hlas -configuration Distribution \
  -derivedDataPath "$BUILD_DIR" -destination 'platform=macOS,arch=arm64' build

codesign -vvv --strict "$APP"
codesign -d --entitlements :- "$APP" 2>&1 | grep -Fq 'com.apple.security.device.audio-input'
codesign -dvvv "$APP" 2>&1 | grep -Fq 'Runtime Version'

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")"
DMG="$DIST_DIR/Hlas-$VERSION-arm64.dmg"
STAGING="$(mktemp -d "${TMPDIR:-/tmp}/hlas-release.XXXXXX")"
trap 'rm -rf "$STAGING"' EXIT

mkdir -p "$DIST_DIR"
ditto "$APP" "$STAGING/Hlas.app"
ln -s /Applications "$STAGING/Applications"
rm -f "$DMG"
hdiutil create -volname Hlas -srcfolder "$STAGING" -ov -format UDZO "$DMG"
codesign --force --sign "$IDENTITY" --timestamp "$DMG"
xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple "$DMG"
xcrun stapler validate "$DMG"
spctl --assess --type open --context context:primary-signature -vv "$DMG"

print "Ready: $DMG"
