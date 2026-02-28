#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BIN_DIR="$ROOT_DIR/Resources/Binaries"
TMP_DIR="$ROOT_DIR/.tmp-binaries"

mkdir -p "$BIN_DIR"
rm -rf "$TMP_DIR"
mkdir -p "$TMP_DIR"

echo "Fetching latest yt-dlp release metadata"
LATEST_TAG="$(curl -sL https://api.github.com/repos/yt-dlp/yt-dlp/releases/latest | /usr/bin/python3 -c 'import json,sys;print(json.load(sys.stdin)["tag_name"])')"

YTDLP_URL="https://github.com/yt-dlp/yt-dlp/releases/download/${LATEST_TAG}/yt-dlp_macos"
SUMS_URL="https://github.com/yt-dlp/yt-dlp/releases/download/${LATEST_TAG}/SHA2-256SUMS"

echo "Downloading yt-dlp_macos (${LATEST_TAG})"
curl -L "$YTDLP_URL" -o "$BIN_DIR/yt-dlp_macos"
curl -L "$SUMS_URL" -o "$TMP_DIR/SHA2-256SUMS"

EXPECTED_HASH="$(grep 'yt-dlp_macos$' "$TMP_DIR/SHA2-256SUMS" | awk '{print $1}')"
ACTUAL_HASH="$(shasum -a 256 "$BIN_DIR/yt-dlp_macos" | awk '{print $1}')"

if [[ "$EXPECTED_HASH" != "$ACTUAL_HASH" ]]; then
  echo "yt-dlp checksum mismatch"
  echo "Expected: $EXPECTED_HASH"
  echo "Actual:   $ACTUAL_HASH"
  exit 1
fi

chmod +x "$BIN_DIR/yt-dlp_macos"

echo "Downloading ffmpeg + ffprobe from evermeet"
curl -L "https://evermeet.cx/ffmpeg/getrelease/ffmpeg/zip" -o "$TMP_DIR/ffmpeg.zip"
curl -L "https://evermeet.cx/ffmpeg/getrelease/ffprobe/zip" -o "$TMP_DIR/ffprobe.zip"

unzip -o "$TMP_DIR/ffmpeg.zip" -d "$TMP_DIR/ffmpeg"
unzip -o "$TMP_DIR/ffprobe.zip" -d "$TMP_DIR/ffprobe"

cp "$TMP_DIR/ffmpeg/ffmpeg" "$BIN_DIR/ffmpeg"
cp "$TMP_DIR/ffprobe/ffprobe" "$BIN_DIR/ffprobe"

chmod +x "$BIN_DIR/ffmpeg" "$BIN_DIR/ffprobe"

echo "Binaries available in $BIN_DIR"
