# ADR 0001 — Back-end de l'étape 2 : Supabase ou Firebase

- Statut : **proposé** (à valider par Fares)
- Date : 2026-11-26
- Portée : comptes, classement hebdo, synchronisation de la progression, questions distantes, défi du jour

## Contexte

L'étape 1 est terminée : quiz local, XP/niveaux, série + gels, défi du jour déterministe (graine = date, sur la liste locale), sons, rappel local, partage en image. La progression est dans `shared_preferences` (`ProgressRepository`), les questions dans `assets/questions.json` (`QuestionRepository`). Le classement est fictif (`LeaderboardScreen`).

L'étape 2 doit apporter :
- comptes **anonymes d'abord**, puis liaison Apple / Google (Sign in with Apple obligatoire sur iOS si Google est proposé) et **suppression de compte dans l'app** (App Store 5.1.1(v), avec révocation du jeton Apple) ;
- classement hebdo global + amis, puis ligues de 30 (montée/descente) à l'étape suivante ;
- score/XP validés côté serveur (anti-triche raisonnable) ;
- 500+ questions mises à jour sans republier, défi du jour identique pour tous ;
- progression (XP, série, gels) synchronisée entre appareils ;
- données hébergées en UE, DPA signé ; peu de maintenance (dev solo, revenus passifs).

Contraintes déjà connues : AdMob (SDK Google de toute façon), analytics à choisir (PostHog ou Firebase Analytics), achat « sans pub » (RevenueCat ou natif), push éventuel plus tard.

## Options

1. **Supabase** (Postgres managé, Auth, Edge Functions Deno, Cron/pg_cron, région Paris `eu-west-3`).
2. **Firebase** (Auth, Firestore, Cloud Functions Node/TS, App Check, région `europe-west9` Paris ou `eur3`).

Écartés : back-end maison (Node + Postgres sur VPS : trop de maintenance), Firebase Data Connect (Postgres chez Google : plus jeune, moins de recul côté Flutter, coût Cloud SQL fixe).

## Comparaison

