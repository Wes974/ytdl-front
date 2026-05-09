# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

Native macOS 11+ SwiftUI app ("Video Downloader") that drives `yt-dlp` + `ffmpeg` to download videos to MP4 from a queue of links. Distributed as a signed, notarized, stapled universal `.dmg`. UI strings are in French — preserve French copy when editing user-facing text.

## Common commands

```bash
# Run the app from source (dev loop)
swift run

# Refresh embedded binaries (yt-dlp_macos, ffmpeg, ffprobe) into Resources/Binaries/
# Verifies yt-dlp checksum against upstream SHA2-256SUMS.
./scripts/download-binaries.sh

# Universal (arm64 + x86_64) .app bundle → dist/Video Downloader.app
./scripts/build-universal-app.sh

# Full release: build-universal → codesign → DMG → notarize → staple
NOTARY_PROFILE=AC_PROFILE ./scripts/release-dmg-notarized.sh

# Sanity checks on the produced .app/.dmg (codesign, stapler, spctl)
./scripts/verify-distribution.sh

# One-shot publish to GitHub Release (rebuilds + notarizes by default)
NOTARY_PROFILE=AC_PROFILE ./scripts/publish-release.sh <tag>
./scripts/publish-release.sh <tag> --skip-notarize   # only re-upload existing DMG
```

There is no test target. `swift test` will do nothing meaningful.

```bash
# One-time Sparkle setup (per dev machine)
./scripts/setup-sparkle.sh

# Update appcast.xml after a release (called automatically by publish-release.sh)
./scripts/update-appcast.sh <tag> "release notes html"
```

## Architecture

`SwiftPM` executable target `YTDLFront` (`Sources/YTDLFront/`) — entry point `YTDLFrontApp.swift` → `ContentView` → `AppViewModel`. MVVM with three services injected into the view model:

- **`BinaryManager`** — locates/installs `yt-dlp`, `ffmpeg`, `ffprobe`. Resolution order: existing copy in `~/Library/Application Support/YTDLFront/bin/` → bundled binary in `.app/Contents/Resources/bin/` (or `Resources/...` for `swift run`) → network fallback (yt-dlp from GitHub releases, ffmpeg/ffprobe from evermeet.cx). Always chmods to `0o755`.
- **`UpdateService`** — yt-dlp "notify then install" flow. Auto-checks at most every 24h (`shouldCheckAutomatically`), gated by user action for actual install. Downloads new binary, verifies against `SHA2-256SUMS` from the release, atomically swaps and runs `--version` to verify. Keeps a `yt-dlp.backup` and rolls back if anything fails. Pending update state is in-memory only.
- **`DownloadRunner`** — wraps `Process` execution of yt-dlp. Two-phase strategy per URL: first attempts a no-recode MP4 muxing (`bv*[ext=mp4]+ba[ext=m4a]/b[ext=mp4]/b` + `--merge-output-format mp4`), then falls back to a full `--recode-video mp4` pass. Trigger for the fallback is **either** an exception **or** a "non-merged" outcome detected via `pickMergedMP4` — when yt-dlp emits more than one `after_move` path or a non-`.mp4` path, the merge silently failed (e.g. ffmpeg unusable for the host arch) and the result would be a silent .mp4 + side .m4a; the recode pass forces ffmpeg back into the picture. Detects the final file via `--print after_move:__YTDL_FILE__:%(filepath)s` (parsed from stdout) — do not remove that print directive without replacing the path-detection logic.

`AppViewModel` (`@MainActor`) owns the queue and runs it strictly sequentially — one `Task` consumes `.queued` items in order. Per-item cancellation goes through `ProcessToken`, which holds the running `Process` reference and calls `terminate()` on cancel. Settings (`outputDirectoryPath`, `isLogPanelExpanded`) persist via `UserDefaults`.

### Key constraints / gotchas

- **`Packaging/Info.plist` is hand-written**, not generated. SwiftPM does not produce a usable .app — `build-universal-app.sh` assembles the bundle manually (Info.plist, AppIcon.icns, embedded binaries under `Contents/Resources/bin/`, `Sparkle.framework` under `Contents/Frameworks/`). Bump `CFBundleShortVersionString` / `CFBundleVersion` here for releases.
- **Sparkle**: ships universal `Sparkle.framework` from the SPM xcframework's `macos-arm64_x86_64` slice (located at `.build/artifacts/sparkle/Sparkle/Sparkle.xcframework/...`). `release-dmg-notarized.sh` signs nested XPC services + `Autoupdate` + `Updater.app` + the framework **before** the outer .app, in that order, with no `--deep`. Per Sparkle docs, only `Downloader.xpc` keeps `--preserve-metadata=entitlements`.
- **Sparkle public key** is stored in `Info.plist` under `SUPublicEDKey`. The placeholder `__SPARKLE_PUBLIC_ED_KEY__` is patched by `setup-sparkle.sh` on first run. The matching private key stays in the developer's Keychain (never in repo). Appcast is served from `raw.githubusercontent.com/.../master/appcast.xml`; `update-appcast.sh` regenerates it after each release.
- **`.app` and `.dmg` must both be stapled.** The release script signs each embedded binary in `Resources/bin/` individually with `--options runtime --timestamp` before signing the bundle — required for notarization.
- **Bundled binaries are gitignored** (`Resources/Binaries/*` minus `.keep`). `swift run` works without them (network fallback kicks in). For releases, run `download-binaries.sh` first so end users don't hit the network on first launch.
- **Sequential queue is intentional** (reliability on older Macs). Don't parallelize without considering yt-dlp/ffmpeg resource contention.
- **Signing identity is hardcoded** in `release-dmg-notarized.sh` (`Developer ID Application: Ouwéis Moolna (LT9VN8QXU9)`); override via `SIGNING_IDENTITY` env var. Notary profile name comes from `NOTARY_PROFILE`.
- App is **unsandboxed** (no entitlements file). It writes to `~/Library/Application Support/YTDLFront/`, executes child processes, and reads/writes the user-chosen output directory.
