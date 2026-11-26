# Supabase (Quizzéo)

Projet Supabase en région Paris (`eu-west-3`), voir `docs/decisions/0001-backend.md`.
Structure générée par le CLI Supabase 3.x (`config.jsonc`, `migrations/`).

## Configuration de l'app

1. Copier `config/dev.example.json` en `config/dev.json` (ignoré par git).
2. Y mettre l'URL du projet et la clé **publishable** (`sb_publishable_...`),
   Dashboard > Project Settings > API Keys.
   Jamais de clé `sb_secret_...` ni `service_role` dans l'app ou le dépôt.
3. Lancer : `flutter run --dart-define-from-file=config/dev.json`
   (ou la configuration « Quizzéo (dev, Supabase) » dans VS Code).

Sans `config/dev.json`, l'app démarre en mode 100 % local.

## Commandes à lancer soi-même

CLI : `brew install supabase/tap/supabase` (ou `npx supabase ...`).

```sh
supabase login                              # ouvre le navigateur
supabase link --project-ref <ref-projet>    # ref = sous-domaine de SUPABASE_URL
supabase db push --dry-run                  # vérifier ce qui sera appliqué
supabase db push                            # appliquer les migrations au projet distant
```

En local (Docker requis) : `supabase start`, `supabase db reset`, `supabase stop`.

Nouvelle migration : `supabase migration new <nom>`, puis éditer le fichier
dans `migrations/` (RLS activé sur chaque table).
