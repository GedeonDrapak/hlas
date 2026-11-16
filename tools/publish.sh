#!/bin/zsh
# Publishes one GitHub release for both apps from the files tools/release.sh
# left in dist/. Publishing triggers .github/workflows/windows.yml, which
# builds Hlas for Windows from the same tag and attaches its installer.
set -euo pipefail

ROOT="${0:A:h:h}"
cd "$ROOT"
VERSION="$(awk '/CFBundleShortVersionString:/ {print $2}' project.yml)"
WIN_VERSION="$(awk -F'"' '/^version = / {print $2; exit}' windows/Cargo.toml)"
if [[ "$VERSION" != "$WIN_VERSION" ]]; then
  print -u2 "macOS is $VERSION but windows/Cargo.toml is $WIN_VERSION. One version for both apps."
  exit 1
fi

DMG="dist/Hlas-$VERSION-arm64.dmg"
for f in "$DMG" "$DMG.sha256" dist/Hlas-mac-arm64.dmg dist/appcast.xml; do
  [[ -f "$f" ]] || { print -u2 "Missing $f. Run tools/release.sh first."; exit 1; }
done
grep -q "<sparkle:shortVersionString>$VERSION<" dist/appcast.xml || { print -u2 'dist/appcast.xml is for another version.'; exit 1; }

section() { awk -v v="$2" '$0 ~ "^## "v"( |$)" {on=1; next} /^## / {on=0} on' "$1"; }
NOTES="$(mktemp)"
trap 'rm -f "$NOTES"' EXIT
{
  print "## Download\n"
  print "| | |\n|---|---|"
  print "| **macOS** (Apple Silicon, macOS 15+) | [Hlas-mac-arm64.dmg](https://hlas.dev/download/Hlas-mac-arm64.dmg) |"
  print "| **Windows** (x64, 10 and 11) | [Hlas-windows-x64-setup.exe](https://hlas.dev/download/Hlas-windows-x64-setup.exe) (on hlas.dev a few minutes after publishing) |\n"
  print "## macOS\n"
  section CHANGELOG.md "$VERSION"
  WIN="$(section windows/CHANGELOG.md "$VERSION")"
  if [[ -n "$WIN" ]]; then print "\n## Windows\n"; print -r -- "$WIN"; fi
} > "$NOTES"

gh release create "v$VERSION" --target "$(git rev-parse HEAD)" --title "Hlas $VERSION" --notes-file "$NOTES" \
  "$DMG" "$DMG.sha256" dist/Hlas-mac-arm64.dmg dist/appcast.xml
print "Published v$VERSION. Windows files follow from GitHub Actions."
print "Once the Windows installer is attached, run tools/site-downloads.sh to put both installers and the update feeds on hlas.dev."
