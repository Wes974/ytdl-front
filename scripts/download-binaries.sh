#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BIN_DIR="$ROOT_DIR/Resources/Binaries"
TMP_DIR="$ROOT_DIR/.tmp-binaries"

mkdir -p "$BIN_DIR"
rm -rf "$TMP_DIR"
mkdir -p "$TMP_DIR"

echo "Fetching latest yt-dlp release metadata"
LATEST_TAG="$(curl -sL --retry 3 --retry-delay 2 https://api.github.com/repos/yt-dlp/yt-dlp/releases/latest | /usr/bin/python3 -c 'import json,sys;print(json.load(sys.stdin)["tag_name"])')"

YTDLP_URL="https://github.com/yt-dlp/yt-dlp/releases/download/${LATEST_TAG}/yt-dlp_macos"
SUMS_URL="https://github.com/yt-dlp/yt-dlp/releases/download/${LATEST_TAG}/SHA2-256SUMS"

echo "Downloading yt-dlp_macos (${LATEST_TAG})"
curl -fL --retry 3 --retry-delay 2 "$YTDLP_URL" -o "$BIN_DIR/yt-dlp_macos"
curl -fL --retry 3 --retry-delay 2 "$SUMS_URL" -o "$TMP_DIR/SHA2-256SUMS"

EXPECTED_HASH="$(grep 'yt-dlp_macos$' "$TMP_DIR/SHA2-256SUMS" | awk '{print $1}')"
ACTUAL_HASH="$(shasum -a 256 "$BIN_DIR/yt-dlp_macos" | awk '{print $1}')"

if [[ "$EXPECTED_HASH" != "$ACTUAL_HASH" ]]; then
  echo "yt-dlp checksum mismatch"
  echo "Expected: $EXPECTED_HASH"
  echo "Actual:   $ACTUAL_HASH"
  exit 1
fi

chmod +x "$BIN_DIR/yt-dlp_macos"

# Pinned arm64 ffmpeg/ffprobe from osxexperts.net (Tessus, same maintainer as evermeet).
# evermeet does not publish arm64 builds; the DMG bundle ships universal binaries built via lipo.
# Bump version + SHA256s together when refreshing arm64 builds.
OSXEXPERTS_VERSION="81"
FFMPEG_ARM64_SHA256="9a08d61f9328e8164ba560ee7a79958e357307fcfeea6fe626b7d66cdc287028"
FFPROBE_ARM64_SHA256="aab17ac7379c1178aaf400c3ef36cdb67db0b75b1a23eeef2cb9f658be8844e6"

echo "Downloading ffmpeg + ffprobe (x86_64 from evermeet)"
curl -fL --retry 3 --retry-delay 2 "https://evermeet.cx/ffmpeg/getrelease/ffmpeg/zip" -o "$TMP_DIR/ffmpeg-x86_64.zip"
curl -fL --retry 3 --retry-delay 2 "https://evermeet.cx/ffmpeg/getrelease/ffprobe/zip" -o "$TMP_DIR/ffprobe-x86_64.zip"

echo "Downloading ffmpeg + ffprobe (arm64 from osxexperts ${OSXEXPERTS_VERSION})"
curl -fL --retry 3 --retry-delay 2 "https://www.osxexperts.net/ffmpeg${OSXEXPERTS_VERSION}arm.zip" -o "$TMP_DIR/ffmpeg-arm64.zip"
curl -fL --retry 3 --retry-delay 2 "https://www.osxexperts.net/ffprobe${OSXEXPERTS_VERSION}arm.zip" -o "$TMP_DIR/ffprobe-arm64.zip"

unzip -oq "$TMP_DIR/ffmpeg-x86_64.zip" -d "$TMP_DIR/ffmpeg-x86_64"
unzip -oq "$TMP_DIR/ffprobe-x86_64.zip" -d "$TMP_DIR/ffprobe-x86_64"
unzip -oq "$TMP_DIR/ffmpeg-arm64.zip" -d "$TMP_DIR/ffmpeg-arm64"
unzip -oq "$TMP_DIR/ffprobe-arm64.zip" -d "$TMP_DIR/ffprobe-arm64"

find_binary() {
  # Excludes __MACOSX metadata directories produced by macOS-zipped archives.
  find "$1" -type f -name "$2" -not -path '*/__MACOSX/*' 2>/dev/null | head -1
}

FFMPEG_X86="$(find_binary "$TMP_DIR/ffmpeg-x86_64" ffmpeg)"
FFMPEG_ARM="$(find_binary "$TMP_DIR/ffmpeg-arm64" ffmpeg)"
FFPROBE_X86="$(find_binary "$TMP_DIR/ffprobe-x86_64" ffprobe)"
FFPROBE_ARM="$(find_binary "$TMP_DIR/ffprobe-arm64" ffprobe)"

for pair in "ffmpeg x86_64:$FFMPEG_X86" "ffmpeg arm64:$FFMPEG_ARM" "ffprobe x86_64:$FFPROBE_X86" "ffprobe arm64:$FFPROBE_ARM"; do
  label="${pair%%:*}"
  path="${pair#*:}"
  if [[ -z "$path" || ! -f "$path" ]]; then
    echo "Missing extracted binary: $label"
    exit 1
  fi
done

verify_sha() {
  local file="$1"
  local expected="$2"
  local actual
  actual="$(shasum -a 256 "$file" | awk '{print $1}')"
  if [[ "$expected" != "$actual" ]]; then
    echo "Checksum mismatch for $file"
    echo "Expected: $expected"
    echo "Actual:   $actual"
    exit 1
  fi
}

# osxexperts.net publishes the SHA256 of the extracted binary (not the zip).
verify_sha "$FFMPEG_ARM" "$FFMPEG_ARM64_SHA256"
verify_sha "$FFPROBE_ARM" "$FFPROBE_ARM64_SHA256"

echo "Combining x86_64 + arm64 into universal binaries"
lipo -create "$FFMPEG_X86" "$FFMPEG_ARM" -output "$BIN_DIR/ffmpeg"
lipo -create "$FFPROBE_X86" "$FFPROBE_ARM" -output "$BIN_DIR/ffprobe"

chmod +x "$BIN_DIR/ffmpeg" "$BIN_DIR/ffprobe"

echo "Verifying universal architectures"
lipo -info "$BIN_DIR/ffmpeg"
lipo -info "$BIN_DIR/ffprobe"

echo "Binaries available in $BIN_DIR"
