#!/usr/bin/env python3
"""Write the Sparkle appcast for one release to stdout.

Usage: appcast.py <version> <build> <dmg-file-name> '<sign_update output>'

The feed lists only the newest release. It is attached to every GitHub
release, and SUFeedURL points at releases/latest/download/appcast.xml.
"""
import html
import re
import sys
from email.utils import formatdate
from pathlib import Path

REPO = "https://github.com/GedeonDrapak/hlas"
# Installers and the feed are served from hlas.dev (web/download/), so updates
# keep working when GitHub is unreachable.
DOWNLOADS = "https://hlas.dev/download"
ROOT = Path(__file__).resolve().parent.parent


def changelog_html(version: str) -> str:
    text = (ROOT / "CHANGELOG.md").read_text()
    match = re.search(rf"^## {re.escape(version)}\b.*?$(.*?)(?=^## |\Z)", text, re.S | re.M)
    if not match:
        sys.exit(f"CHANGELOG.md has no section for {version}")
    items = [line[2:].strip() for line in match.group(1).splitlines() if line.startswith("- ")]
    lis = "".join(f"<li>{html.escape(item).replace('`', '')}</li>" for item in items)
    return f"<ul>{lis}</ul>"


def main() -> None:
    version, build, dmg, signature = sys.argv[1:5]
    if not re.fullmatch(r'sparkle:edSignature="[^"]+" length="\d+"', signature.strip()):
        sys.exit(f"Unexpected sign_update output: {signature!r}")
    print(f"""<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>Hlas</title>
    <link>https://hlas.dev</link>
    <item>
      <title>Hlas {version}</title>
      <pubDate>{formatdate(usegmt=True)}</pubDate>
      <sparkle:version>{build}</sparkle:version>
      <sparkle:shortVersionString>{version}</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>15.0</sparkle:minimumSystemVersion>
      <description><![CDATA[{changelog_html(version)}]]></description>
      <enclosure url="{DOWNLOADS}/{dmg}" type="application/octet-stream" {signature.strip()}/>
    </item>
  </channel>
</rss>""")


if __name__ == "__main__":
    main()
