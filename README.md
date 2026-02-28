# YTDLFront

App macOS (11+) pour telecharger des videos en MP4 via `yt-dlp` avec file multi-liens et mises a jour `yt-dlp` en mode **Notifier puis installer**.

## Fonctionnalites V1

- Colle plusieurs liens (1 lien par ligne)
- File d'attente sequentielle (1 telechargement a la fois)
- Sortie MP4 garantie avec fallback recodage (`ffmpeg`)
- Dossier de sortie configurable
- Check MAJ `yt-dlp` quotidien + bouton manuel
- Installation MAJ uniquement sur action utilisateur
- Verification checksum SHA-256 + rollback automatique en cas d'echec

## Prerequis

- macOS 11+
- Xcode / toolchain Swift

## Developpement local

```bash
swift run
```

L'app tente d'utiliser des binaires embarques (`Resources/Binaries`), sinon elle telecharge:

- `yt-dlp_macos` depuis le release GitHub latest
- `ffmpeg` et `ffprobe` depuis evermeet

## Preparer des binaires embarques

```bash
./scripts/download-binaries.sh
```

Les fichiers sont places dans `Resources/Binaries/`.

## Build app Universal

```bash
./scripts/build-universal-app.sh
```

Sortie: `dist/YTDLFront.app`

## Signature + DMG notarise

1) Configurer un profil notarytool:

```bash
xcrun notarytool store-credentials "AC_PROFILE" \
  --apple-id "<ton-apple-id>" \
  --team-id "LT9VN8QXU9" \
  --password "<app-specific-password>"
```

2) Lancer release:

```bash
NOTARY_PROFILE=AC_PROFILE ./scripts/release-dmg-notarized.sh
```

Sortie: `dist/YTDLFront.dmg`

## Notes

- Cette app est fournie pour usage legal uniquement.
- Certains contenus peuvent etre indisponibles (DRM, restrictions geographiques, etc.).
