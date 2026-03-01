# Video Downloader - Pistes d'amelioration futures

Ce document centralise les idees pour les prochaines versions de l'app.
Objectif: garder une roadmap claire apres la V2 (queue multi-liens + notarisation OK).

## Priorite haute (impact direct utilisateur)

### 1) Persistance de la file
- Sauvegarder la queue sur disque (etat, progression, erreurs, ordre).
- Restaurer automatiquement au lancement.
- Marquer proprement les jobs "en cours" comme "interrompus" apres crash/quit force.

### 2) Controles de queue avances
- Pause / Reprendre la queue globale.
- Annuler tout, retenter tout, supprimer tout.
- Reordonner les elements (drag and drop).
- Option "1 a la fois" / "2 en parallele" configurable.

### 3) Progression plus lisible
- Afficher vitesse, ETA, taille telechargee/totale.
- Etat detaille par etape (download, merge, recode, finalize).
- Resume global de session (N succes, N erreurs, temps total).

### 4) Journal utilisable en prod
- Badge "nouveaux logs" quand le panneau est replie.
- Filtres: info / warning / error.
- Export des logs en fichier texte (support/debug).

## Priorite moyenne

### 5) Validation intelligente des liens
- Detecter et ignorer les doublons.
- Validation plus fine (URLs supportees, playlists, shorts, etc.).
- Feedback utilisateur plus explicite avant ajout en queue.

### 6) Qualite/format configurable
- Presets: Best, 1080p, 720p, 480p.
- Option "audio only" (mp3/m4a) selon usage.
- Gestion des sous-titres (download + embed optionnel).

### 7) Notifications macOS
- Notification a la fin d'un telechargement.
- Notification en cas d'erreur.
- Option activer/desactiver dans les preferences.

### 8) UX generale
- Ecran Preferences (dossier par defaut, format par defaut, queue).
- Raccourcis clavier utiles.
- Etat vide plus guide (exemples de liens, aide rapide).

## Fiabilite et maintenance

### 9) Robustesse download
- Retry automatique avec backoff sur erreurs reseau temporaires.
- Timeout parametrable.
- Detection propre des erreurs connues yt-dlp (geo, age, private, DRM).

### 10) Gestion des binaires
- Politique de mise a jour ffmpeg (mensuelle ou manuelle).
- Verification hash/signature supplementaire quand possible.
- Nettoyage des anciennes versions locales.

### 11) Mises a jour de l'app elle-meme
- Integrer Sparkle pour update de Video Downloader.
- Flux de release signe + notes de version.
- Canaux stable/beta (optionnel).

## Packaging, distribution, support

### 12) Pipeline release automatise
- CI pour build universal + signature + notarisation.
- Job de verification Gatekeeper apres notarisation.
- Checklists auto pour reduire les erreurs humaines.

### 13) DMG plus propre
- Fond/icone DMG personnalises.
- Lien Applications bien positionne.
- Version dans le nom du DMG (ex: VideoDownloader-0.2.1.dmg).

### 14) Support utilisateur
- Ecran "A propos" (version app, version yt-dlp, diagnostics rapides).
- Bouton "Copier infos support" (OS, versions, erreurs recentes).
- FAQ integree (liens non telechargeables, limitations DRM, etc.).

## Qualite logicielle

### 15) Tests
- Tests unitaires sur parser de progression/logs.
- Tests integration sur queue (states + transitions).
- Tests de non-regression pour update yt-dlp (checksum + rollback).

### 16) Architecture
- Separation plus nette UI / domaine / infra.
- Protocoles pour faciliter le mocking.
- Isolation des services reseau/processus pour tests.

### 17) Observabilite
- Telemetrie locale minimale (sans collecte externe) pour debug.
- Compteurs internes: taux succes, types d'erreurs frequentes.
- Mode diagnostic activable temporairement.

## Accessibilite et internationalisation

### 18) Accessibilite
- Labels VoiceOver complets.
- Contraste et tailles de texte adaptes.
- Navigation clavier complete.

### 19) i18n
- Localisation FR/EN.
- Chaines centralisees dans un systeme de localisation.

## Securite et conformite

### 20) Bonnes pratiques
- Revue reguliere des permissions/entitlements.
- Politique claire de conservation des logs.
- Documentation legale plus visible (usage responsable, limites DRM).

## Proposition de roadmap

### V2.1 (court terme)
- Persistance queue
- Pause/Reprendre
- Vitesse + ETA
- Badge nouveaux logs

### V2.2 (moyen terme)
- Preferences completes
- Presets qualite/format
- Notifications macOS
- Export logs

### V3.0 (plus ambitieux)
- Auto-update app via Sparkle
- CI release notarisee
- Refonte architecture + couverture tests elevee
