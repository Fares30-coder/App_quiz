# Stratégie produit — Quizzéo

Date : 2026-11-26 · Auteur : agent `strategie-produit` · Base : `marketing/concurrence.md`

## 1. Positionnement proposé
> **Le quiz de culture G en français, fiable et respectueux : 10 questions vérifiées par jour, les mêmes pour tous, sans pub pendant le jeu.**

Les leaders (QuizzLand, Trivia Crack, Quiz Planet, DuelQuiz) gagnent sur le volume et le social, et perdent sur trois points cités sans cesse dans les avis : **pubs envahissantes** (même après achat), **questions fausses ou répétées**, **contenu pas vraiment français**. Un dev solo ne battra pas leur volume ; il peut battre leur qualité et leur respect du joueur, et occuper le créneau « rituel quotidien » façon Wordle, que les apps FR exploitent peu.

## 2. Existant (état du code au 2026-11-26)
Déjà en place : défi du jour serveur, série + gel, XP/niveaux, objectif, rappel, classement hebdo, partage image 9:16 (score + série, avec la suite de réponses), temps mesuré serveur, questions servies par le serveur (70 dans `supabase/questions/questions.json`). Absent : signalement de question, partage texte sans spoiler, comparaison aux autres joueurs, source dans l'explication.

## 3. Angles de différenciation

Pondération : rétention 30 %, viralité 20 %, revenus 15 %, différenciation 15 %, effort 20 % (5 = très facile) ; risque en malus : − 0,2 × (risque − 1), risque 1 = faible, 5 = élevé. Notes = jugement de l'agent (hypothèses), à recalibrer avec les données PostHog/Firebase.

| # | Angle | Rét. | Viral. | Rev. | Diff. | Effort | Risque | Score |
|---|---|---|---|---|---|---|---|---|
| A | Défi du jour = rituel commun partageable (grille texte sans spoiler + « tu fais mieux que X % ») | 4 | 5 | 3 | 3 | 4 | 1 | **3,90** |
| B | Questions fiables : source dans l'explication + bouton « Signaler » + pas de répétition récente | 3 | 2 | 2 | 4 | 5 | 1 | **3,20** |
| C | Ancrage francophone (références FR/BE/CH/QC, ton complice, actu FR) | 3 | 4 | 2 | 4 | 3 | 1 | **3,20** |
| D | Pubs respectueuses garanties (promesse affichée, « sans pub » = zéro pub imposée) | 3 | 2 | 3 | 4 | 4 | 1 | **3,15** |
| E | Défi asynchrone entre amis « Bats mon score » (lien vers les mêmes 10 questions) | 4 | 5 | 3 | 3 | 2 | 3 | **3,10** |
| F | Carnet de révision (questions ratées rejouables, « le saviez-vous ») | 3 | 1 | 2 | 3 | 3 | 1 | **2,45** |

### A. Rituel du défi du jour partageable
- **Pour** : mécanique Wordle prouvée (même puzzle pour tous + partage sans spoiler) ; alimente TikTok « Tu as X/10 ? » ; renforce la série (Duolingo : 7 jours de série ⇒ 2,4× plus de retour le lendemain) ; base déjà codée.
- **Contre** : le % de joueurs demande un agrégat serveur (petite fonction SQL) ; avec peu de joueurs au lancement, le % est peu parlant (afficher seulement au-delà d'un seuil, ex. 50 joueurs — hypothèse).
- **Concurrents** : Quiz Planet a un quotidien « contre ton pays » et le % par réponse (apprécié dans les avis) ; DuelQuiz a des quiz mensuels. Aucun ne propose un partage texte sans spoiler.
- **Version minimale (1 PR)** : ajouter au texte partagé une grille `Quizzéo · Défi n° 42 · 8/10` + `🟩🟩🟥🟩…` + 🔥 série. Puis (2e PR, Étape 2) : « Tu fais mieux que 63 % des joueurs aujourd'hui » via un agrégat sur les soumissions du jour.
- **Indicateur** : part des défis terminés qui sont partagés ; rétention J7.

### B. Questions fiables et signalables
- **Pour** : répond à la plainte n° 2 du marché ; cohérent avec « relues à la main » ; le signalement améliore la base gratuitement ; argument ASO (« questions vérifiées »).
- **Contre** : il faut traiter les signalements (charge faible si ≤ quelques/jour, hypothèse) ; afficher une source impose de la stocker pour chaque question (champ en plus pour `redacteur-questions`).
- **Concurrents** : QuizzLand retire les questions après N signalements mais son contenu est créé par les joueurs ; Culture G cite Wikipédia (apprécié).
- **Version minimale (1 PR)** : bouton « Signaler » sur la feuille d'explication → table `question_reports` (RLS : insertion par l'utilisateur connecté, 1 par question) ; exclure les questions vues dans les 30 derniers jours (hypothèse de durée) quand la base le permet.
- **Indicateur** : taux de signalement par question ; nb de questions corrigées.

### C. Ancrage francophone
- **Pour** : Trivia Crack sert des questions en anglais aux FR ; les références locales (Tour de France, chanson française, géo des régions) font des vidéos TikTok plus « relatables » ; coût = rédaction, pas de code.
- **Contre** : limite l'international (non visé au MVP) ; l'actu vieillit vite (questions datées à prévoir).
- **Version minimale** : consigne pour `redacteur-questions` : environ 30 % de questions à ancrage francophone (hypothèse) + charte de ton § 4.
- **Indicateur** : taux de bonnes réponses et de partage par question « FR » vs générale.

