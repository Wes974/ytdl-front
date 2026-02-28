#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_BUNDLE_NAME="Video Downloader"
DIST_DIR="$ROOT_DIR/dist"
APP_BUNDLE="$DIST_DIR/$APP_BUNDLE_NAME.app"
DMG_PATH="$DIST_DIR/$APP_BUNDLE_NAME.dmg"

if [[ ! -d "$APP_BUNDLE" ]]; then
  echo "Missing app bundle: $APP_BUNDLE"
  exit 1
fi

if [[ ! -f "$DMG_PATH" ]]; then
  echo "Missing DMG: $DMG_PATH"
  exit 1
fi

echo "[1/5] codesign verification"
codesign --verify --deep --strict --verbose=2 "$APP_BUNDLE"

echo "[2/5] app notarization ticket"
xcrun stapler validate "$APP_BUNDLE"

echo "[3/5] dmg notarization ticket"
xcrun stapler validate "$DMG_PATH"

echo "[4/5] Gatekeeper app check"
spctl -a -vv --type exec "$APP_BUNDLE"

echo "[5/5] Gatekeeper dmg check"
spctl -a -vv --type open "$DMG_PATH"

echo "Distribution artifacts look valid."
