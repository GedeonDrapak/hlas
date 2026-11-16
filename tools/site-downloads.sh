#!/bin/zsh
# Puts the installers and update feeds on hlas.dev (web/download/, not in git)
# and deploys the site. Downloads and updates then work without GitHub.
#
#   tools/site-downloads.sh                    Mac files from dist/, Windows installer
#                                              from the GitHub release of this version
#   tools/site-downloads.sh path/to/setup.exe  Windows installer from a local file
#
# Writes web/download/:
#   Hlas-mac-arm64.dmg, Hlas-<version>-arm64.dmg   Mac installer (the stable name
#                                                  is what the site links to)
#   appcast.xml                                    Sparkle feed for Mac updates
#   Hlas-windows-x64-setup.exe                     Windows installer
#   latest.json                                    version the Windows app compares with
set -euo pipefail

ROOT="${0:A:h:h}"
cd "$ROOT"
VERSION="$(awk '/CFBundleShortVersionString:/ {print $2}' project.yml)"
OUT=web/download
mkdir -p "$OUT"

DMG="dist/Hlas-$VERSION-arm64.dmg"
for f in "$DMG" dist/appcast.xml; do
  [[ -f "$f" ]] || { print -u2 "Missing $f. Run make release first."; exit 1; }
done
grep -q "<sparkle:shortVersionString>$VERSION<" dist/appcast.xml || { print -u2 'dist/appcast.xml is for another version.'; exit 1; }
grep -q 'url="https://hlas.dev/download/' dist/appcast.xml || { print -u2 'dist/appcast.xml points outside hlas.dev. Rebuild it with tools/appcast.py.'; exit 1; }
cp "$DMG" "$OUT/"
cp "$DMG" "$OUT/Hlas-mac-arm64.dmg"
cp dist/appcast.xml "$OUT/appcast.xml"

WIN="${1:-}"
if [[ -z "$WIN" ]]; then
  WIN="$(mktemp -d)/Hlas-windows-x64-setup.exe"
  gh release download "v$VERSION" -p Hlas-windows-x64-setup.exe -O "$WIN" \
    || { print -u2 "No Windows installer on the v$VERSION release yet. Pass a local file instead."; exit 1; }
fi
cp "$WIN" "$OUT/Hlas-windows-x64-setup.exe"
print -r -- "{\"version\": \"$VERSION\", \"page\": \"https://hlas.dev/#download\"}" > "$OUT/latest.json"

(cd web && node _src/build.mjs >/dev/null && ../cloud/node_modules/.bin/wrangler deploy)
for f in Hlas-mac-arm64.dmg appcast.xml Hlas-windows-x64-setup.exe latest.json; do
  code="$(curl -s -o /dev/null -w '%{http_code}' "https://hlas.dev/download/$f")"
  print "$code https://hlas.dev/download/$f"
done
