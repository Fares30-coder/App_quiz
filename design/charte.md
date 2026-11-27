# Charte de marque — Quizzéo

Version 1 · 25 nov. 2026. Source de vérité pour les maquettes (`design/maquettes/`), le `ThemeData` Flutter et les visuels marketing.

## 1. Idée de marque

**Promesse :** « 10 questions, 5 minutes, et tu sais ce que tu vaux. »
**Personnalité :** vive, chaleureuse, un peu taquine, jamais condescendante. Une culture G de comptoir sympa, pas un examen.
**Signature visuelle :** le **é** corail. C'est l'élément qui distingue Quizzéo : on ne construit pas l'identité sur un « Q ».

### Rester distinct de Quizeo.ai et Qizeo
- **Nom :** toujours écrit `Quizzéo` (deux z, é accentué). Jamais « Quizzeo », « Quizeo » ni « QZ ».
- **Logo :** pas de monogramme « Q », pas de bulle de dialogue, pas d'étincelle « IA », pas de point d'interrogation stylisé. Le symbole est le « é ».
- **Couleurs :** pas de violet ni de dégradé bleu-violet (codes très répandus chez les apps de quiz et les produits IA). Quizzéo utilise un trio **corail / encre / safran** sur fond crème.
- **À vérifier par Fares :** le site quizeo.ai n'était pas joignable et la fiche App Store de Qizeo n'était plus en ligne au moment de la rédaction. Faire une comparaison visuelle rapide avant de figer l'icône.

## 2. Couleurs

Contrastes calculés selon la formule WCAG 2.x. Seuils : texte normal 4,5:1, grand texte (≥ 24 px, ou ≥ 18,7 px en gras) et éléments graphiques 3:1.

### Mode clair

| Rôle | Nom | Hex | Usage | Contraste vérifié |
|---|---|---|---|---|
| Fond | Crème | `#FFF7EE` | fond des écrans | — |
| Surface | Blanc | `#FFFFFF` | cartes, boutons de réponse | — |
| Surface 2 | Sable | `#F6EEE3` | zones secondaires, bannière pub | — |
| Texte | Encre | `#1A1B3A` | titres, texte principal | 15,7 sur crème · 16,6 sur blanc |
| Texte 2 | Encre douce | `#4A4C6B` | sous-titres, légendes | 7,8 sur crème · 8,3 sur blanc |
| Contour | Gris ardoise | `#8A8CA6` | bordures des boutons de réponse | 3,1 sur crème · 3,3 sur blanc (élément graphique) |
| Séparateur | Lin | `#E6DED2` | séparateurs décoratifs seulement | décoratif |
| Primaire | Corail | `#D63A1F` | bouton principal, défi du jour, le « é » | texte blanc dessus : 4,7 |
| Primaire texte | Corail foncé | `#B8301A` | liens et texte corail sur fond clair, état pressé | 5,7 sur crème · 6,0 sur blanc |
| Primaire conteneur | Pêche | `#FFE1D8` | pastilles, fonds doux | texte `#5A1406` : 11,1 |
| Secondaire | Canard | `#0E6E72` | timer (> 10 s), infos, onglet actif | 5,7 sur crème · texte blanc dessus : 6,0 |
| Tertiaire | Safran | `#FFC23D` | série (streak), podium, timer (≤ 10 s) | **remplissage uniquement**, texte encre dessus : 10,3. Jamais en texte sur fond clair (1,6). |
| Safran foncé | Ambre | `#9A6500` | anneau du timer entre 10 et 6 s | 5,0 sur blanc |
| Succès | Vert sapin | `#17784A` | bonne réponse (bordure, pastille) | texte blanc dessus : 5,5 |
| Succès conteneur | Menthe | `#DDF3E6` | fond de la bonne réponse | texte `#0F5C37` : 6,9 |
| Erreur | Rouge grenat | `#C42B3A` | mauvaise réponse | texte blanc dessus : 5,6 |
| Erreur conteneur | Rose pâle | `#FCE3E5` | fond de la mauvaise réponse | texte `#9E1C2A` : 6,5 |

