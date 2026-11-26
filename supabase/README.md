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
`submit_quiz()` (et, pour la série seulement, `validate_offline_day()`).
Autre écriture client : `set_daily_goal(goal)` (1 à 3).

Sync (`lib/engagement/progress_sync.dart`) : en arrière-plan après connexion,
puis au retour au premier plan (au plus 1 fois par minute). Règle de fusion :
- `last_quiz_at` null (aucun quiz soumis au serveur, aucune journée validée
  hors ligne) : la progression locale est conservée telle quelle ;
- `last_quiz_at` renseigné : le serveur remplace XP, série, gels et compteur
  de quiz du jour en local (compteur : le plus grand des deux pour un même
  jour, car seul le 1er quiz hors ligne du jour est connu du serveur ; si
  le jour local est postérieur à celui du serveur, par exemple après une
  journée hors ligne refusée, le compteur local est gardé) ;
- l'objectif du jour est un choix local, envoyé par `set_daily_goal` à chaque
  changement et à chaque sync s'il diffère (donc réessayé après un échec) ;
- tant qu'un quiz ou une journée hors ligne attend d'être validé (files
  locales non vides), la progression locale, en avance, n'est pas remplacée.

## Quiz servis par le serveur (`start_quiz`, `next_question`, `answer_question`, `submit_quiz`)

Migrations `*_start_quiz.sql` (remplace l'ancienne signature à 5 paramètres
de `submit_quiz`), `*_temps_serveur.sql` (questions servies une à une,
temps de réponse mesuré par le serveur) et `*_questions_serveur.sql`
(questions actives seulement, identifiants jamais envoyés, réponse par
position). En mode Supabase avec une session,
un quiz se joue ainsi :

1. `start_quiz(mode, category default null)` : `mode` = `daily` (défi du
   jour), `category` (catégorie obligatoire) ou `mix`. Tire 10 questions
   **actives** (`questions.active`),
   réponses mélangées par le serveur (pour chaque joueur et chaque
   question), mais ne renvoie que **la question 1** (`questions: [q1]`,
   `total: 10`, `position: 1`, `seconds_left: 30`), **sans bonne réponse,
   ni explication, ni identifiant** (chaque question porte sa `position`),
   et
   note son heure d'envoi (`served_at`). Enregistre la session (questions
   tirées, heure de départ serveur), valable **30 min**.
   Limites (`PT429`) : 30 quiz commencés par heure (soumis ou non) et
   10 quiz non soumis (abandonnés) par jour Europe/Paris. `P0002` s'il y a
   moins de 10 questions pour ce mode (ou profil absent).
   **Défi du jour : une seule session par joueur et par jour** (index unique
   `quiz_sessions (user_id, challenge_day) where mode = 'daily'`). Un nouvel
   appel le même jour **reprend** cette session (`resumed: true`) : même
   `quiz_id`, mêmes questions, même ordre des réponses, et pour chaque
   question déjà répondue `answer: { choice, correct, correct_choice,
   explanation, time_ms }`, suivie de la question en cours (`answer: null`,
   `position` = son numéro) ; les questions suivantes ne sont pas renvoyées.
   L'app reprend à la question en cours. Si elle avait déjà été servie, elle
   garde son `served_at` d'origine : plus de 33 s après, elle compte en
   temps écoulé (voulu : sinon fermer l'app donnerait un temps illimité pour
   chercher) ; `seconds_left` (calculé par le serveur depuis `served_at`,
   0 à 30) sert de point de départ au chrono de l'app. Tout répondu :
   `position: null`, l'app passe aux résultats. La session du défi reste reprenable
   jusqu'à minuit (Europe/Paris), au moins 30 min après le départ ; une
   reprise ne compte dans aucune limite. Défi déjà soumis : erreur `23505`
   « défi du jour déjà joué », détail `{"score": n, "total": 10}`.
2. `next_question(quiz_id)` : question suivant la dernière question
   répondue (`{ quiz_id, total, position, seconds_left, question }`, sans bonne réponse ni
   explication), et note son `served_at`. **Refusée (`22023`) tant que la
   question 1 n'a pas de réponse**, quand les 10 sont répondues, sur un quiz
   expiré, soumis ou d'un autre joueur. Idempotente : rappeler (réponse
   perdue par le réseau) renvoie la même question sans changer son
   `served_at` (`seconds_left` diminue). `security definer`, EXECUTE pour
   `authenticated` seulement. Si la position reçue n'est pas celle attendue
   (quiz avancé sur un autre appareil), l'app propose seulement « Quitter ».
