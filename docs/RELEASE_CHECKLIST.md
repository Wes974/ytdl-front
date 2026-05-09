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

This also updates `appcast.xml` (Sparkle) when the public key has been
wired in. Don't forget to commit + push it:

```bash
git add appcast.xml && git commit -m "release: appcast for V2" && git push
```

Without that commit, Sparkle clients won't see the new version — the
appcast is fetched from `raw.githubusercontent.com/.../master/appcast.xml`.

## First-time Sparkle setup (one-shot per dev machine)

Generates the EdDSA signing keypair (private stays in Keychain, public
goes into Info.plist):

```bash
swift build  # populates .build/artifacts/sparkle/.../bin/
./scripts/setup-sparkle.sh
git add Packaging/Info.plist && git commit -m "chore: configure Sparkle public key"
```

Re-running `setup-sparkle.sh` after the key is set is a no-op.
