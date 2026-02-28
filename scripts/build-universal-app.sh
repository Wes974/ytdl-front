#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_EXECUTABLE="YTDLFront"
APP_BUNDLE_NAME="Video Downloader"
DIST_DIR="$ROOT_DIR/dist"
APP_BUNDLE="$DIST_DIR/$APP_BUNDLE_NAME.app"
ARM_BUILD="$ROOT_DIR/.build/arm64-apple-macosx/release/$APP_EXECUTABLE"
X86_BUILD="$ROOT_DIR/.build/x86_64-apple-macosx/release/$APP_EXECUTABLE"
UNIVERSAL_BUILD="$DIST_DIR/$APP_EXECUTABLE-universal"

mkdir -p "$DIST_DIR"

echo "[1/5] Build arm64"
swift build -c release --arch arm64 --package-path "$ROOT_DIR"

echo "[2/5] Build x86_64"
swift build -c release --arch x86_64 --package-path "$ROOT_DIR"

echo "[3/5] Create universal binary"
lipo -create "$ARM_BUILD" "$X86_BUILD" -output "$UNIVERSAL_BUILD"

echo "[4/5] Assemble .app bundle"
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources/bin"

cp "$UNIVERSAL_BUILD" "$APP_BUNDLE/Contents/MacOS/$APP_EXECUTABLE"
chmod +x "$APP_BUNDLE/Contents/MacOS/$APP_EXECUTABLE"

cp "$ROOT_DIR/Packaging/Info.plist" "$APP_BUNDLE/Contents/Info.plist"

if [[ -d "$ROOT_DIR/Resources/Binaries" ]]; then
  cp -R "$ROOT_DIR/Resources/Binaries/." "$APP_BUNDLE/Contents/Resources/bin/"
  if compgen -G "$APP_BUNDLE/Contents/Resources/bin/*" > /dev/null; then
    for candidate in "$APP_BUNDLE/Contents/Resources/bin/"*; do
      if [[ -f "$candidate" && "$(basename "$candidate")" != ".keep" ]]; then
        chmod +x "$candidate"
      fi
    done
  fi
fi

if [[ -f "$ROOT_DIR/Resources/THIRD_PARTY_LICENSES.md" ]]; then
  cp "$ROOT_DIR/Resources/THIRD_PARTY_LICENSES.md" "$APP_BUNDLE/Contents/Resources/THIRD_PARTY_LICENSES.md"
fi

if [[ -f "$ROOT_DIR/Resources/AppIcon.icns" ]]; then
  cp "$ROOT_DIR/Resources/AppIcon.icns" "$APP_BUNDLE/Contents/Resources/AppIcon.icns"
fi

echo "[5/5] Done"
echo "App bundle: $APP_BUNDLE"
