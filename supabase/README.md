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

## Connexion anonyme

Au démarrage, l'app réutilise la session enregistrée ou crée un compte anonyme
(`signInAnonymously`), en arrière-plan ; hors ligne, elle reste jouable en
local et réessaie au retour au premier plan. Session dans le Keychain / Keystore
(`lib/backend/secure_session_storage.dart`), purge locale :
`AuthService.purgeLocalSession()` (`lib/backend/auth_service.dart`).

Dashboard (projet Paris) : Authentication > Sign In / Providers > « Allow
anonymous sign-ins » activé ; limites de débit dans Authentication > Rate Limits.

## Progression (`profiles`)

Une ligne par utilisateur, créée par trigger à l'inscription (migration
`*_profiles.sql`). Le client la **lit** seulement (RLS + GRANT select) ;
XP, série, gels et compteur de quiz sont écrits uniquement par
`submit_quiz()`. Autre écriture client : `set_daily_goal(goal)` (1 à 3).

Sync (`lib/engagement/progress_sync.dart`) : en arrière-plan après connexion,
puis au retour au premier plan (au plus 1 fois par minute). Règle de fusion :
- `last_quiz_at` null (aucun quiz soumis au serveur) : la progression locale
  est conservée telle quelle ;
- `last_quiz_at` renseigné : le serveur remplace XP, série, gels et compteur
  de quiz du jour en local ;
- l'objectif du jour est un choix local, envoyé par `set_daily_goal` à chaque
  changement et à chaque sync s'il diffère (donc réessayé après un échec) ;
- tant qu'un quiz attend d'être validé (file locale non vide), la progression
  locale, en avance, n'est pas remplacée.

## Validation des quiz (`submit_quiz`)

Migration `*_submit_quiz.sql`. En fin de quiz (mode Supabase, quiz de 10
questions), l'app affiche tout de suite son calcul local, puis envoie en
arrière-plan `submit_quiz(quiz_id, question_ids, choices, times_ms, played_at)` :
- `quiz_id` : uuid généré par l'app ; une double soumission renvoie le
  résultat déjà enregistré (`duplicate: true`) sans rien recompter ;
- `choices` : index de la réponse choisie **dans l'ordre de
  `assets/questions.json`** (avant mélange), `null` si temps écoulé ;
- `times_ms` : 500 à 30 000 ms par question ;
- `played_at` : fin du quiz selon l'appareil (quiz joué hors ligne), ramené
  entre le dernier quiz validé et maintenant ; refusé au-delà de 48 h.

Le serveur recalcule score, XP (barème de `CLAUDE.md`), série et gels
(jour calendaire **Europe/Paris** ; l'app utilise l'heure de l'appareil, même
résultat en France), compteur du jour et `last_quiz_at`, puis renvoie
`{ score, total, xp_gained, xp_capped, duplicate, profile }`. Le profil
renvoyé remplace la progression locale (règle de fusion ci-dessus).

