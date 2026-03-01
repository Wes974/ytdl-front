# Video Downloader - Status actuel

Date: 2026-03-02

## Etat global

- App macOS native fonctionnelle (SwiftUI), cible minimale macOS 11.0.
- Nom public app: `Video Downloader`.
- Build Universal OK (`arm64 + x86_64`).
- Queue multi-liens en mode sequentiel (1 download a la fois) operationnelle.
- Pipeline MP4 garanti en place via `yt-dlp` + `ffmpeg` (avec fallback recodage).

## Fonctionnalites actuellement en place

- Ajout de plusieurs URLs (1 par ligne).
- Gestion queue: annuler, retenter, supprimer, vider termines, retenter en lot des erreurs.
- Detail progression par item + resume global (compteurs + progression queue).
- Panneau Journal repliable (masque par defaut), avec bouton nettoyer.
- MAJ `yt-dlp`: check auto, check manuel, mode "Notifier puis installer", checksum SHA-256, rollback.

## Packaging / notarisation

- Signature `Developer ID Application` active et utilisee.
- Notarisation DMG acceptee par Apple.
- Submission notary la plus recente: `eecae493-d4fd-422f-bf6e-50ea06a2ea2b` (status `Accepted`).
- Staple valide sur:
  - `dist/Video Downloader.app`
  - `dist/Video Downloader.dmg`
- Verifs OK: `codesign --verify`, `stapler validate`, `spctl --type exec` sur l'app.

## Artefacts et docs

- App bundle: `dist/Video Downloader.app`
- DMG de distribution: `dist/Video Downloader.dmg`
- Checklist release: `docs/RELEASE_CHECKLIST.md`
- Roadmap future: `docs/FUTURE_IMPROVEMENTS.md`

## Etat git actuel

- Branche courante: `master`
- Derniers commits:
  - `1eade76` feat: make logs panel collapsible by default
  - `a4313a7` fix: prevent top header clipping in constrained windows
  - `0f789bc` chore: harden notarized DMG release workflow
  - `3ad0ae2` feat: ship V2 UX and Video Downloader branding
  - `94a0aea` feat: bootstrap V1 macOS yt-dlp downloader
- Tag existant: `V1` (sur le commit initial).

## Points en cours / a finaliser

- Des modifications locales non committees existent actuellement (UI/ViewModel + docs roadmap).
- Prochaine etape recommandee: faire un commit de consolidation V2.1 avant nouvelle release partagee.
