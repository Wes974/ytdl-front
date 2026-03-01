#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="Video Downloader"
DMG_PATH="$ROOT_DIR/dist/$APP_NAME.dmg"

TAG=""
TITLE=""
NOTES_FILE=""
REPO=""
SKIP_NOTARIZE=0

usage() {
  cat <<'EOF'
Usage:
  scripts/publish-release.sh <tag> [options]

Examples:
  NOTARY_PROFILE=AC_PROFILE ./scripts/publish-release.sh V2
  ./scripts/publish-release.sh V2 --skip-notarize
  NOTARY_PROFILE=AC_PROFILE ./scripts/publish-release.sh V2.1 --title "Video Downloader V2.1"

Options:
  --title <title>          Release title (default: "Video Downloader <tag>")
  --notes-file <path>      Markdown file used as release notes
  --repo <owner/name>      Target repository (default: current repository)
  --skip-notarize          Skip build/sign/notarize step and only publish existing DMG
  -h, --help               Show this help

Notes:
  - Without --skip-notarize, NOTARY_PROFILE must be set.
  - The script will create or update the GitHub release.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help)
      usage
      exit 0
      ;;
    --title)
      TITLE="${2:-}"
      shift 2
      ;;
    --notes-file)
      NOTES_FILE="${2:-}"
      shift 2
      ;;
    --repo)
      REPO="${2:-}"
      shift 2
      ;;
    --skip-notarize)
      SKIP_NOTARIZE=1
      shift
      ;;
    --*)
      echo "Unknown option: $1" >&2
      usage
      exit 1
      ;;
    *)
      if [[ -z "$TAG" ]]; then
        TAG="$1"
      else
        echo "Unexpected argument: $1" >&2
        usage
        exit 1
      fi
      shift
      ;;
  esac
done

if [[ -z "$TAG" ]]; then
  echo "Missing required argument: <tag>" >&2
  usage
  exit 1
fi

if ! command -v gh >/dev/null 2>&1; then
  echo "GitHub CLI not found. Install gh first." >&2
  exit 1
fi

if [[ -z "$TITLE" ]]; then
  TITLE="$APP_NAME $TAG"
fi

repo_args=()
if [[ -n "$REPO" ]]; then
  repo_args=(--repo "$REPO")
fi

if [[ "$SKIP_NOTARIZE" -eq 0 ]]; then
  if [[ -z "${NOTARY_PROFILE:-}" ]]; then
    echo "NOTARY_PROFILE is required unless --skip-notarize is used." >&2
    exit 1
  fi

  "$ROOT_DIR/scripts/release-dmg-notarized.sh"
fi

if [[ ! -f "$DMG_PATH" ]]; then
  echo "DMG not found: $DMG_PATH" >&2
  exit 1
fi

cleanup_file=""
effective_notes_file="$NOTES_FILE"

if [[ -z "$effective_notes_file" ]]; then
  cleanup_file="$(mktemp)"
  effective_notes_file="$cleanup_file"
  cat > "$effective_notes_file" <<EOF
## Summary
- Release $TAG of $APP_NAME for macOS 11+
- Universal build (Intel + Apple Silicon)
- DMG signed, notarized, and stapled

## Installation
1. Open the DMG
2. Drag "$APP_NAME" to Applications
3. Launch the app from Applications
EOF
fi

if [[ ! -f "$effective_notes_file" ]]; then
  echo "Notes file not found: $effective_notes_file" >&2
  exit 1
fi

trap '[[ -n "$cleanup_file" ]] && rm -f "$cleanup_file"' EXIT

asset_spec="$DMG_PATH#$APP_NAME.dmg"

if gh release view "$TAG" "${repo_args[@]}" >/dev/null 2>&1; then
  gh release upload "$TAG" "$asset_spec" --clobber "${repo_args[@]}"
  gh release edit "$TAG" --title "$TITLE" --notes-file "$effective_notes_file" "${repo_args[@]}"
else
  gh release create "$TAG" "$asset_spec" --title "$TITLE" --notes-file "$effective_notes_file" "${repo_args[@]}"
fi

release_url="$(gh release view "$TAG" --json url --jq .url "${repo_args[@]}")"
echo "Release published: $release_url"
