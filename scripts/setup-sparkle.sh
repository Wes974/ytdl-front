#!/usr/bin/env bash
set -euo pipefail

# One-time setup: generates the Sparkle EdDSA signing keypair (private key stays in
# the macOS Keychain, public key is patched into Packaging/Info.plist).
#
# Run this once per developer machine. After the first run, re-running just prints
# the existing public key — it does NOT regenerate.
#
# Requires: `swift build` to have populated .build/artifacts/sparkle/Sparkle/bin/.

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SPARKLE_BIN="$ROOT_DIR/.build/artifacts/sparkle/Sparkle/bin/generate_keys"
INFO_PLIST="$ROOT_DIR/Packaging/Info.plist"

if [[ ! -x "$SPARKLE_BIN" ]]; then
  echo "Sparkle CLI not found at $SPARKLE_BIN"
  echo "Run \`swift build\` first to populate the SPM artifacts cache."
  exit 1
fi

# First call (no args) generates the key if missing; on existing keys this is a no-op
# that prints the same Info.plist snippet. We discard its output.
"$SPARKLE_BIN" >/dev/null 2>&1 || true

# Then -p prints just the public key, suitable for capture.
PUBLIC_KEY="$("$SPARKLE_BIN" -p)"

if [[ -z "$PUBLIC_KEY" ]]; then
  echo "Failed to obtain public key from generate_keys."
  exit 1
fi

echo "Sparkle public key: $PUBLIC_KEY"

if grep -q "__SPARKLE_PUBLIC_ED_KEY__" "$INFO_PLIST"; then
  /usr/bin/sed -i '' "s|__SPARKLE_PUBLIC_ED_KEY__|$PUBLIC_KEY|" "$INFO_PLIST"
  echo "Patched Packaging/Info.plist with the public key."
  echo "Commit Packaging/Info.plist and push."
else
  CURRENT_KEY="$(/usr/libexec/PlistBuddy -c 'Print :SUPublicEDKey' "$INFO_PLIST" 2>/dev/null || true)"
  if [[ "$CURRENT_KEY" == "$PUBLIC_KEY" ]]; then
    echo "Packaging/Info.plist already contains this public key. Nothing to do."
  else
    echo "Packaging/Info.plist already has a different SUPublicEDKey ($CURRENT_KEY)."
    echo "Refusing to overwrite — rotate keys deliberately if this is intended."
    exit 1
  fi
fi
