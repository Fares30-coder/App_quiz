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

## Quiz servis par le serveur (`start_quiz`, `answer_question`, `submit_quiz`)

Migration `*_start_quiz.sql` (remplace l'ancienne signature à 5 paramètres de
`submit_quiz`). En mode Supabase avec une session, un quiz se joue ainsi :

1. `start_quiz(mode, category default null)` : `mode` = `daily` (défi du
   jour), `category` (catégorie obligatoire) ou `mix`. Renvoie `quiz_id` et
   10 questions **sans bonne réponse ni explication**, réponses mélangées par
   le serveur (pour chaque joueur et chaque question). Enregistre la session
   (questions servies, heure de départ serveur), valable **30 min**.
   30 quiz commencés par heure au plus (`PT429`) ; `P0002` s'il y a moins de
   10 questions pour ce mode (ou profil absent). Sessions effacées après
   2 jours.
2. `answer_question(quiz_id, question_id, choice, time_ms)` : `choice` =
   position affichée (0 à 3, `null` si temps écoulé). Questions dans l'ordre,
   réponse horodatée par le serveur et définitive (un réessai renvoie la
   correction déjà enregistrée). `time_ms` doit rester sous le temps écoulé
   côté serveur depuis la réponse précédente, plus 1 s. Renvoie la correction
   et l'explication, affichées après chaque réponse.
3. `submit_quiz(quiz_id)` : exige un quiz servi à ce joueur avec ses 10
   réponses enregistrées, une durée totale plausible et une dernière réponse
   de moins de **6 h**. Le score officiel se calcule sur les réponses
   enregistrées. Double soumission : résultat déjà enregistré
   (`duplicate: true`).

Le serveur recalcule score, XP (barème de `CLAUDE.md`), série et gels
(jour calendaire **Europe/Paris**), compteur du jour et `last_quiz_at`, puis
renvoie `{ score, total, xp_gained, xp_capped, duplicate, profile }`. Le
profil renvoyé remplace la progression locale (règle de fusion ci-dessus).
Plafonds conservés : 240 XP par quiz, 3 000 par jour (au-delà : série et
objectif sans XP), 20 quiz validés par heure (`PT429`).

Défi du jour : table `daily_challenges(day, question_ids)`, créée à la
demande par `ensure_daily_challenge(day)` (fonction interne, idempotente,
évite si possible les questions des 7 derniers jours). Identique pour tous,
pas de `pg_cron` pour l'instant.

