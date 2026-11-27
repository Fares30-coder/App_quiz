# Plan de la suite — Quizzéo

> Source unique du plan. Mis à jour à chaque PR qui termine une tâche (voir « Comment tenir ce plan à jour »).

## Statut global

- **Date** : 2026-11-27 — `main` à jour, PR #1 à #29 mergées.
- **Étape en cours** : **2 (back-end + comptes + classement)**, T1 à T7 et T10 faites, plus le top 3 de différenciation (partage sans spoiler, signalement, source, ancrage francophone). Migrations `question_reports` et `source_explication` appliquées en distant, seed exécuté.
- **Reste en étape 2** : T11 (4G), comptes (T12 liaison, T13 suppression : comptes anonymes faits, reste révocation Apple après T12 et page web), anti-abus (T14, T15), contenu (T16 : 140/500, T17), petits correctifs (T9, T39, T40), non-répétition (T38, après T16), tri des signalements (T41, continu).
- **Étape 1** : terminée (quiz local, série, XP, niveaux, objectif, sons, rappel, partage, app en français).
- **Étape 5 (TikTok)** : pas commencée, à lancer maintenant en parallèle.

Légende : taille **S** ≤ ½ journée, **M** 1-2 jours, **L** 3 jours et plus. **Sécu** = revue `securite` obligatoire avant merge. **[MH]** = must-have publication (voir § Bloquant).

## Étape 2 — Back-end, comptes, classement