### Mode sombre

| Rôle | Hex | Contraste vérifié |
|---|---|---|
| Fond (Nuit) | `#12132A` | — |
| Surface | `#1E2042` | — |
| Surface 2 | `#2A2C55` | texte `#F5F1EA` : 11,7 · texte 2 : 6,6 |
| Texte | `#F5F1EA` | 16,2 sur fond |
| Texte 2 | `#B4B6D0` | 9,2 sur fond · 7,9 sur surface |
| Contour | `#6E7096` | 3,3 sur surface |
| Séparateur | `#34365E` | décoratif |
| Primaire (Corail clair) | `#FF7A5C` | texte `#12132A` dessus : 7,1 · 6,1 sur surface |
| Primaire conteneur | `#5A1E12` | texte `#FFD9CF` : 9,9 |
| Secondaire (Canard clair) | `#4FC7C9` | 9,0 sur fond |
| Tertiaire (Safran) | `#FFC23D` | 11,3 sur fond |
| Succès | `#5BD69A` | 10,0 sur fond · 8,6 sur surface |
| Succès conteneur | `#0F3A2A` | texte `#5BD69A` : 7,0 |
| Erreur | `#FF8A95` | 8,1 sur fond · 7,0 sur surface |
| Erreur conteneur | `#45161F` | texte `#FF8A95` : 6,7 |

En sombre, le texte posé sur primaire, succès ou erreur est **foncé** (`#12132A`), pas blanc.

### Couleurs de catégories

Fond teinté en clair (texte encre dessus : ≥ 13:1), icône colorée (≥ 4,5:1 sur la teinte). En sombre, la carte reste en surface `#1E2042` avec l'icône en couleur claire (≥ 6,8:1).

| Catégorie | Teinte (clair) | Icône (clair) | Icône (sombre) |
|---|---|---|---|
| Histoire | `#FBE3D3` | `#A3401A` | `#FF9A6B` |
| Géo | `#D8EEF0` | `#0E6E72` | `#4FC7C9` |
| Sciences | `#E3E4FB` | `#3E4BB8` | `#9AA4FF` |
| Arts | `#FBE0EC` | `#B02A6B` | `#FF8AC0` |
| Sport | `#E1F2D5` | `#2F7A1F` | `#8FD66B` |
| Actu | `#FFF0C7` | `#8A5A00` | `#FFC23D` |
| Divers | `#ECE7DF` | `#6B5B45` | `#D2C2A8` |

### Règles
- La couleur n'est **jamais** le seul signal : bonne / mauvaise réponse ont toujours une icône (coche / croix) et un libellé (« Bonne réponse », « Ta réponse »).
- Un seul bouton corail plein par écran.
- Pas de dégradé dans l'UI. Un dégradé corail → safran est toléré sur les visuels TikTok.

## 3. Typographies (Google Fonts, licence OFL)

| Usage | Police | Graisses | Tailles (px = dp) |
|---|---|---|---|
| Titres, scores, chiffres, logo | **Bricolage Grotesque** | 700, 800 | Score 72 · Titre écran 28 · Question 24 · Titre carte 20 |
| Texte, boutons, réponses | **Atkinson Hyperlegible** | 400, 700 | Réponse 17 · Corps 16 · Légende 14 · Mini 13 (minimum) |

- Atkinson Hyperlegible est conçue pour la lisibilité (distingue bien 1 / l / I, 0 / O) : utile pour des réponses chiffrées comme « 1789 » ou « 206 ».
- Interligne : 1,25 pour les titres, 1,45 pour le texte.
- Flutter : embarquer les fichiers `.ttf` dans `assets/fonts/` (pas de chargement réseau au démarrage) et déclarer `fontFamily` dans le `TextTheme`.
- Respecter l'agrandissement du texte système (Dynamic Type / taille de police Android) jusqu'à 130 % sans casser la mise en page.

## 4. Ton de voix