| Critère | Supabase | Firebase |
|---|---|---|
| Comptes anonymes puis Apple/Google | `signInAnonymously` puis `linkIdentityWithIdToken` (Apple/Google natifs). OK. | `signInAnonymously` puis `linkWithCredential`. OK, très éprouvé. |
| Suppression de compte + révocation Apple | Edge Function à écrire (échange du code Apple, `/auth/revoke`, suppression des données puis de l'utilisateur). | `revokeTokenWithAuthorizationCode` côté client (iOS ; code souvent nul sur Android) + suppression ; Cloud Function pour purger les données. Un peu plus simple. |
| Classement hebdo global/amis | SQL : vue ou table `weekly_scores`, `rank()`, jointure sur `friends`. 1 requête = 1 appel, pas de coût à la lecture. | Pas de rang natif : agrégats `count()` + document « top 100 » dénormalisé par fonction planifiée. Coût par document lu. |
| Ligues de 30, montée/descente, reset hebdo | Une fonction SQL lancée par Cron le lundi (regroupement, montée/descente). Naturel. | Fonction planifiée qui lit/écrit tous les membres ; modélisation dénormalisée, transactions. Faisable mais plus de code. |
| Anti-triche | Fonction Postgres `submit_quiz()` (security definer) : recalcule score/XP depuis les réponses et les temps ; RLS interdit l'écriture directe. Pas d'équivalent App Check (seulement captcha + limites de débit). | Cloud Function callable qui recalcule ; Security Rules interdisent l'écriture directe ; **App Check** (App Attest / Play Integrity) bloque les clients non officiels. Avantage Firebase. |
| Questions distantes + défi du jour | Table `questions` + table `daily_challenges(day, question_ids)` remplie par Cron ; le client met en cache et ne télécharge que le delta (`updated_at`). | Collection `questions` (lectures facturées, cache local) ou fichier JSON dans Storage + doc `daily_challenges/{day}`. |
| Sync progression multi-appareils | Ligne `profiles` (XP, série, gels) écrite via RPC ; pas de mode hors ligne intégré (on garde `shared_preferences` comme cache). | Persistance hors ligne Firestore intégrée : sync gratuite à coder. Avantage Firebase. |
| SDK Flutter | `supabase_flutter` 2.x officiel, maintenu. | FlutterFire officiel Google, très mature. |
| AdMob / analytics / achats / push | Indépendant : PostHog (hébergement UE), RevenueCat, FCM utilisable seul plus tard. | Firebase Analytics lié à AdMob (pratique) ; Crashlytics ; FCM natif. Avantage Firebase. |
| RGPD | Région Paris ou Francfort, DPA disponible ; société US (CLOUD Act). | Régions UE disponibles, DPA Google Cloud ; société US ; Firebase Analytics/Auth traitent une partie hors UE. |
| Verrouillage | Faible : Postgres standard, auto-hébergeable, export `pg_dump`. | Fort : modèle Firestore + Rules propriétaires. |
| Coût de départ | Plan Free inutilisable en prod (pause après 1 semaine d'inactivité) → **Pro 25 $/mois** dès le test fermé. | **0 $** sur Blaze tant qu'on reste dans les quotas gratuits (carte bancaire requise). |
| Maintenance | Migrations SQL versionnées, montée de version Postgres de temps en temps. | Montée de version Node des fonctions tous les 2-3 ans, index Firestore. |
| Expérience du dev (React/Node/SQL) | SQL + TypeScript (Deno). Familier. | TypeScript (Node). Familier ; modélisation NoSQL à apprendre pour les ligues. |

### Coût estimé (USD/mois, hors AdMob/RevenueCat)

Hypothèses par joueur actif/mois : 20 quiz terminés, 8 ouvertures du classement, 15 lancements de l'app.
- Firebase : ~600 lectures (dont ~400 pour le classement si on lit 50 lignes à chaque fois), ~40 écritures, ~20 appels de fonction. Lectures/écritures Standard ≈ 0,03 $ / 0,09 $ les 100 000 (tarif `eur3`/us-central1 ; à confirmer pour Paris). Auth gratuit sans passer à Identity Platform.
- Supabase : Pro 25 $ incluant 100 000 MAU, 8 Go de base, 250 Go de sortie, 2 M d'invocations d'Edge Functions ; le score passe par une fonction SQL (pas d'Edge Function), donc quasi rien d'autre.

| Joueurs actifs/mois | Supabase | Firebase |
|---|---|---|
| 1 000 | 25 $ (Pro, calcul Micro couvert par le crédit) | 0 $ (≈ 20 000 lectures/jour < 50 000 gratuites) |
| 10 000 | 25 $ | ≈ 2-5 $ (≈ 200 000 lectures/jour) |
| 100 000 | ≈ 40-50 $ (Pro + calcul Small 15 $, éventuel dépassement) | ≈ 20-50 $ (≈ 60 M lectures/mois ; ≈ 5-10 $ si le top 100 est un seul document mis en cache) |

À ces volumes, les deux restent négligeables face aux revenus pub attendus. L'écart de coût n'est pas décisif ; ce qui compte est l'effort sur le classement/les ligues et la maintenance.

## Décision recommandée

**Supabase, région Paris (`eu-west-3`), plan Free pendant le développement puis Pro (25 $/mois) dès le test fermé.**

Raisons :
1. Classement hebdo, amis et surtout ligues de 30 sont des problèmes relationnels : quelques requêtes et une fonction SQL planifiée, au lieu de dénormalisation et de fonctions planifiées coûteuses en lectures.
2. Anti-triche simple : une seule fonction Postgres `submit_quiz()` recalcule score et XP avec les règles validées ; RLS interdit toute autre écriture. Pas de serveur à maintenir.
3. Coût fixe et prévisible (pas de facture surprise à la lecture si un écran est mal mis en cache).
4. Données en France, DPA disponible ; Postgres standard = sortie possible (auto-hébergement, autre hébergeur Postgres).
5. Correspond aux compétences du dev (SQL, TypeScript).

Analytics : PostHog (instance UE) plutôt que Firebase Analytics, pour garder une seule logique « données en UE » ; Crashlytics reste possible seul (projet Firebase sans Firestore) si besoin de rapports de plantage.

## Conséquences

- Nouveau dossier `supabase/` (migrations SQL, fonctions, `config.toml`) versionné ; aucune clé dans le dépôt (clé `anon` injectée par `--dart-define`, clé `service_role` uniquement côté serveur).
- `ProgressRepository` et `QuestionRepository` deviennent des interfaces avec une implémentation locale (cache) et une implémentation Supabase ; l'app reste jouable hors ligne, la sync se fait en fin de quiz et au lancement.
- Le défi du jour n'est plus calculé sur la liste locale (qui va changer avec les mises à jour) : le serveur publie `daily_challenges(day, question_ids)` ; le calcul local actuel reste en secours hors ligne.
- Le score « officiel » (classement) est celui renvoyé par `submit_quiz()` ; le client garde son calcul pour l'affichage immédiat.
- Fonction `delete_account` (Edge Function) obligatoire avant la soumission iOS.
- Coût fixe de 25 $/mois à partir du test fermé.

## Risques et parades

- **Pas d'App Check** : un client modifié peut appeler `submit_quiz()`. Parades : temps de réponse plausibles (≥ 1 s, ≤ 30 s), plafond de quiz comptés par jour, réponses vérifiées côté serveur, signalement/masquage manuel des scores aberrants. Si la triche devient réelle : ajouter une vérification Play Integrity / App Attest dans une Edge Function (plus de travail qu'avec Firebase).
- **Projet Free en pause** pendant le dev s'il n'y a pas d'activité pendant 7 jours : sans gravité en dev, passer en Pro avant les testeurs.
- **Comptes anonymes comptés en MAU** et création abusive : activer les limites de débit et nettoyer les anonymes inactifs (Cron).
- **Révocation Apple** : nécessite de stocker le code/jeton de rafraîchissement Apple à la connexion ; à tester tôt (cause fréquente de rejet).
- **Société US** (CLOUD Act) pour les deux options : à mentionner dans la politique de confidentialité ; données minimales (pseudo, scores, pas d'e-mail affiché).

## Ce qui ferait changer d'avis (vers Firebase)

- Refus d'un coût fixe de 25 $/mois avant les premiers revenus.
- Triche jugée critique dès le lancement (App Check clé en main).
- Choix de Firebase Analytics + Crashlytics + FCM comme socle de toute façon.
- Besoin fort de jeu hors ligne multi-appareils avec fusion automatique.

## Sources (consultées le 2026-11-26)

- Tarifs Supabase : https://supabase.com/pricing.md
- Régions Supabase : https://supabase.com/docs/guides/platform/regions
- RGPD / DPA Supabase : https://supabase.com/docs/guides/security/gdpr-compliance , https://supabase.com/legal/customer-resources/data-processing-addendum
- Supabase Cron : https://supabase.com/docs/guides/cron
- Supabase Dart `linkIdentityWithIdToken` : https://supabase.com/docs/reference/dart/auth-linkidentitywithidtoken
- Supabase Sign in with Apple : https://supabase.com/docs/guides/auth/social-login/auth-apple.md
- Tarifs Firebase : https://firebase.google.com/pricing
- Tarifs Firestore (quotas gratuits, agrégats) : https://firebase.google.com/docs/firestore/pricing , https://cloud.google.com/firestore/pricing
- Cloud Functions (2 M invocations gratuites/mois) : https://cloud.google.com/functions/pricing-1stgen , https://firebase.google.com/docs/functions/faq-and-troubleshooting
- Firebase Auth / Identity Platform : https://firebase.google.com/docs/auth , https://cloud.google.com/identity-platform/pricing
- FlutterFire `revokeTokenWithAuthorizationCode` : https://pub.dev/documentation/firebase_auth/latest/firebase_auth/FirebaseAuth/revokeTokenWithAuthorizationCode.html ; code nul sur Android : https://github.com/firebase/flutterfire/discussions/12779
- Apple, suppression de compte 5.1.1(v) : https://developer.apple.com/support/offering-account-deletion-in-your-app ; TN3194 révocation : https://developer.apple.com/documentation/technotes/tn3194-handling-account-deletions-and-revoking-tokens-for-sign-in-with-apple

Les montants sont indicatifs (tarifs publics à la date ci-dessus, hypothèses d'usage ci-dessus) et à revérifier avant le passage en Pro.
