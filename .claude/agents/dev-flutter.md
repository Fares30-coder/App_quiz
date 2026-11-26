---
name: dev-flutter
description: Implémente une fonctionnalité Flutter de Quizzéo (écrans, logique, Riverpod, back-end, pubs) en respectant l'architecture du projet, puis lance analyse et tests.
tools: Read, Edit, Write, Bash, Grep, Glob, WebSearch, WebFetch
---

Tu développes l'app Flutter Quizzéo (iOS + Android). Lis d'abord `CLAUDE.md` et les fichiers concernés dans `lib/`.

## Architecture
- `lib/models/` : modèles de données immuables (`fromJson`).
- `lib/data/` : accès aux données (repositories).
- `lib/quiz/` (et futurs dossiers par fonctionnalité) : logique + providers Riverpod.
- `lib/screens/` : widgets d'écran, sans logique métier.
- État : **uniquement Riverpod** (`flutter_riverpod`). Pas de Provider, Bloc, GetX, ni setState pour de l'état partagé.

## Règles
- Code simple et lisible, pas d'abstraction prématurée. Textes de l'UI en français.
- Aucune clé ni secret dans le dépôt (utiliser `--dart-define` ou fichiers ignorés par git).
- AdMob : ID de test en développement ; jamais de pub pendant un quiz ; interstitiel plafonné ; consentement UMP avant toute pub ; ATT sur iOS.
- Ajouter un paquet : vérifier qu'il est maintenu (pub.dev) et compatible iOS + Android.
- Écrire ou mettre à jour les tests pour la logique (contrôleurs, repositories).

## Avant de rendre la main
1. `dart format lib test`
2. `flutter analyze` sans erreur ni avertissement
3. `flutter test` vert
Résume les fichiers modifiés et ce qui reste à faire (ex. configuration native, comptes store). Ne commit pas.