Fait :
- [x] T1 ADR back-end Supabase (`docs/decisions/0001-backend.md`)
- [x] T2 Branchement Supabase (`--dart-define-from-file=config/dev.json`)
- [x] T3 Connexion anonyme
- [x] T4 Synchro de la progression (`profiles`)
- [x] T5 `submit_quiz` serveur
- [x] T6 Classement hebdo global
- [x] T7 Quiz servis par le serveur : `start_quiz` / `next_question` / `answer_question` / `submit_quiz(quiz_id)`, temps serveur, défi du jour serveur, limite d'abandons, purge pg_cron, questions serveur hors de l'app (PR #15, #16, #17)
- [x] T10 Série hors ligne préservée : `validate_offline_day` (PR #22)

Fait hors plan initial (top 3 de différenciation, `marketing/strategie-produit.md`) :
- [x] Agent `strategie-produit` (PR #18) ; analyse concurrentielle `marketing/concurrence.md` + `marketing/strategie-produit.md` (PR #20)
- [x] Partage : grille sans spoiler + numéro du défi (PR #21) ; numéro/jour du défi pris sur le jour serveur (Paris), figé au début du quiz (PR #24)
- [x] « Signaler une question » : RPC `report_question`, table `question_reports`, 4 motifs fixes, plafond 20/jour, purge 90 j (PR #25)
- [x] Champ `source` affiché dans la correction (PR #26) ; sources remplies (PR #27) ; corrections factuelles, 140/140 sourcées (PR #29)
- [x] Ancrage francophone (~30 %) dans `design/charte.md`, agent `redacteur-questions` à jour : questions serveur, `source` obligatoire (PR #28)

À faire :

| # | Statut | Tâche | Objectif | Livrable / critère de fin | Dépend de | Agent(s) | Sécu | Taille |
|---|---|---|---|---|---|---|---|---|
| T8 | à faire | Comptes développeur **[MH]** | Ouvrir Apple Developer (99 $/an) et Google Play Console (25 $) | Comptes validés (identité vérifiée), bundle ID / applicationId réservés, contrat « apps payantes » Apple + profil marchand Google signés | Décision D5 | Fares (admin) | non | S (mais délais de validation de plusieurs jours) |
| T9 | à faire | Bandeau « Mode local » | Rendre visible en debug que l'app tourne sans Supabase ; noter les pièges CLI | Bandeau affiché en debug seulement si config absente ; test widget ; `supabase/README.md` : `db query --remote -f supabase/seed.sql` pour un seed modifié, toujours `--remote` | — | dev-flutter, relecteur-code | non | S |
| T10 | fait (PR #22) | Série hors ligne préservée **[MH]** | Un quiz hors ligne qui valide la journée ne doit plus être écrasé par le profil serveur | RPC qui valide uniquement le jour (pas d'XP, pas de classement), appelée à la reconnexion ; test pgTAP + test Dart du scénario « hors ligne puis synchro » ; série intacte | — | dev-flutter | **oui** | M |
| T11 | à faire | Bonus rapidité en 4G lente **[MH]** | Vérifier la tolérance de 2 s de `submit_quiz` sur réseau dégradé | Essai sur appareil réel avec Network Link Conditioner (iOS) / profil réseau lent (Android) ; résultat noté dans `supabase/README.md` ; tolérance ajustée si besoin | — | dev-flutter | oui si tolérance modifiée | S |
| T12 | à faire | Liaison compte anonyme → Apple / Google | Ne pas perdre la progression (changement de téléphone, réinstallation) | `linkIdentityWithIdToken` : Sign in with Apple (iOS), Google (iOS + Android) ; écran Profil « Sauvegarder ma progression » ; cas « identité déjà liée à un autre compte » géré ; tests | T8 (capability Sign in with Apple), D3 | dev-flutter | **oui** | L |
| T13 | en cours (C1 = PR #34 : comptes anonymes) | Suppression de compte **[MH]** | Satisfaire App Store 5.1.1(v) et la règle Google Play de suppression | Edge Function `delete_account` : supprime données puis utilisateur, révoque le jeton Apple (TN3194) ; bouton dans Profil avec confirmation ; page web de demande de suppression (exigée par Google Play) ; testée avec compte anonyme et compte Apple | T12 | dev-flutter, securite, conformite-stores | **oui** | L |
| T14 | à faire | Anti-abus comptes **[MH]** | Limiter la création massive d'anonymes et les MAU fantômes | Limites de débit Auth réglées dans le Dashboard (noté dans README) ; purge pg_cron des anonymes inactifs (ex. 90 j sans activité, sans liaison) ; CAPTCHA selon D4 | — | dev-flutter | **oui** | M |
| T15 | à faire | Repérage des comptes suspects **[MH]** | Masquer les tricheurs du classement | Requête (100 % juste + temps médian < 2 s sur N quiz) ; colonne `hidden_from_leaderboard` lue par `weekly_leaderboard` ; procédure manuelle dans README ; test pgTAP | — | dev-flutter | **oui** | M |
| T16 | en cours (C1 = PR #23) | Contenu : 500+ questions serveur **[MH]** | Parade principale contre la récolte des réponses, et promesse du MVP | Lots de ~70 (10/catégorie) dans `supabase/questions/questions.json`, ~30 % d'ancrage francophone, `source` remplie, chacun relu par `verificateur-faits`, seed régénéré et exécuté en distant, 1 PR par lot. Fait : C1 (lot 2, PR #23) → **140 questions, 20/catégorie, 140/140 sourcées**. Reste ≥ 360 questions : C2 à C7 (≥ 500 au total, ≥ 72/catégorie) | — | redacteur-questions, verificateur-faits | non | L (continu) |
| T17 | à faire | Lot hors ligne dédié | Avoir 10 questions/catégorie jouables hors ligne | `assets/questions.json` à 70 questions (21 aujourd'hui), disjointes du serveur (`test/questions_test.dart` vert) | — | redacteur-questions, verificateur-faits | non | M |
| T38 | à faire | Non-répétition sur 30 jours | Ne pas resservir une question vue il y a moins de 30 jours (décision top 3 n° 4) | Table `question_history` (user_id, question_id, date de vue) remplie côté serveur au service des questions ; tirage prioritaire des questions non vues, repli sur les plus anciennes si le stock est épuisé ; défi du jour inchangé (même quiz pour tous) ; purge pg_cron > 30 j ; RLS sans accès client ; tests pgTAP | T16 (≥ 500 questions) | dev-flutter, securite | **oui** | M |
| T39 | à faire | Accueil : jour du défi serveur | Supprimer l'incohérence de date accueil / résultats pour un joueur hors fuseau de Paris (mineur) | L'accueil (carte défi, « joué aujourd'hui ») utilise le jour serveur (Europe/Paris) quand il est connu, sinon le jour local ; test Dart avec une horloge décalée | — | dev-flutter, relecteur-code | non | S |
| T40 | à faire | Test widget Résultats (mineur) | Verrouiller que date et partage de l'écran Résultats viennent de `s.day` | Test widget : session dont `day` ≠ jour local → date affichée et texte partagé sur `s.day` (peut aller dans la PR de T39) | — | dev-flutter | non | S |
| T41 | en continu | Tri des signalements | Corriger vite les questions signalées (notes store) | Chaque semaine : requête de tri de `supabase/README.md` (§ Signalements) ; question fautive corrigée ou désactivée dans `questions.json` via une PR `content/…` relue par `verificateur-faits`, seed exécuté en distant ; rythme noté dans le README | PR #25 | Fares, verificateur-faits, redacteur-questions | non | S (récurrent) |

## Étape 3 — Pubs, consentement, achat « sans pub »

| # | Statut | Tâche | Objectif | Livrable / critère de fin | Dépend de | Agent(s) | Sécu | Taille |
|---|---|---|---|---|---|---|---|---|
| T18 | à faire | ADR 0002 « sans pub » | Trancher achat unique vs abonnement, prix, RevenueCat vs natif | `docs/decisions/0002-sans-pub.md` accepté par Fares ; CLAUDE.md mis à jour | D1 | (architecte), conformite-stores | non | S |
| T19 | à faire | Consentement UMP + ATT **[MH]** | Aucune requête pub avant le consentement (EEE) ; ATT sur iOS | `google_mobile_ads` + UMP branchés sur `consent_screen.dart` ; message IDFA créé dans AdMob ; `NSUserTrackingUsageDescription` ; entrée « Gérer mes choix de confidentialité » dans Profil ; testé avec géographie de debug EEE | — | dev-flutter, conformite-stores | **oui** | M |
| T20 | à faire | Bannières | Bannière sur l'accueil et les résultats | ID de test en dev, ID réels injectés par `--dart-define` (jamais dans le dépôt) ; aucune bannière pendant un quiz | T19 | dev-flutter, relecteur-code | non | S |
| T21 | à faire | Interstitiel plafonné | Interstitiel entre deux quiz, jamais pendant | Règle de fréquence testée (ex. 1 tous les 2 quiz, 1 toutes les 3 min max) dans une classe pure + tests ; préchargement | T19 | dev-flutter | non | M |
| T22 | à faire | Pub récompensée → gel | Gel de série obtenu volontairement | Bouton sur l'écran Série ; RPC serveur qui accorde le gel (max 2 en réserve, plafond/jour) ; pas de gel accordé si la pub n'est pas terminée | T19, T10 | dev-flutter | **oui** | M |
| T23 | à faire | Achat « sans pub » **[MH si l'écran est visible]** | Retirer les pubs contre paiement | Achat + **restauration** (exigée par Apple) ; prix localisé du store ; statut connu du serveur (1 gel offert/semaine) ; pubs coupées ; testé en sandbox iOS et licence de test Google | T8, T18 | dev-flutter, conformite-stores | **oui** | L |

## Étape 4 — Tests et publication

| # | Statut | Tâche | Objectif | Livrable / critère de fin | Dépend de | Agent(s) | Sécu | Taille |
|---|---|---|---|---|---|---|---|---|
| T24 | à faire | Analytics + plantages | Mesurer rétention et plantages pendant le test fermé | ADR courte (D2) ; SDK branché après consentement, événements limités (quiz_start, quiz_end, streak_day, purchase) ; rapports de plantage | D2, T19 | dev-flutter, conformite-stores | **oui** | M |
| T25 | à faire | Documents légaux **[MH]** | Politique de confidentialité, mentions, page de suppression | Pages hébergées (URL stable) : données collectées, Supabase Paris + CLOUD Act, AdMob/UMP, classement public (pseudo + XP de la semaine), durée de conservation, contact | T13, T19 | conformite-stores | non | M |
| T26 | à faire | Prod Supabase + build release **[MH]** | Environnement prêt pour des testeurs | Projet en **Pro** ; `config/prod.json` (hors dépôt) ; réglages Auth prod vérifiés ; signature Android (keystore hors dépôt) et iOS ; `./tool/check_config.sh` OK | T8 | dev-flutter, securite | **oui** | M |
| T27 | à faire | Audit pré-soumission **[MH]** | Rien qui fasse rejeter | Rapport `conformite-stores` : App Privacy (Apple), Data safety (Google), classification d'âge (nouveau questionnaire Apple), privacy manifest, login 4.8, 5.1.1(v), restauration d'achat, pubs/enfants ; points bloquants corrigés | T13, T19, T23, T25 | conformite-stores, securite | **oui** | M |
| T28 | à faire | Fiches stores **[MH]** | Icône, captures, textes, mots-clés | Icônes finales, captures iPhone/Android, textes FR, mots-clés ASO ; vérification d'antériorité de la marque « Quizzéo » faite | — (peut démarrer tôt) | marketing-design, conformite-stores | non | M |
| T29 | à faire | TestFlight + test fermé Google **[MH]** | Satisfaire la règle Google (compte personnel) et corriger les retours | Build sur TestFlight ; test fermé Google avec **≥ 12 testeurs inscrits sans interruption pendant 14 jours** ; retours triés en tâches | T26, T27 (recrutement des testeurs dès maintenant) | dev-flutter, conformite-stores | non | L (≥ 14 jours calendaires) |
| T42 | à faire | Défi n° 1 = jour de publication **[MH]** | Le défi n° 1 tombe le jour de sortie (décision top 3 n° 3) | `challengeStartDay` (`lib/share/share_content.dart`, provisoire au 2026-12-01) fixé à la date de sortie (D10), TODO retiré, `test/share_test.dart` à jour ; inclus dans le build soumis en revue | D10, T29 | dev-flutter | non | S |
| T30 | à faire | Publication | Sortie simultanée iOS + Android | Demande d'accès production Google acceptée ; revue Apple passée ; sortie programmée le même jour (celui de T42) | T29, T42 | conformite-stores | non | M |

## Étape 5 — TikTok (en parallèle, dès maintenant)

| # | Statut | Tâche | Objectif | Livrable / critère de fin | Dépend de | Agent(s) | Sécu | Taille |
|---|---|---|---|---|---|---|---|---|
| T31 | à faire | Lancer TikTok « Tu as X/10 ? » | Construire une audience avant la sortie | Compte créé (nom réservé aussi sur Instagram) ; 10 scripts prêts ; rythme tenu de 3 vidéos/semaine pendant 4 semaines ; questions tirées du **lot hors ligne ou de questions retirées**, jamais du lot serveur actif | — | scripts-tiktok, marketing-design | non | M (continu) |

## Après publication (nice to have)

- [ ] T32 Changement de pseudo avec modération (liste de mots interdits + signalement) — dev-flutter, **Sécu**, M
- [ ] T33 Classement en cache (table remplie par pg_cron) quand `quiz_results` grossit — dev-flutter, **Sécu**, S
- [ ] T34 Classement entre amis (code d'invitation) — dev-flutter, **Sécu**, L
- [ ] T35 Ligues de 30 (montée/descente, reset le lundi) — dev-flutter, **Sécu**, L
- [ ] T36 Badges — dev-flutter, marketing-design, M
- [ ] T37 App Attest / Play Integrity si la triche devient réelle — dev-flutter, **Sécu**, L

Priorité juste après la sortie (avant, l'agrégat n'a pas de sens : ~15 testeurs en test fermé) :

| # | Statut | Tâche | Objectif | Livrable / critère de fin | Dépend de | Agent(s) | Sécu | Taille |
|---|---|---|---|---|---|---|---|---|
| T43 | à faire | « Tu fais mieux que X % des joueurs » | Comparaison sociale sur le défi du jour (top 3 n° 1, 2e temps) | RPC agrégée sur `quiz_results` du jour (Europe/Paris), défi du jour seulement ; rien affiché sous le seuil (D9) ; une ligne sur l'écran Résultats, jamais de donnée individuelle ; tests pgTAP + widget | T30, D9 | dev-flutter, securite | **oui** | M |
| T44 | à faire | % de joueurs par réponse (défi du jour) | Montrer la répartition des réponses après chaque question | Répartition renvoyée seulement après la réponse du joueur, même seuil que T43 ; tests | T43 | dev-flutter, securite | **oui** | M |

## Ordre recommandé et parallélisme

Piste **dev** (séquentielle, une PR à la fois) :
1. T11 → T9 → T39 + T40 (petits correctifs, sans dépendance externe ; T10 fait)
2. T19 → T20 → T21 → T22 (pubs avec ID de test : ne demandent pas encore les comptes store, utile si T8 traîne)
3. T12 → T13 (dès que le compte Apple est actif)
4. T14 → T15 → T38 (T38 dès que T16 atteint 500)
5. T18 → T23 (achat, comptes store requis)
6. T24 → T26 → T27 → T29 → T42 → T30
7. Après la sortie : T43 → T44

Pistes **en parallèle** dès maintenant :
- **Admin (Fares)** : T8 tout de suite ; recruter 15-20 testeurs Android (marge au-dessus de 12) pendant les étapes 2-3.
- **Contenu** : T16 en continu (1 lot par semaine environ), puis T17 ; prochain lot : C2. Le classement ne s'ouvre pas au public avant 500+ questions. T41 (tri des signalements) chaque semaine.
- **Marketing** : T28 (icône, captures provisoires, marque) et T31 TikTok.
- **Légal** : T25 dès que T13 et T19 sont définis.

Compter au moins **3 semaines** entre le début de T29 et la sortie (14 jours de test fermé + délais de revue).

## Bloquant pour la publication (must-have)

- Comptes développeur actifs, contrats de paiement signés (T8).
- Suppression de compte dans l'app + révocation Sign in with Apple + lien web de suppression pour Google Play (T13).
- Consentement UMP avant toute pub personnalisée, ATT sur iOS (T19).
- Achat « sans pub » fonctionnel avec restauration, ou écran « sans pub » retiré de la version publiée (T23).
- Politique de confidentialité en ligne, App Privacy, Data safety, classification d'âge (T25, T27).
- Supabase en Pro, build release signé, aucune clé dans le dépôt (T26).
- Test fermé Google : 12 testeurs × 14 jours (T29).
- Défi n° 1 calé sur le jour de sortie (T42).
- Pas de perte de série (T10, fait), bonus rapidité juste en 4G (T11), anti-abus minimal (T14), masquage des tricheurs (T15), 500+ questions serveur ou classement masqué (T16).
- Fiches stores complètes (T28).

Fortement recommandé mais non bloquant côté stores : liaison Apple/Google (T12), analytics + plantages (T24), lot hors ligne dédié (T17).

Nice to have : T9, T39, T40, T32 à T37, T43, T44.

## Décisions ouvertes

| # | Décision | À trancher avant | Recommandation |
|---|---|---|---|
| D1 | « Sans pub » : achat unique ou abonnement, prix ; RevenueCat ou natif | T18 (début étape 3) | **Achat unique non consommable**, palier ~3,99 € (à confirmer dans T18). **RevenueCat** : gratuit jusqu'à 2 500 $ de revenu mensuel suivi, puis 1 % ; donne le statut côté serveur (webhook) pour le gel hebdo, sans valider les reçus soi-même. |
| D2 | Analytics : PostHog (UE) ou Firebase Analytics | T24 (avant le test fermé) | **PostHog UE**, déjà recommandé par l'ADR 0001 (données en UE, pas de SDK Firebase en plus) ; plantages : Sentry (UE) ou Crashlytics seul. |
| D3 | Connexions proposées | T12 | **Apple sur iOS, Google sur iOS + Android**, en liaison du compte anonyme (jamais obligatoire pour jouer). Sign in with Apple sur Android non (flux web, peu utile). |
| D4 | CAPTCHA sur la connexion anonyme | T14 | **Limites de débit + purge d'abord** ; CAPTCHA (Turnstile/hCaptcha, nécessite une vue web dans Flutter) seulement si des abus apparaissent. |
| D5 | Compte Google Play : personnel ou organisation | T8 (maintenant) | **Personnel** sauf structure existante avec numéro D-U-N-S ; accepter le test fermé 12 × 14 j et recruter tôt. |
| D6 | Classement public au lancement | T30 | Ouvert **seulement si 500+ questions serveur** et T15 fait ; sinon onglet masqué ou « bientôt ». |
| D7 | Marque « Quizzéo » | T28 | Recherche d'antériorité INPI/EUIPO (classes 9 et 41) avant de payer les visuels définitifs ; dépôt si la voie est libre. |
| D8 | Ligues et badges | après publication | Repoussés après la sortie (T35, T36) ; CLAUDE.md mis à jour. |
| D9 | Seuil et forme de la comparaison sociale (« mieux que X % ») | T43 | **Défi du jour seulement**, affiché à partir de **50 joueurs** ce jour-là, arrondi à 5 % ; jamais sur les quiz libres. |
| D10 | Date de sortie (= défi n° 1) | T42 | Fixer la date une fois T29 lancé (≥ 3 semaines avant), plutôt un lundi ou mardi pour profiter de la semaine TikTok. |

Décisions prises par Fares le 2026-11-26 (top 3 de différenciation, numérotées D1–D4 dans les échanges, distinctes des D ci-dessus) : signalement par **4 motifs fixes sans texte libre** ; champ **`source` court, sans URL** ; **défi n° 1 = jour de publication** (`challengeStartDay` provisoire, voir T42) ; **non-répétition en étape 2 après 500+ questions** (T38). À reporter dans « Décisions prises » de `CLAUDE.md`.

## Comment tenir ce plan à jour

- Une tâche = une branche (`feat/…`, `content/…`, `docs/…`) = une PR. Pas de merge automatique.
- Dans la PR qui termine une tâche : passer sa colonne **Statut** de « à faire » à « fait (PR #18) » (ou « en cours (PR #18) » à l'ouverture de la PR) ; pour les listes à cases, cocher `- [x]` et ajouter le lien de la PR.
- Nouvelle tâche : prendre le numéro suivant libre (T38…), ne jamais renuméroter.
- Décision tranchée : la retirer du tableau « Décisions ouvertes », l'ajouter dans « Décisions prises » de `CLAUDE.md` (avec la date) et, si elle est structurante, écrire un ADR dans `docs/decisions/`.
- Mettre à jour le **Statut global** (date, étape en cours) à chaque fin d'étape.

## Sources (consultées le 2026-11-26)

- Google Play, test fermé pour les nouveaux comptes personnels (12 testeurs, 14 jours) : https://support.google.com/googleplay/android-developer/answer/14151465
- Google Play, suppression de compte (lien web exigé) : https://support.google.com/googleplay/android-developer/answer/13327111
- Apple, suppression de compte 5.1.1(v) : https://developer.apple.com/help/app-review/guideline-reference/5-1-1-account-deletion , https://developer.apple.com/support/offering-account-deletion-in-your-app
- Apple TN3194, révocation des jetons Sign in with Apple : https://developer.apple.com/documentation/technotes/tn3194-handling-account-deletions-and-revoking-tokens-for-sign-in-with-apple
- Apple, nouveau questionnaire de classification d'âge (13+/16+/18+) : https://developer.apple.com/news/?id=ks775ehf
- AdMob Flutter, message IDFA / ATT via UMP : https://developers.google.com/admob/flutter/privacy/idfa
- Tarifs RevenueCat : https://www.revenuecat.com/pricing