- **Tutoiement**, phrases courtes, verbes d'action : « Joue le défi », « Partage ton score ».
- **Encourager, jamais moquer.** Erreur : « Raté ! » puis l'explication, sans « nul » ni « honte ».
- **Défier avec le sourire** : « Tu fais mieux ? », « 7/10. Qui dit mieux ? ».
- **Expliquer en une ou deux phrases** : un fait, pas un cours.
- **Ancrage francophone** : environ 30 % des questions parlent du monde francophone (France, Belgique, Suisse, Québec, Afrique francophone, outre-mer), sans jamais exclure un joueur d'un autre pays. Ex. : « Quelle ville belge est surnommée la Cité ardente ? », « Quel fleuve traverse Québec ? ».
- **Honnête sur les pubs et le paiement** : « Un seul achat, plus de pubs. Le contenu reste le même. »
- Pas de chiffres non vérifiés dans les textes (« des milliers de joueurs », « n°1 »).
- Majuscule seulement en début de phrase. Pas de texte tout en capitales, sauf les surtitres courts (« DÉFI DU JOUR ») en 13 px, espacement +0,08 em.

| Situation | Oui | Non |
|---|---|---|
| Bonne réponse | « Bien vu ! » | « EXCELLENT !!! » |
| Mauvaise réponse | « Raté ! C'était Canberra. » | « Faux. Dommage pour toi. » |
| Série en danger | « Joue aujourd'hui pour garder ta série de 6 jours. » | « Tu vas tout perdre ! » |
| Résultat | « 7/10, joli score ! » | « Tu bats 82 % des joueurs » (chiffre inventé) |

## 5. Logo