Anti-triche : 10 questions distinctes existantes, temps plausibles, XP
plafonnée à 240 par quiz (maximum du barème) et à 3 000 par jour (au-delà le
quiz compte pour la série et l'objectif, sans XP), 20 quiz par heure glissante.
Erreurs : `22023` entrée invalide (l'app abandonne ce quiz), `PT429` trop de
quiz (HTTP 429, réessai plus tard), `42501` non authentifié.

Hors ligne ou sans session : le quiz va dans une file locale
(`lib/data/pending_quiz_repository.dart`, 30 au plus), renvoyée dans l'ordre
au sync suivant ou à la fin du quiz suivant.

Tables :
- `questions` : contenu et bonne réponse, RLS sans policy et **aucun GRANT**
  client (ni `anon` ni `authenticated` ne lisent `correct_index`). Une future
  lecture distante des questions passera par une RPC/vue sans la réponse.
- `quiz_results` : un quiz validé par ligne (jour, score, XP comptée et
  avant plafond) ; lecture de ses propres lignes, aucune écriture client.
  Servira au classement hebdo.

Les bonnes réponses sont aussi dans l'app (`assets/questions.json`) : la
validation serveur empêche surtout d'écrire XP/série à volonté, pas de
tricher en lisant l'APK. À revoir quand les questions viendront du serveur.

## Questions (`seed.sql`)

`supabase/seed.sql` est **généré** depuis `assets/questions.json` (upsert sur
`id`, `updated_at` modifié seulement si la question change, aucune
suppression) :

```sh
dart run tool/generate_seed.dart   # après chaque modification des questions
```

Un test Flutter (`test/submit_quiz_test.dart`) échoue si `seed.sql` n'est
plus à jour. Appliqué automatiquement par `supabase db reset` en local ; en
distant avec `supabase db push --include-seed`. Les identifiants de
`assets/questions.json` doivent rester stables : un quiz contenant une
question absente du serveur est refusé (`22023`).

Tests SQL : `supabase test db` (pgTAP, `tests/profiles_test.sql`,
`tests/submit_quiz_test.sql`).

## Commandes à lancer soi-même

CLI : `brew install supabase/tap/supabase` (ou `npx supabase ...`).

```sh
supabase login                              # ouvre le navigateur
supabase link --project-ref <ref-projet>    # ref = sous-domaine de SUPABASE_URL
supabase db push --dry-run                  # vérifier ce qui sera appliqué
supabase db push                            # appliquer les migrations au projet distant
supabase db push --include-seed             # idem + questions (seed.sql)
```

En local (Docker requis) : `supabase start`, `supabase db reset`, `supabase stop`.

Nouvelle migration : `supabase migration new <nom>`, puis éditer le fichier
dans `migrations/` (RLS activé sur chaque table).

## Sécurité (à respecter dans chaque migration)

- `config.jsonc` ne règle que la stack **locale**. Ne jamais lancer `supabase config push` sans relire ses valeurs ; les réglages de prod (auth, limites de débit, schémas exposés) se font dans le Dashboard du projet Paris.
- Avant tout `flutter build` : `./tool/check_config.sh` (refuse une clé secrète dans `config/*.json`).
- La clé publishable est publique : la protection des données repose uniquement sur RLS, les GRANT et les fonctions serveur.

Règles imposées par la revue sécurité (PR #9) :
1. Chaque `create table` dans `public` : `enable row level security` + policies sur `(select auth.uid())` dans la même migration, GRANT explicites (`auto_expose_new_tables` est à `false`). Jamais de policy `using (true)` en écriture.
2. Contrôle « aucune table sans RLS » :
   `select relname from pg_class c join pg_namespace n on n.oid = c.relnamespace where n.nspname = 'public' and c.relkind = 'r' and not c.relrowsecurity;` doit être vide.
3. Pas d'écriture directe du client sur scores, XP, série, gels : tout passe par `submit_quiz()` (`security definer`) qui recalcule le score côté serveur, vérifie les temps (0,5 s à 30 s par question), plafonne l'XP par quiz et par jour et limite le nombre de quiz par heure.
4. `correct_index` et `explanation` non lisibles via l'API avant la réponse (vue/RPC dédiée ou table sans GRANT pour `anon`).
5. Fonctions `security definer` : `set search_path = ''`, `revoke execute … from public, anon`, grant à `authenticated` seulement si nécessaire.
6. « Sans pub » et gels obtenus par pub récompensée : écrits uniquement côté serveur (webhook RevenueCat, SSV AdMob via Edge Function avec secret de fonction).
7. Auth : session dans le stockage sécurisé (`flutter_secure_storage`), purge locale à la déconnexion, suppression de compte dans l'app ; `site_url` / redirections limitées au schéma de l'app ; limites de débit revues pour l'auth anonyme.
8. `ssl_enforcement` activé ; `supabase db lint` et Security Advisors vérifiés régulièrement.