Erreurs : `22023` entrée invalide (quiz non servi, expiré, hors ordre, temps
impossible, `quiz_id` d'un autre joueur), `P0002` profil absent ou pas assez
de questions, `PT429` trop de quiz, `42501` non authentifié. L'app traite
`22023`, `22P02`, `22003`, `23505` et `P0002` comme définitifs (quiz
abandonné, la file n'est jamais bloquée) ; les autres erreurs sont réessayées.

Repli local : hors ligne, serveur lent (plus de 6 s), `PT429`, `P0002` ou
sans session, l'app joue les questions de `assets/questions.json`. Ces quiz
ne comptent pas au classement et ne sont jamais soumis (un message
l'indique). Si la connexion tombe pendant un quiz servi, la réponse est
gardée et l'app propose « Réessayer » ou « Quitter ». Si `submit_quiz`
échoue (réseau), seul l'identifiant du quiz va dans la file locale
(`lib/data/pending_quiz_repository.dart`, clé `pending_quizzes_v2`),
renvoyée au sync suivant ; `AuthService.purgeLocalSession()` la vide.

Tables (RLS activé, aucune policy ni GRANT client sauf mention) :
- `questions` : contenu et bonne réponse ; ni `anon` ni `authenticated` ne
  lisent `correct_index`.
- `daily_challenges`, `quiz_sessions`, `quiz_session_questions` : défi du
  jour, quiz servis et réponses enregistrées.
- `quiz_results` : un quiz validé par ligne (jour, score, XP comptée et
  avant plafond) ; lecture de ses propres lignes, aucune écriture client.
  Alimente le classement hebdo.

Limites connues :
- un quiz joué hors ligne valide la journée et donne de l'XP en local
  seulement ; le profil serveur l'écrase au sync suivant (série perdue
  possible). Piste : une RPC qui ne valide que le jour ;
- le défi du jour peut être rejoué en connaissant les réponses (borné par
  les plafonds d'XP) ;
- les bonnes réponses restent lisibles dans l'APK tant que toutes les
  questions du serveur y sont aussi ;
- un quiz dont la dernière réponse arrive après 30 min est perdu.

## Classement hebdo (`weekly_leaderboard`)

Migration `*_weekly_leaderboard.sql`. Classement **global** de la semaine en
cours, du lundi 00:00 au dimanche 23:59 (Europe/Paris, changement d'heure
compris), calculé uniquement sur l'XP **comptée** de `quiz_results` (après
plafonds) : le score officiel du serveur, jamais une valeur du client.
**Plafond propre au classement** : 1 000 XP par joueur et par jour au plus
(`least(sum(xp), 1000)` par jour, puis somme sur la semaine) ; l'XP du profil
n'est pas touchée (plafond de `submit_quiz` : 3 000 par jour).

`weekly_leaderboard(max_entries default 50)` (1 à 100, ramené dans
l'intervalle), `security definer`, EXECUTE pour `authenticated` seulement
(`anon` refusé, `42501`). Retour :

```json
{ "week_start": "2026-11-23", "week_end": "2026-11-29",
  "ends_at": "2026-11-29T23:00:00+00:00",
  "entries": [{ "rank": 1, "display_name": "Joueur482913", "xp": 630, "is_me": false }],
  "me": { "rank": 12, "xp": 380, "display_name": "Joueur000123" } }
```

- `me` est renvoyé même hors du top ; `rank` y vaut `null` sans XP cette
  semaine. Seuls les joueurs avec au moins 1 XP sont classés.
- Ex-aequo : même rang (1, 2, 2, 4) ; ordre d'affichage stable : XP
  décroissante, puis le premier à avoir atteint ce total (heure serveur du
  dernier quiz rapportant de l'XP), puis identifiant (jamais exposé).
- Aucune donnée personnelle : ni identifiant, ni série, ni date de jeu ;
  `profiles` reste lisible uniquement par son propriétaire.
- `profiles.display_name` : pseudo public **unique** (index unique sur
  `lower(display_name)`, casse ignorée), généré à l'inscription par
  `generate_display_name()` (`Joueur` + 6 chiffres aléatoires, sans lien avec
  l'uid ; 10 essais, puis 10 à 9 chiffres, sinon erreur ; `handle_new_user()`
  réessaie 3 fois en cas de course entre deux inscriptions). Comptes existants
  remplis ligne par ligne par la migration, sans doublon. 3 à 20 caractères : lettres (accents compris),
  chiffres, espace, `_`, `-`, `.`, sans espace au bord. Pas encore
  modifiable par le joueur (future RPC, avec modération).
- Index `quiz_results (day, user_id) include (xp, submitted_at)` : agrégation
  de la semaine en parcours d'index seul. Calcul à chaque appel (suffisant au
  lancement ; à mettre en cache ou matérialiser si le volume grossit).
- `leaderboard_week_start(at)` et `generate_display_name()` : fonctions
  internes, non exposées aux clients.

App (`lib/leaderboard/leaderboard_controller.dart`) : chargé à l'ouverture de
session, rechargé après chaque quiz validé par `submit_quiz` (toujours), par
tirage (ignoré moins de 10 s après un chargement réussi) et à l'ouverture de
l'onglet (s'il date de plus d'une minute). Mode local : message
« Classement indisponible », aucun faux classement. Hors ligne : dernier
classement chargé avec un bandeau, sinon message et « Réessayer ».

### À faire avant la publication

- Comptes anonymes en prod : captcha (Dashboard > Authentication > Attack
  Protection) et limite de créations par IP.
- Classement en cache (table remplie par `pg_cron`, par exemple chaque
  minute) quand le volume de `quiz_results` grossit.
- Politique de confidentialité : indiquer que le classement révèle
  l'activité (pseudo et XP de la semaine) des joueurs du top.

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
`assets/questions.json` doivent rester stables (référencés par les sessions
et les défis du jour). Avec 3 questions par catégorie (21 au total), le défi
du jour et le mix sont servis par le serveur, les quiz par catégorie
retombent en local (`P0002`) jusqu'à 10 questions par catégorie. Sans seed
en distant, tout est joué en local (hors classement).

Tests SQL : `supabase test db` (pgTAP, `tests/profiles_test.sql`,
`tests/start_quiz_test.sql`, `tests/submit_quiz_test.sql`,
`tests/weekly_leaderboard_test.sql`).

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