### D. Pubs respectueuses comme promesse
- **Pour** : plainte n° 1 de tous les leaders ; déjà décidé dans CLAUDE.md, donc coût surtout marketing (fiche store, écran « sans pub ») ; augmente la confiance avant l'achat.
- **Contre** : moins d'impressions qu'un concurrent agressif (revenu/joueur plus faible, compensé si la rétention suit — hypothèse) ; la promesse doit être tenue à 100 %.
- **Version minimale** : texte sur l'écran « sans pub » et la fiche store : « Jamais de pub pendant un quiz. Avec l'option sans pub : plus aucune pub imposée. » Vérifier que l'achat coupe bannière + interstitiel.
- **Indicateur** : notes store mentionnant les pubs ; conversion « sans pub ».

### E. Défi entre amis asynchrone
- **Pour** : boucle virale forte (lien dans le partage) ; pas de temps réel ni de chat (pas de toxicité comme DuelQuiz).
- **Contre** : liens profonds iOS/Android, gestion de l'installation différée, anti-triche du lien ; c'est presque du multijoueur. Le défi du jour couvre déjà 80 % de l'effet (même quiz pour tous).
- **Verdict** : Étape 2 (après les ligues), si le partage du défi du jour marche.

### F. Carnet de révision
- **Pour** : angle « j'apprends », bon pour les 25-35 ans.
- **Contre** : faible viralité ; demande beaucoup de contenu pour ne pas tourner en boucle.
- **Verdict** : Plus tard.

## 4. Top 3 recommandé

| Rang | Angle | Verdict | Raison |
|---|---|---|---|
| 1 | A. Rituel du défi du jour partageable | **Maintenant (MVP)** pour la grille texte ; **Étape 2** pour le % de joueurs | Meilleur rapport viralité/effort, colle à la stratégie TikTok |
| 2 | B. Questions fiables + Signaler | **Maintenant (MVP)** | Petite PR, répond à une plainte forte, protège les notes store |
| 3 | C. Ancrage francophone | **Maintenant (MVP)**, côté contenu | Pas de code ; différencie face à Trivia Crack et QuizzLand |

D est déjà acté dans CLAUDE.md : à traiter comme **promesse marketing** (agent `marketing-design`), pas comme feature.

## 5. Backlog de features

| Date | Feature | Verdict | Raison |
|---|---|---|---|
| 2026-11-26 | Partage texte sans spoiler du défi du jour (grille + n° du défi) | Maintenant (MVP) | 1 PR dans `lib/share/share_content.dart`, mécanique Wordle prouvée |
| 2026-11-26 | Bouton « Signaler la question » + table serveur | Maintenant (MVP) | Plainte récurrente « questions fausses » chez tous les leaders |
| 2026-11-26 | Source courte dans l'explication | Maintenant (MVP) | Crédibilité, déjà vérifiée par `verificateur-faits` ; champ à ajouter au JSON |
| 2026-11-26 | Consigne ~30 % de questions à ancrage francophone | Maintenant (MVP) | Contenu seulement |
| 2026-11-26 | Promesse « pubs respectueuses » sur fiche store et écran sans pub | Maintenant (MVP) | Décision déjà prise, à rendre visible |
| 2026-11-26 | Une seule demande de note store, après un bon moment | Maintenant (MVP) | Quiz Planet critiqué pour ses relances ; notes = ASO |
| 2026-11-26 | « Tu fais mieux que X % des joueurs » sur le défi du jour | Étape 2 | Agrégat serveur + seuil de joueurs |
| 2026-11-26 | % de joueurs par réponse après chaque question | Étape 2 | Apprécié chez Quiz Planet ; même agrégat que ci-dessus |
| 2026-11-26 | Pas de répétition d'une question vue < 30 jours | Étape 2 | Utile quand la base dépasse 500 questions |
| 2026-11-26 | Défi asynchrone entre amis par lien | Étape 2 | Viral mais liens profonds + anti-triche |
| 2026-11-26 | Carnet de révision des questions ratées | Plus tard | Peu viral |
| 2026-11-26 | Duels temps réel, chat | Non | Hors MVP, modération et coût serveur (cf. QuizUp, DuelQuiz) |
| 2026-11-26 | Questions proposées par les joueurs | Non | Modération lourde ; cause des questions fausses chez QuizzLand |
| 2026-11-26 | Jokers / indices payants, vies | Non | Contraire aux « À éviter » ; pression à l'achat critiquée |

## 6. Décisions qui reviennent à Fares
1. **« Sans pub » : achat unique ou abonnement, et prix.** Repères marché : 2,99–4,99 € en achat unique (voir concurrence § 4). Recommandation : achat unique ~3,99 € (hypothèse).
2. **Afficher une source dans chaque explication** (ajoute un champ au JSON et du travail de rédaction).
3. **Seuil et forme de la comparaison sociale** (« mieux que X % ») : à partir de combien de joueurs l'afficher, et sur le défi du jour seulement ?
