#!/usr/bin/env bash
set -euo pipefail

# Generates or updates appcast.xml after a release. Signs the DMG with Sparkle's
# EdDSA private key (from Keychain), inserts a new <item>, leaves the file ready
# to commit + push.
#
# Usage: ./scripts/update-appcast.sh <tag> [release-notes-html]
# Example: ./scripts/update-appcast.sh V2.1 'Fix audio merge on Apple Silicon.'

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="Video Downloader"
DMG_PATH="$ROOT_DIR/dist/$APP_NAME.dmg"
APPCAST_PATH="$ROOT_DIR/appcast.xml"
INFO_PLIST="$ROOT_DIR/Packaging/Info.plist"
SPARKLE_BIN="$ROOT_DIR/.build/artifacts/sparkle/Sparkle/bin"
GITHUB_REPO="Wes974/ytdl-front"

TAG="${1:-}"
NOTES="${2:-Mise a jour disponible.}"

if [[ -z "$TAG" ]]; then
  echo "Usage: $0 <tag> [release-notes-html]"
  exit 1
fi

if [[ ! -x "$SPARKLE_BIN/sign_update" ]]; then
  echo "Sparkle CLI not found at $SPARKLE_BIN. Run \`swift build\` first."
  exit 1
fi

if [[ ! -f "$DMG_PATH" ]]; then
  echo "DMG not found: $DMG_PATH (run release-dmg-notarized.sh first)"
  exit 1
fi

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$INFO_PLIST")"
BUILD="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$INFO_PLIST")"

# sign_update emits a single line: sparkle:edSignature="..." length="..."
SIGN_OUT="$("$SPARKLE_BIN/sign_update" "$DMG_PATH")"
ED_SIG="$(printf '%s' "$SIGN_OUT" | sed -nE 's/.*sparkle:edSignature="([^"]+)".*/\1/p')"
LENGTH="$(printf '%s' "$SIGN_OUT" | sed -nE 's/.*length="([^"]+)".*/\1/p')"

if [[ -z "$ED_SIG" || -z "$LENGTH" ]]; then
  echo "Could not parse sign_update output: $SIGN_OUT"
  exit 1
fi

PUB_DATE="$(date -u +'%a, %d %b %Y %H:%M:%S +0000')"

# GitHub rewrites spaces in asset filenames (e.g. "Video Downloader.dmg" becomes
# "Video.Downloader.dmg" in download URLs). Query the API for the authoritative
# URL instead of guessing the encoding.
DOWNLOAD_URL="$(gh release view "$TAG" --repo "$GITHUB_REPO" --json assets \
  --jq '.assets[] | select(.name | endswith(".dmg")) | .url' | head -1)"

if [[ -z "$DOWNLOAD_URL" ]]; then
  echo "Could not resolve DMG download URL from gh release view (release $TAG, repo $GITHUB_REPO)."
  exit 1
fi

# Pass the dynamic fields through env vars so XML special chars can't break injection.
export ITEM_TITLE="$APP_NAME $TAG"
export ITEM_PUB_DATE="$PUB_DATE"
export ITEM_VERSION="$BUILD"
export ITEM_SHORT="$VERSION"
export ITEM_NOTES="$NOTES"
export ITEM_URL="$DOWNLOAD_URL"
export ITEM_SIG="$ED_SIG"
export ITEM_LEN="$LENGTH"
export APPCAST_PATH
export APP_NAME

/usr/bin/python3 - <<'PY'
import os
import xml.sax.saxutils as su

path = os.environ["APPCAST_PATH"]
title = su.escape(os.environ["ITEM_TITLE"])
pub_date = su.escape(os.environ["ITEM_PUB_DATE"])
version = su.escape(os.environ["ITEM_VERSION"])
short = su.escape(os.environ["ITEM_SHORT"])
notes = os.environ["ITEM_NOTES"]
url = su.quoteattr(os.environ["ITEM_URL"])
sig = su.quoteattr(os.environ["ITEM_SIG"])
length = su.quoteattr(os.environ["ITEM_LEN"])

new_item = f"""        <item>
            <title>{title}</title>
            <pubDate>{pub_date}</pubDate>
            <sparkle:version>{version}</sparkle:version>
            <sparkle:shortVersionString>{short}</sparkle:shortVersionString>
            <sparkle:minimumSystemVersion>11.0</sparkle:minimumSystemVersion>
            <description><![CDATA[<p>{notes}</p>]]></description>
            <enclosure url={url} sparkle:edSignature={sig} length={length} type="application/octet-stream"/>
        </item>
"""

if not os.path.exists(path):
    app_name = su.escape(os.environ["APP_NAME"])
    content = f"""<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" xmlns:dc="http://purl.org/dc/elements/1.1/">
    <channel>
        <title>{app_name}</title>
{new_item}    </channel>
</rss>
"""
    with open(path, "w", encoding="utf-8") as f:
        f.write(content)
else:
    with open(path, encoding="utf-8") as f:
        content = f.read()

    # Insert immediately after the channel <title>.
    import re
    pattern = re.compile(r"(<channel>\s*<title>[^<]*</title>\s*)", re.DOTALL)
    m = pattern.search(content)
    if not m:
        raise SystemExit("Could not find <channel><title> in existing appcast.xml")
    content = content[:m.end()] + new_item + content[m.end():]
    with open(path, "w", encoding="utf-8") as f:
        f.write(content)
PY

echo "Updated $APPCAST_PATH for $TAG."
echo "Next: git add appcast.xml && git commit -m 'release: appcast for $TAG' && git push"
