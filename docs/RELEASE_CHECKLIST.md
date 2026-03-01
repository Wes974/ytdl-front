# Notarization and DMG checklist

Use this checklist for each public build.

## 1) Pre-flight

- Confirm Apple Developer certificates are valid.
- Bump `CFBundleShortVersionString` and `CFBundleVersion` in `Packaging/Info.plist`.
- Refresh embedded binaries:

```bash
./scripts/download-binaries.sh
```

## 2) Build + sign + notarize

Create/update your notary profile once:

```bash
xcrun notarytool store-credentials "AC_PROFILE" \
  --apple-id "<apple-id>" \
  --team-id "LT9VN8QXU9" \
  --password "<app-password>"
```

Run release pipeline:

```bash
NOTARY_PROFILE=AC_PROFILE ./scripts/release-dmg-notarized.sh
```

Artifacts:

- `dist/Video Downloader.app`
- `dist/Video Downloader.dmg`

## 3) Validate before sending

```bash
./scripts/verify-distribution.sh
```

Also test manually on another Mac account or another machine:

1. Open DMG
2. Drag app to Applications
3. Launch app normally
4. Download one test URL

## 4) Send to end user

- Share only `dist/Video Downloader.dmg`
- Include install instruction: open DMG, drag to Applications, launch

## Optional: publish on GitHub automatically

```bash
NOTARY_PROFILE=AC_PROFILE ./scripts/publish-release.sh <tag>
```

Example:

```bash
NOTARY_PROFILE=AC_PROFILE ./scripts/publish-release.sh V2
```
