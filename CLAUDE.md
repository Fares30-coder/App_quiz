# Quizzéo — App de quiz de culture générale

## Projet
App mobile iOS + Android (lancement simultané) de quiz de culture générale, nom retenu : **Quizzéo**.
Revenus : publicités (AdMob) + achat in-app pour supprimer les pubs. Acquisition organique via TikTok.
Développeur : Fares Haouari (full stack, à l'aise en React/Node/Flutter). Projet perso de revenus passifs.

## Stack
- Mobile : **Flutter** (une seule base de code iOS + Android), dev sous VS Code, Mac
- Back-end : **Supabase** région Paris (auth, questions, classement) — voir `docs/decisions/0001-backend.md`
- Pubs : Google AdMob (`google_mobile_ads`) + consentement UMP (RGPD) + ATT sur iOS
- Achat "sans pub" : RevenueCat ou achats natifs (StoreKit / Play Billing)
- Analytics : PostHog ou Firebase Analytics

## Fonctionnalités MVP
- Quiz de 10 questions (QCM, 4 choix), 30 s par question
- Catégories : histoire, géo, sciences, arts, sport, actu, divers
- Défi du jour (même quiz pour tous) + série de jours consécutifs (streak)
- Score, explication courte après chaque réponse, partage du résultat en image (TikTok/Stories)
- Classement hebdo (amis ou global)
- Tout le contenu est gratuit, avec pubs

## Engagement (mécaniques inspirées de Duolingo, sans copier son apparence)
MVP :
- Série renforcée : flamme visible, animation de validation du jour, gel de série (obtenu via pub récompensée)
- XP et niveaux : XP par bonne réponse + bonus rapidité + combo de bonnes réponses d'affilée
- Objectif du jour (1, 2 ou 3 quiz) choisi au premier lancement, jauge sur l'accueil
- Retours satisfaisants : sons, vibrations, confettis à 10/10, animation du score
- Un seul rappel quotidien (notification locale) à l'heure choisie
Règles validées :
- XP : +10 bonne réponse, +5 si réponse en moins de 10 s, +5 par bonne réponse à partir du combo x3, +20 quiz terminé, +30 sans-faute
- Niveaux : 100 + 50 × (n − 1) XP pour passer du niveau n au suivant
- Gel de série : 2 en réserve max, 1 gel protège 1 jour ; 1 quiz suffit pour valider la journée ; joueurs « sans pub » : 1 gel offert par semaine
- Sons activés par défaut, coupés en mode silencieux (session audio ambient sur iOS)
- Premier lancement : objectif 2 quiz/jour et rappel à 20 h 30 proposés par défaut
- Maquettes et composants : `design/maquettes/`, `design/charte.md` (§ 7 bis Engagement)
Après publication : ligues hebdo (groupes de 30, montée/descente), badges (voir `docs/plan.md`, T35-T36).
À éviter : vies qui bloquent le jeu, notifications culpabilisantes ou trop fréquentes.

## Monétisation
- Bannière sur l'accueil et les résultats ; interstitiel entre deux quiz, jamais pendant un quiz, fréquence plafonnée
- Pub récompensée facultative (choisie par le joueur) pour obtenir un gel de série
- Option "Supprimer les pubs" (achat unique ou abonnement : à trancher, prix à définir)
- Consentement avant toute pub personnalisée

## Contenu
- 500+ questions au lancement, générées puis relues à la main (faits vérifiés)
- Champs : question, 4 réponses, bonne réponse, explication, catégorie, difficulté
- Questions servies par le serveur : `supabase/questions/questions.json` uniquement, jamais dans `assets/` ; `assets/questions.json` = lot hors ligne, jamais servi (anti-triche)

## Hors MVP
Multijoueur temps réel, notifications avancées, contenus par niveau scolaire.

## Étapes prévues
1. Scaffold Flutter + quiz local (questions en JSON)
2. Back-end + comptes + classement
3. AdMob + consentement + achat "sans pub"
4. TestFlight (iOS) et test fermé Google Play (Android), puis publication
5. TikTok : démarrer dès l'étape 1 (vidéos "Tu as X/10 ?")

## Décisions prises
- Pas d'abonnement classique : pubs + option payante pour les retirer
- iOS + Android en même temps
- Flutter retenu (React Native/Expo écarté après comparaison)
- État : Riverpod (`flutter_riverpod`)
- Nom Quizzéo gardé malgré des noms proches (Quizeo.ai, Qizeo) : risque de marque à garder en tête
- Back-end : Supabase (Paris, `eu-west-3`), plan Free en dev puis Pro (25 $/mois) dès le test fermé ; Firebase et Scaleway écartés (ADR 0001)

## Questions ouvertes
- "Sans pub" : achat unique ou abonnement, et prix
- Analytics : PostHog (UE) ou Firebase Analytics
- Google Play : un compte personnel récent exige en général un test fermé avant publication (vérifier les conditions actuelles)

## Conventions de travail
- Répondre en français, de façon courte et directe ; ne développer que sur demande
- Architecture simple et lisible, état géré avec un seul outil (Riverpod ou Provider)
- Ne jamais mettre de clés ou secrets dans le dépôt
- Utiliser les ID de test AdMob en développement
- Le cahier des charges complet est dans le projet claude.ai "quiz culture G" (`cahier-des-charges-mvp.md`)
- Plan des tâches (numérotées T1, T2…, statut, dépendances, décisions ouvertes) : `docs/plan.md`, source unique à mettre à jour dans chaque PR
