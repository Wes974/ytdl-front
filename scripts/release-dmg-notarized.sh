#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="YTDLFront"
DIST_DIR="$ROOT_DIR/dist"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
DMG_PATH="$DIST_DIR/$APP_NAME.dmg"
STAGING_DIR="$DIST_DIR/dmg-staging"

SIGNING_IDENTITY="${SIGNING_IDENTITY:-Developer ID Application: Ouwéis Moolna (LT9VN8QXU9)}"
NOTARY_PROFILE="${NOTARY_PROFILE:-}"

if [[ -z "$NOTARY_PROFILE" ]]; then
  echo "NOTARY_PROFILE is required."
  echo "Example setup:"
  echo "  xcrun notarytool store-credentials \"AC_PROFILE\" --apple-id \"<apple-id>\" --team-id \"LT9VN8QXU9\" --password \"<app-password>\""
  echo "Then run:"
  echo "  NOTARY_PROFILE=AC_PROFILE ./scripts/release-dmg-notarized.sh"
  exit 1
fi

"$ROOT_DIR/scripts/build-universal-app.sh"

echo "Signing embedded binaries"
if [[ -d "$APP_BUNDLE/Contents/Resources/bin" ]]; then
  while IFS= read -r binary; do
    base_name="$(basename "$binary")"
    if [[ -f "$binary" && "$base_name" != ".keep" ]]; then
      codesign --force --timestamp --options runtime --sign "$SIGNING_IDENTITY" "$binary"
    fi
  done < <(find "$APP_BUNDLE/Contents/Resources/bin" -type f)
fi

echo "Signing app bundle"
codesign --force --timestamp --options runtime --sign "$SIGNING_IDENTITY" "$APP_BUNDLE"
codesign --verify --deep --strict --verbose=2 "$APP_BUNDLE"

echo "Creating DMG"
rm -rf "$STAGING_DIR"
mkdir -p "$STAGING_DIR"
cp -R "$APP_BUNDLE" "$STAGING_DIR/"
ln -s /Applications "$STAGING_DIR/Applications"

rm -f "$DMG_PATH"
hdiutil create -volname "$APP_NAME" -srcfolder "$STAGING_DIR" -ov -format UDZO "$DMG_PATH"

echo "Submitting DMG for notarization"
xcrun notarytool submit "$DMG_PATH" --keychain-profile "$NOTARY_PROFILE" --wait

echo "Stapling app and DMG"
xcrun stapler staple "$APP_BUNDLE"
xcrun stapler staple "$DMG_PATH"

echo "Release complete: $DMG_PATH"
