#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h}"
BUILD_DIR="$ROOT/.release"
APP="$BUILD_DIR/Build/Products/Distribution/Hlas.app"
DIST_DIR="$ROOT/dist"
NOTARY_PROFILE="${NOTARY_PROFILE:-EdenNotary}"
IDENTITY="${DEVELOPER_ID_IDENTITY:-Developer ID Application}"

CERT_LINE="$(security find-identity -v -p codesigning | grep -F 'Developer ID Application:' | head -1 || true)"
if [[ -z "$CERT_LINE" ]]; then
  print -u2 'No Developer ID Application certificate found. Create one in Apple Developer first.'
  print -u2 'It lives on the Eden Makers account (tech@edenmakers.ai) and only its Account Holder can issue it.'
  exit 1
fi

# The Developer ID cert belongs to the Eden Makers team, while project.yml
# carries the personal Apple Development team for the Release configuration.
# Read the distribution team off the cert instead of hardcoding it twice - one
# of the two copies would inevitably go stale.
DISTRIBUTION_TEAM="${DEVELOPER_ID_TEAM:-${${CERT_LINE##*\(}%\)*}}"
if [[ ! "$DISTRIBUTION_TEAM" =~ '^[A-Z0-9]{10}$' ]]; then
  print -u2 "Could not read a team id from the certificate: $CERT_LINE"
  print -u2 'Set DEVELOPER_ID_TEAM=<team-id> to override.'
  exit 1
fi

if ! xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null 2>&1; then
  print -u2 "Notary credentials '$NOTARY_PROFILE' are missing."
  print -u2 "Store them with: xcrun notarytool store-credentials $NOTARY_PROFILE --apple-id tech@edenmakers.ai --team-id $DISTRIBUTION_TEAM"
  exit 1
fi

cd "$ROOT"
swift test
xcodegen generate
xcodebuild -project Hlas.xcodeproj -scheme Hlas -configuration Distribution \
  -derivedDataPath "$BUILD_DIR" -destination 'platform=macOS,arch=arm64' \
  DEVELOPMENT_TEAM="$DISTRIBUTION_TEAM" build

codesign -vvv --strict "$APP"
# Capture first: `codesign | grep -q` exits 141 under pipefail when grep stops
# reading early.
ENTITLEMENTS="$(codesign -d --entitlements :- "$APP" 2>&1)"
SIGNATURE="$(codesign -dvvv "$APP" 2>&1)"
if [[ "$ENTITLEMENTS" != *com.apple.security.device.audio-input* ]]; then
  print -u2 'The built app is missing the microphone entitlement.'
  exit 1
fi

# Xcode injects com.apple.security.get-task-allow unless
# CODE_SIGN_INJECT_BASE_ENTITLEMENTS is off. It lets a debugger attach to the
# shipped app and notarization rejects it, so catch it here rather than three
# minutes into an upload.
if [[ "$ENTITLEMENTS" == *get-task-allow* ]]; then
  print -u2 'The built app carries com.apple.security.get-task-allow.'
  print -u2 'Set CODE_SIGN_INJECT_BASE_ENTITLEMENTS: NO on the Distribution config in project.yml.'
  exit 1
fi
if [[ "$SIGNATURE" != *"Runtime Version"* ]]; then
  print -u2 'The built app is not signed with the Hardened Runtime.'
  exit 1
fi

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
