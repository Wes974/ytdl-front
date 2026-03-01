# Video Downloader

App macOS (11+) pour telecharger des videos en MP4 via `yt-dlp` avec file multi-liens et mises a jour `yt-dlp` en mode **Notifier puis installer**.

## Fonctionnalites V2

- Colle plusieurs liens (1 lien par ligne)
- File d'attente sequentielle (1 telechargement a la fois)
- Sortie MP4 garantie avec fallback recodage (`ffmpeg`)
- Dossier de sortie configurable
- Resume de file (en attente/en cours/termines/erreurs)
- Retenter les erreurs en lot + copie des liens en erreur
- Check MAJ `yt-dlp` quotidien + bouton manuel
- Installation MAJ uniquement sur action utilisateur
- Verification checksum SHA-256 + rollback automatique en cas d'echec
- Icone app dediee + nom public `Video Downloader`

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

Sortie: `dist/Video Downloader.app`

## Signature + DMG notarise

Plan de release recommande pour partage utilisateur final (ex: installation chez ton pere):

1) Preparer les binaires embarques pour eviter les telechargements au premier launch:

```bash
./scripts/download-binaries.sh
```

2) Configurer un profil `notarytool` (une seule fois):

```bash
xcrun notarytool store-credentials "AC_PROFILE" \
  --apple-id "<ton-apple-id>" \
  --team-id "LT9VN8QXU9" \
  --password "<app-specific-password>"
```

3) Lancer build + signature + notarisation + staple:

```bash
NOTARY_PROFILE=AC_PROFILE ./scripts/release-dmg-notarized.sh
```

Sortie: `dist/Video Downloader.dmg`

4) Verification Gatekeeper/notarisation avant envoi:

```bash
./scripts/verify-distribution.sh
```

5) Envoi:

- envoyer `dist/Video Downloader.dmg`
- installation cible: ouvrir DMG, glisser l'app dans `Applications`, lancer

## Publier une GitHub Release (1 commande)

```bash
NOTARY_PROFILE=AC_PROFILE ./scripts/publish-release.sh V2
```

Le script:

- rebuild + signe + notarise + staple le DMG (sauf si `--skip-notarize`)
- cree ou met a jour la release GitHub du tag cible
- upload `dist/Video Downloader.dmg` comme asset

Checklist detaillee: `docs/RELEASE_CHECKLIST.md`

## Notes

- Cette app est fournie pour usage legal uniquement.
- Certains contenus peuvent etre indisponibles (DRM, restrictions geographiques, etc.).