3. `answer_question(quiz_id, position, choice, time_ms)` : `position` =
   numéro de la question en cours (1 à 10), `choice` = position affichée
   de la réponse (0 à 3, `null` si temps écoulé). Questions dans l'ordre
   et déjà servies : la question n'est cherchée que parmi les questions
   servies, donc une position hors du quiz et une question pas encore
   servie donnent **la même erreur** (`22023` « question non servie »). Réponse horodatée par le serveur et définitive (un
   réessai renvoie la correction déjà enregistrée, même avec un autre
   `choice` ; refusé une fois le quiz soumis). **Temps mesuré par le
   serveur** : temps serveur = `now() - served_at` (gardé dans
   `elapsed_ms`) ; temps officiel (`time_ms`) = min(`time_ms` déclaré de 500
   à 30 000 ms, temps serveur), au moins 500 ms (il peut donc dépasser de
   moins de 500 ms un temps serveur très court). Temps serveur > 30 s + 3 s
   de tolérance : réponse enregistrée en **temps écoulé** (choix ignoré,
   fausse, 30 000 ms). Renvoie `{ …, correct, timed_out, time_ms,
   correct_choice, explanation }`, affichés après chaque réponse.
4. `submit_quiz(quiz_id)` : exige un quiz servi à ce joueur avec ses 10
   réponses enregistrées, une durée totale plausible (somme des temps
   officiels ≤ durée serveur + 1 s + 10 × 500 ms : un joueur très rapide
   n'est jamais refusé) et une dernière réponse
   de moins de **6 h**. Le score officiel se calcule sur les réponses
   enregistrées. **Bonus rapidité** seulement si temps officiel < 10 s **et**
   temps serveur ≤ 10 s + 2 s. Double soumission : résultat déjà enregistré
   (`duplicate: true`).

Tolérances réseau : le temps serveur compte aussi le trajet de la question
vers l'app et celui de la réponse vers le serveur (quelques centaines de ms
en 4G, 1 à 2 s sur un réseau faible). 2 s pour le bonus (un tricheur gagne
au plus 2 s de recherche par question) et 3 s avant le temps écoulé (une
réponse donnée à 29 s sur un réseau lent reste valable). Un script ne voit
plus qu'une question à la fois et ne peut plus chercher les réponses avant
de jouer.

Le serveur recalcule score, XP (barème de `CLAUDE.md`), série et gels
(jour calendaire **Europe/Paris**), compteur du jour et `last_quiz_at`, puis
renvoie `{ score, total, xp_gained, xp_capped, duplicate, profile }`. Le
profil renvoyé remplace la progression locale (règle de fusion ci-dessus).
Plafonds conservés : 240 XP par quiz, 3 000 par jour (au-delà : série et
objectif sans XP), 20 quiz validés par heure (`PT429`).

Défi du jour : table `daily_challenges(day, question_ids)`, créée à la
demande par `ensure_daily_challenge(day)` (fonction interne, idempotente,
questions actives seulement, évite si possible les questions des 7 derniers
jours). Identique pour tous. Si une question du défi a disparu ou est
devenue inactive, elle est remplacée (question active tirée au hasard, en
fin de liste) au prochain appel ; les sessions déjà commencées gardent la
leur.

**Ne jamais supprimer une question en base** : la corriger (`update`) ou la
**désactiver** (`active = false`, plus jamais tirée par `start_quiz` ni
`ensure_daily_challenge`). Une question servie dans les 2 derniers jours est
référencée par `quiz_session_questions` (clé étrangère, index
`question_id`) et sa suppression échoue ; une suppression réussie
fausserait le défi du jour et l'historique.

Purge : `purge_quiz_sessions()` (fonction interne) efface les sessions de
plus de 2 jours, réponses comprises ; lancée chaque jour à 03:30 UTC par
`pg_cron` (job `purge-quiz-sessions`, extension activée par la migration ;
`select * from cron.job_run_details order by start_time desc limit 5;` pour
vérifier). `start_quiz` purge aussi les anciennes sessions du joueur.
`quiz_results` n'est pas touché.