- **Logotype :** « quizzéo » en minuscules, Bricolage Grotesque ExtraBold (800), approche −0,02 em. Lettres en encre (`#1A1B3A`), le **é en corail** (`#D63A1F`). En sombre : lettres `#F5F1EA`, é `#FF7A5C`.
- **Symbole (icône d'app) :** un « é » minuscule blanc, centré sur un carré corail aux coins arrondis. Variantes à explorer : é dans un anneau de timer, é sur fond encre. À tester à 29 px (taille réglages iOS) : l'accent doit rester visible.
- **Zone de protection :** la hauteur du « z » autour du logo.
- **Interdits :** contour, ombre portée, rotation, autre couleur pour le é, ajout d'un « Q », d'une bulle ou d'un point d'interrogation.

## 6. Grille, formes, élévation

- Grille de **4 dp** : espacements 4, 8, 12, 16, 20, 24, 32. Marges d'écran : **20 dp**.
- Rayons : 12 (pastilles, petites cartes), **16** (boutons, cartes de réponse), 24 (carte défi, feuilles du bas), 999 (pilules).
- Élévation : pas d'ombre sur les cartes. Bordures de 2 dp ou fonds teintés. Seule la feuille d'explication du bas a une ombre douce.
- Cibles tactiles : **≥ 48 dp** sur Android, ≥ 44 pt sur iOS. Nos composants font tous ≥ 48.

## 7. Composants clés

### Bouton de réponse
- Hauteur min. **60 dp**, pleine largeur, rayon 16, bordure 2 dp `#8A8CA6`, fond blanc.
- À gauche, une pastille 32 × 32 avec la lettre (A, B, C, D) ; texte 17 px Atkinson 700, jusqu'à 2 lignes.
- États :
  - **Pressé** : bordure corail foncé `#B8301A`, fond `#FFE1D8`.
  - **Bonne réponse** : fond `#DDF3E6`, bordure `#17784A`, pastille verte avec coche, libellé « Bonne réponse ».
  - **Mauvaise (choisie)** : fond `#FCE3E5`, bordure `#C42B3A`, pastille rouge avec croix, libellé « Ta réponse ».
  - **Autres après réponse** : opacité 55 %, désactivés.
- L'ordre des 4 réponses est **mélangé** à l'affichage (dans `questions.json`, `correctIndex` vaut toujours 0).
- Retour haptique léger au choix. Sons activés par défaut, coupés en mode silencieux.

### Timer (30 s)
- Anneau de 56 dp (trait 5 dp) avec le nombre de secondes au centre (Bricolage 800, 20 px), plus une barre fine de progression sous l'en-tête.
- Couleurs : canard `#0E6E72` de 30 à 11 s → ambre `#9A6500` de 10 à 6 s, avec la pastille centrale en safran → corail `#D63A1F` de 5 à 0 s.
- Le chiffre est toujours affiché : la couleur ne porte pas l'information seule.
- `prefers-reduced-motion` / « Réduire les animations » : pas de pulsation, seulement le décompte.
- Temps écoulé : la question passe en feedback avec « Temps écoulé » et la bonne réponse.
- Lecteur d'écran : annoncer seulement à 10 s et à 5 s, pas chaque seconde.

### Carte catégorie
- Grille de 2 colonnes, hauteur 72 dp, rayon 16, fond teinté de la catégorie.
- Icône 24 dp dans un rond blanc de 40 dp, nom en Atkinson 700 17 px.
- Toute la carte est cliquable.

### Carte « Défi du jour »
- Fond corail, rayon 24, padding 20. Surtitre « DÉFI DU JOUR · date », titre blanc 24 px, bouton blanc « Jouer le défi » (texte encre) de 52 dp.
- Une fois joué, elle affiche le score du jour et « Nouveau défi dans X h ».

### Série (streak)
- Pastille safran avec flamme et nombre de jours, en haut de l'accueil.
- Sur l'accueil, une rangée de 7 jours (L M M J V S D) : jour joué = rond safran avec coche, aujourd'hui = anneau corail, jour à venir = contour.

### Emplacement pub
- **Bannière adaptative ancrée** en bas de l'accueil et des résultats : zone réservée de 50 à 60 dp, fond sable `#F6EEE3`, libellé « Annonce ».
- **Interstitiel** : seulement entre deux quiz (au lancement du quiz suivant), fréquence plafonnée. Jamais sur les écrans question ni feedback.
- Aucune pub si l'utilisateur a acheté « Sans pub ». Aucune pub personnalisée sans consentement UMP.

## 7 bis. Engagement (série, gel, XP, objectif, combo)

Mécaniques inspirées des apps d'apprentissage à séries (voir `CLAUDE.md` § Engagement), **avec l'apparence de Quizzéo** : pas de mascotte, pas de vert « appli de langues », pas de personnage. Les couleurs restent corail / encre / safran, avec deux ajouts : **glacier** (gel) et l'usage du canard pour l'XP.

### Couleurs ajoutées

| Rôle | Clair | Sombre | Contraste vérifié |
|---|---|---|---|
| Flamme extérieure | corail `#D63A1F` | `#FF7A5C` | 4,7 sur blanc · 4,4 sur crème (graphique) |
| Flamme intérieure | safran `#FFC23D` | `#FFC23D` | décoratif, toujours dans la flamme corail |
| Gel (Glacier) | `#1F5E8C` | `#8CC8F0` | 6,9 sur blanc · 5,7 sur `#DDEBF6` · sombre 8,7 sur surface |
| Gel conteneur | `#DDEBF6` | `#1E2042` + bordure gel 1,5 | texte encre 13,7 |
| XP | canard `#0E6E72` | `#4FC7C9` | 6,0 sur blanc · texte blanc dessus 6,0 |
| XP conteneur | `#D8EEF0` (texte `#0A3F42`) | `#133F45` (texte `#F5F1EA`) | 9,7 · 10,2 |
| Gain d'XP (barre) | safran `#FFC23D` | `#FFC23D` | remplissage uniquement |
| Combo (fond / texte / icône) | `#1A1B3A` / `#FFF7EE` / `#FFC23D` | `#2A2C55` + bordure safran / `#F5F1EA` / `#FFC23D` | 15,7 · icône 10,3 ; sombre 11,7 · 8,2 |
| Rapidité (icône) | ambre `#9A6500` | `#FFC23D` | 5,0 sur blanc · 4,7 sur crème |

### Composants

- **Flamme de série** : symbole en 2 couleurs (corail + cœur safran), sans visage ni personnage. Tailles : 24 dp (pastille de l'AppBar, en encre sur safran), 52 dp (carte Série de l'accueil), 104 dp (écran « Série validée »). Série en danger : même flamme **en contour** corail, jamais grise, éteinte ou rouge alarme.
- **Pastille série** (AppBar) : safran, flamme encre + nombre en Bricolage 800 20 px, 44 dp de haut. Tap -> écran Série.
- **Pastille gel** : fond glacier conteneur, flocon glacier + nombre de gels, 44 dp. Dans la rangée des jours, un jour couvert par un gel = rond glacier conteneur avec flocon.
- **Jauge de l'objectif du jour** : N segments (N = objectif choisi, 1 à 3), hauteur 10, rayon 999, écart 6. Plein = corail, vide = lin `#E6DED2` (sombre `#34365E`). Objectif atteint : tous les segments en vert succès + coche. Le texte « 1/2 quiz » est toujours affiché.
- **Niveau et barre d'XP** : pastille ronde 40 dp canard avec le numéro de niveau (Bricolage 800 18, texte blanc) ; barre de 10 dp, fond lin, part acquise en canard, gain du quiz en safran pendant l'animation. Toujours accompagnée de « 355 / 400 XP ».
- **Badge XP** : pilule XP conteneur, Bricolage 800 16 (20 sur la feuille de feedback), format « +15 XP ». Détail en puces bordées (« +10 bonne réponse », « +5 rapidité »).
- **Combo** : pilule encre avec éclair safran, « Combo x3 », Bricolage 800 15, 32 dp. Affichée à partir de x2, masquée sinon. Perte de combo : disparition en fondu, sans message négatif.
- **Bonus rapidité** : discret, texte légende (14 px, encre douce) + chrono ambre, « Bonus rapidité · 4 s ». Disparaît après 10 s. Pas de pulsation.
- **Confettis** (10/10 seulement) : rectangles et ronds corail, safran, canard, vert, glacier ; 1,2 s ; jamais avec « Réduire les animations ».

### Règles de ton et d'éthique
- Pas de vies, pas de blocage : on peut toujours jouer.
- Un seul rappel par jour, à l'heure choisie, seulement si le joueur n'a pas encore joué. Texte neutre : « Le défi du jour est prêt. 10 questions, ça te dit ? ». Jamais « Tu vas perdre ta série ! ».
- Le gel via pub récompensée est **facultatif** : bouton « Non merci » aussi visible que l'offre, aucune relance le même jour.
- « Difficulté 2/3 » désigne la difficulté d'une question ; « Niveau » est réservé au niveau du joueur.

### Retours sensoriels
| Moment | Haptique (`HapticFeedback`) | Son (si activé) |
|---|---|---|
| Choix d'une réponse | `lightImpact` | aucun |
| Bonne réponse | `mediumImpact` | court « ding » (≈ 300 ms) |
| Mauvaise réponse | aucun | aucun ou son neutre |
| Combo qui monte | `selectionClick` | aucun |
| Série validée | `mediumImpact` | « flamme » (≈ 500 ms) |
| Objectif atteint | `mediumImpact` | aucun |
| Montée de niveau / 10/10 | `heavyImpact` | « fanfare » courte (≈ 1 s) |

Sons : préchargés, respectant le mode silencieux (iOS : session audio *ambient*), réglables dans Profil. **Activés par défaut** (décision de Fares, 25/11/2026), mais muets quand le téléphone est en mode silencieux.

### Barème proposé (à valider par Fares)
- +10 XP par bonne réponse ; +5 si réponse dans les 10 premières secondes ; +5 par bonne réponse à partir du combo x3 ; +20 quiz terminé ; +30 sans faute.
- Niveau n -> n+1 : 100 + 50 × (n − 1) XP (niveau 1 -> 2 : 100 XP ; 7 -> 8 : 400 XP).
- Série validée par 1 quiz terminé dans la journée (heure locale), indépendamment de l'objectif.
- Gel : protège 1 jour ; réserve max proposée : 2.

## 8. Correspondance Flutter Material 3

```dart
// ColorScheme clair
ColorScheme(
  brightness: Brightness.light,
  primary: Color(0xFFD63A1F), onPrimary: Color(0xFFFFFFFF),
  primaryContainer: Color(0xFFFFE1D8), onPrimaryContainer: Color(0xFF5A1406),
  secondary: Color(0xFF0E6E72), onSecondary: Color(0xFFFFFFFF),
  secondaryContainer: Color(0xFFD8EEF0), onSecondaryContainer: Color(0xFF0A3F42),
  tertiary: Color(0xFFFFC23D), onTertiary: Color(0xFF1A1B3A),
  error: Color(0xFFC42B3A), onError: Color(0xFFFFFFFF),
  errorContainer: Color(0xFFFCE3E5), onErrorContainer: Color(0xFF9E1C2A),
  surface: Color(0xFFFFF7EE), onSurface: Color(0xFF1A1B3A),
  onSurfaceVariant: Color(0xFF4A4C6B),
  surfaceContainerLowest: Color(0xFFFFFFFF), // cartes
  surfaceContainer: Color(0xFFF6EEE3),       // zone pub, fonds secondaires
  outline: Color(0xFF8A8CA6), outlineVariant: Color(0xFFE6DED2),
)
// ColorScheme sombre
ColorScheme(
  brightness: Brightness.dark,
  primary: Color(0xFFFF7A5C), onPrimary: Color(0xFF12132A),
  primaryContainer: Color(0xFF5A1E12), onPrimaryContainer: Color(0xFFFFD9CF),
  secondary: Color(0xFF4FC7C9), onSecondary: Color(0xFF12132A),
  secondaryContainer: Color(0xFF133F45), onSecondaryContainer: Color(0xFFF5F1EA),
  tertiary: Color(0xFFFFC23D), onTertiary: Color(0xFF12132A),
  error: Color(0xFFFF8A95), onError: Color(0xFF12132A),
  errorContainer: Color(0xFF45161F), onErrorContainer: Color(0xFFFFD9DC),
  surface: Color(0xFF12132A), onSurface: Color(0xFFF5F1EA),
  onSurfaceVariant: Color(0xFFB4B6D0),
  surfaceContainerLowest: Color(0xFF1E2042),
  surfaceContainer: Color(0xFF2A2C55),
  outline: Color(0xFF6E7096), outlineVariant: Color(0xFF34365E),
)
```

- **Succès, ambre timer et teintes de catégories** : hors `ColorScheme`. Les mettre dans une `ThemeExtension<QuizColors>` (`success`, `onSuccess`, `successContainer`, `onSuccessContainer`, `timerWarning`, `categoryTint[cat]`, `categoryIcon[cat]`).
- **Engagement** : `ThemeExtension<EngagementColors>` (`flammeExt`, `flammeInt`, `gel`, `gelContainer`, `xp`, `xpContainer`, `onXpContainer`, `xpGain`, `comboBg`, `comboText`, `comboIcon`, `rapide`), valeurs au § 7 bis. Animations : désactiver si `MediaQuery.disableAnimationsOf(context)`.
- `FilledButton` : hauteur min. 56, rayon 16, texte Atkinson 700 17.
- `OutlinedButton` (réponses) : hauteur min. 60, bordure 2, rayon 16.
- `CardTheme` : elevation 0, rayon 16, couleur `surfaceContainerLowest`.
- `NavigationBar` : hauteur 64, indicateur `primaryContainer`.
- `textTheme` : `displayLarge` = Bricolage 800 72 (score) ; `headlineSmall` = Bricolage 700 24 (question) ; `titleLarge` = Bricolage 700 20 ; `bodyLarge` = Atkinson 400 16 ; `labelLarge` = Atkinson 700 17.