Erreurs : `22023` entrée invalide (quiz non servi, expiré, déjà soumis,
question non servie, `next_question` avant réponse ou après la 10e,
`quiz_id` d'un autre joueur), `P0002` profil absent
ou pas assez de questions, `PT429` trop de quiz, `23505` défi du jour déjà
joué (`start_quiz`), `42501` non authentifié. L'app traite
`22023`, `22P02`, `22003`, `23505` et `P0002` comme définitifs (quiz
abandonné, la file n'est jamais bloquée) ; les autres erreurs sont réessayées.

Repli local : hors ligne, serveur lent (plus de 6 s), `PT429`, `P0002` ou
sans session, l'app joue le **lot hors ligne** (`assets/questions.json`,
jamais servi par le serveur ; 3 questions par catégorie : un quiz local par
catégorie n'en a que 3) ; après un
échec (délai, réseau, `PT429`), elle ne rappelle pas `start_quiz` pendant
1 min. Défi déjà joué (`23505`) : pas de repli, l'app affiche « Tu as déjà
joué le défi du jour » et marque le défi comme joué sur l'accueil (avec le
score du serveur). Ces quiz
ne comptent pas au classement et ne sont jamais soumis (un message
l'indique) ; s'ils valident la journée, elle est gardée par
`validate_offline_day` (section Série hors ligne). Si la connexion tombe pendant un quiz servi, la réponse est
gardée et l'app propose « Réessayer » ou « Quitter » ; de même si la
question suivante ne se charge pas (« Question suivante » appelle
`next_question`, le chrono local de 30 s démarre à la réception). Si `submit_quiz`
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
- un quiz joué hors ligne donne de l'XP en local seulement : le profil
  serveur la remplace au sync suivant (voulu : seul le serveur accorde de
  l'XP). La série et le compteur du jour sont conservés par
  `validate_offline_day` (section suivante), dans ses limites ;
- le défi du jour ne se joue qu'une fois par compte et par jour, mais un
  nouveau compte anonyme peut le rejouer (effet borné par les plafonds
  d'XP et le classement) ;
- les bonnes réponses du lot hors ligne restent lisibles dans l'APK (sans
  effet : ces quiz ne sont jamais soumis et ces questions ne sont jamais
  servies) ;
- un quiz dont la dernière réponse arrive après 30 min est perdu (défi du
  jour : après minuit) ;
- défi du jour entièrement répondu mais jamais soumis (app fermée avant
  l'écran Résultats) : la reprise le termine, mais `submit_quiz` le refuse
  si la dernière réponse date de plus de 6 h ;
- défi commencé juste avant minuit et fini après : il compte pour le jour
  de la dernière réponse ;
- reprise du défi : la question affichée au moment de la fermeture garde
  son chrono serveur (`seconds_left`) ; à 0, l'app l'envoie aussitôt en
  temps écoulé ;
- l'XP affichée en fin de quiz est d'abord calculée par l'app, puis
  remplacée par `xp_gained` dès que `submit_quiz` répond (sur un réseau très
  lent, le serveur peut refuser un bonus rapidité ; un message l'indique).
  Si la validation est différée (hors ligne), le profil serveur corrige
  l'XP au sync suivant.

Migration `*_temps_serveur.sql` : supprime les sessions non soumises
créées par l'ancien `start_quiz` (elles avaient reçu leurs 10 énoncés) ; les
joueurs concernés recommencent leur quiz ou leur défi du jour.

## Série hors ligne (`validate_offline_day`)

Migration `*_serie_hors_ligne.sql`. Un quiz local (lot hors ligne, jamais
soumis) qui valide la journée en mode Supabase est mémorisé dans une file
locale (`lib/data/pending_offline_day_repository.dart`, clé
`pending_offline_days_v1` : compte connecté, heure de fin) ; au sync suivant,
l'app appelle `validate_offline_day(played_at)` **avant** d'appliquer le
profil serveur. Les deux files (quiz servis, journées hors ligne) sont
envoyées dans l'ordre joué. Entrée d'un autre compte ou de plus de 6 h :
abandonnée sans envoi. Sans session au moment du quiz : rien n'est mémorisé.
`AuthService.purgeLocalSession()` vide aussi cette file. Mode 100 % local :
inchangé.

`validate_offline_day(played_at timestamptz)` : `security definer`,
`search_path = ''`, EXECUTE pour `authenticated` seulement. Elle appelle
`private.validate_offline_day(uid, played_at, as_of)` avec `auth.uid()` et
`now()` : schéma `private` non exposé par l'API, aucun usage ni EXECUTE
client ; `as_of` permet aux tests de fixer l'heure. Valide le jour
(Europe/Paris) de `played_at` avec les règles de `submit_quiz` (jours
manqués couverts par les gels, sinon série perdue, gels conservés),
incrémente le compteur du jour et avance `last_quiz_at`. **Aucune XP, aucune
ligne dans `quiz_results`** (donc aucun effet sur le classement ni sur les
plafonds d'XP), **aucun gel gagné**. Verrou `for update` sur le profil.
Retour : `{ validated, reason, day, profile }` (profil au format de
`submit_quiz`).

- `22023` (définitif, l'app abandonne l'entrée) : `played_at` manquant, dans
  le futur (au-delà de 5 min de décalage d'horloge), de plus de 6 h, ou jour
  hors de la veille et d'aujourd'hui ; `42501` non authentifié (`anon`
  refusé) ; `P0002` profil absent.
- Refus propres (`validated: false`, profil renvoyé inchangé) :
  `already_validated` si le jour est déjà validé (quiz servi, appel
  précédent : idempotent) ou antérieur au dernier jour validé (le passé
  n'est pas réécrit) ; `limit` si 3 jours ont déjà été validés hors ligne
  sur les 7 jours finissant au jour du quiz (la veille a donc sa propre
  fenêtre). Un jour hors ligne aussi validé par un quiz servi (ligne dans
  `quiz_results`, index `quiz_results_day_user_idx`) ne compte pas.
- Table `offline_days (user_id, day)` : jours validés ainsi (idempotence,
  plafond), RLS sans policy, aucun GRANT client ; lignes de plus de 14 jours
  purgées à chaque validation.

Abus (inhérent au hors ligne) : rien ne prouve qu'un quiz a été joué, un
joueur peut donc valider sa série **sans jouer** en appelant la RPC. Bornes :
1 validation par jour, aujourd'hui ou la veille seulement, jamais de gel ni
d'XP ni de place au classement, et au plus **3 jours sur 7** : une série ne
tient pas durablement sans quiz servi. Un appel refusé n'écrit rien (les
limites de débit de l'API s'appliquent). Piste plus stricte si besoin :
exiger un quiz servi la veille ou l'avant-veille.

Limites :
- sur un même appareil, la journée hors ligne passe toujours avant un quiz
  servi plus récent (même file, ordre joué). Mais si un **autre appareil** a
  déjà validé le lendemain, une veille jouée hors ligne arrive trop tard
  (jour antérieur au dernier jour validé) : elle compte comme manquée (gel
  consommé ou série perdue) ;
- au-delà de 6 h sans connexion, ou au 4e jour hors ligne sur 7, la journée
  n'est plus validée et le profil serveur remplace la série locale ;
- `last_quiz_at` avancé par la RPC : `submit_quiz` date un quiz servi de
  `greatest(dernière réponse, last_quiz_at)`. Un quiz servi fini avant le
  quiz hors ligne mais envoyé après (autre appareil, ou réseau revenu plus
  tard) est donc daté de l'heure du quiz hors ligne, voire d'aujourd'hui
  alors que sa dernière réponse date de la veille (XP du jour, classement
  de la semaine). Effet faible aujourd'hui ; **à revoir avant les badges et
  les ligues** (jour d'un quiz servi = jour de sa dernière réponse) ;
- rattrapage de la veille seulement entre 0 h et 6 h (Paris) : `played_at`
  doit dater de moins de 6 h. Une veille jouée à 23 h et envoyée à 7 h est
  refusée (`22023`) et compte comme manquée. **À revoir avant les badges et
  les ligues** si des séries longues deviennent un enjeu ;
- tant que la migration n'est pas poussée, l'appel échoue (erreur
  passagère) : l'entrée est gardée jusqu'à 6 h, puis abandonnée.

## Signalements de questions (`report_question`)

Migration `*_question_reports.sql`. Après sa réponse à une question d'un
quiz **servi**, le joueur peut la signaler (lien « Signaler » sous
l'explication ; jamais en quiz local). 4 motifs fixes, pas de texte libre :
`fausse` (Réponse fausse), `ambigue` (Question ambiguë), `faute` (Faute ou
coquille), `autre`.

`report_question(p_quiz_id, p_position, p_reason)` : `security definer`,
EXECUTE pour `authenticated` seulement. L'app n'envoie que la session et la
position (1 à 10) ; le serveur retrouve la question (servie à ce joueur et
**déjà répondue**) et ne renvoie jamais son identifiant. Retour
`{ "reported": true }`, identique pour un doublon (aucune nouvelle ligne,
motif d'origine gardé). Erreurs : `22023` motif invalide ou « question
introuvable » (même erreur pour un quiz d'un autre joueur, purgé, une
position non servie ou sans réponse), `PT429` au-delà de **20 signalements
par joueur et par jour** (Europe/Paris), `42501` non authentifié.
Signalable tant que la session existe (purge après 2 jours).

Table `question_reports` (RLS sans policy, aucun GRANT client) :
`question_id` (clé étrangère vers `questions`, pas vers la session : le
signalement survit à la purge), `user_id` (`on delete set null` : gardé
après suppression du compte), `reason`, `created_at`, unique
`(user_id, question_id)`.

Trier les signalements (SQL Editor du Dashboard, ou `supabase db query`) :

```sql
select r.question_id,
       count(*) as signalements,
       count(*) filter (where r.reason = 'fausse')  as fausse,
       count(*) filter (where r.reason = 'ambigue') as ambigue,
       count(*) filter (where r.reason = 'faute')   as faute,
       count(*) filter (where r.reason = 'autre')   as autre,
       max(r.created_at) as dernier,
       q.active,
       q.question,
       q.answers[q.correct_index + 1] as bonne_reponse,
       q.explanation
  from public.question_reports r
  join public.questions q on q.id = r.question_id
 group by r.question_id, q.active, q.question, q.answers, q.correct_index,
          q.explanation
 order by signalements desc, dernier desc;
```

Correction : modifier la question dans `supabase/questions/questions.json`
(ou l'en retirer pour la désactiver), régénérer le seed puis
`supabase db push --include-seed`. Les signalements traités peuvent ensuite
être supprimés (`delete from public.question_reports where question_id = …`).

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

Deux lots **disjoints** :
- **questions du serveur** : `supabase/questions/questions.json`, hors
  bundle (jamais déclaré dans `pubspec.yaml`, jamais copié dans `assets/`).
  Seules elles sont servies (`start_quiz`, défi du jour, classement) ;
- **lot hors ligne** : `assets/questions.json`, embarqué dans l'app (bonnes
  réponses lisibles dans l'APK), joué seulement en local (hors ligne, sans
  session, `P0002`), jamais soumis, hors classement. Ses identifiants sont
  désactivés en base (`active = false`) s'ils y sont encore.

`supabase/seed.sql` est **généré** depuis `supabase/questions/questions.json`
(upsert sur `id`, `active = true`, `updated_at` modifié seulement si la
question change ; toute question absente du fichier est désactivée, jamais
supprimée) :

```sh
dart run tool/generate_seed.dart   # après chaque modification des questions
```

Ajouter une question serveur : l'ajouter à `supabase/questions/questions.json`
(nouvel `id` stable, ex. `his-014`, champs `category`, `question`, 4
`answers`, `correctIndex`, `explanation`, `difficulty`), régénérer le seed,
puis `supabase db push --include-seed`. Retirer une question : l'enlever du
fichier puis régénérer (le seed la désactive). Ne jamais copier une question
du serveur dans `assets/`.

Tests Flutter : `test/submit_quiz_test.dart` échoue si `seed.sql` n'est plus
à jour ; `test/questions_test.dart` échoue si un identifiant ou un énoncé est
dans les deux lots, si une question du serveur apparaît dans `assets/`, ou
s'il y a moins de 10 questions serveur par catégorie. Seed appliqué
automatiquement par `supabase db reset` en local ; en distant avec
`supabase db push --include-seed`. Sans seed en distant, tout est joué en
local (hors classement).

Tests SQL : `supabase test db` (pgTAP, `tests/profiles_test.sql`,
`tests/start_quiz_test.sql`, `tests/submit_quiz_test.sql`,
`tests/temps_serveur_test.sql`, `tests/questions_serveur_test.sql`,
`tests/weekly_leaderboard_test.sql`, `tests/serie_hors_ligne_test.sql`,
`tests/question_reports_test.sql`).

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
