# Quizzéo · Canva et visuels marketing

Dossier Canva : **Quizzéo** · https://www.canva.com/folder/FAHb9U7jUH4
Rien n'a été supprimé ni partagé dans Canva.

## Designs Canva (25 nov. 2026)

| Visuel | Lien Canva (édition) | Export PNG | État |
|---|---|---|---|
| Icône piste A (é blanc sur corail) | https://www.canva.com/d/sMRc14wQCtMvkPd | `exports/icone-piste-a-canva.png` | **Hors charte** : Canva a mis un « É » majuscule. Utiliser la version SVG. |
| Icône piste B (é dans un anneau de timer) | https://www.canva.com/d/ZXed49xITfLHMcD | `exports/icone-piste-b-canva.png` | Conforme. |
| Icône piste C | https://www.canva.com/d/ggidqIUqTsRvXm7 | `exports/icone-piste-c-canva.png` | **Hors charte** : « É » majuscule, accent pas en corail. Utiliser la version SVG. |
| Image de partage 8/10 (1080×1920) | https://www.canva.com/d/XzpfzmSLYPZ48-Z | `exports/partage-score-canva.png` | Bonne base, mais **rangée de pastilles fausse** (une rose avec coche verte, deux qui se chevauchent). À corriger dans Canva ou utiliser la version HTML. |

Retouches Canva non faites : elles demandent une validation de Fares avant enregistrement.

## Non créés dans Canva : quota de crédits atteint

Les 3 captures stores et la miniature TikTok ont été refusées par Canva (`quota_exceeded`). Ils ont été produits en HTML à partir des maquettes, puis rendus en PNG. Pour les refaire dans Canva quand le quota revient, les briefs ci-dessous sont prêts à l'emploi.

- Capture 1 : fond corail, « 10 questions, 30 secondes chacune », écran Question (geo-001).
- Capture 2 : fond crème, « Un défi par jour. Garde ta série ! », écran Accueil.
- Capture 3 : fond encre, « Partage ton score. Défie tes potes. », écran Résultats 7/10.
- TikTok : dégradé corail → safran, « Tu as combien sur 10 ? », carte question geo-001, « Réponds en commentaire ».

## Repli HTML (sources versionnées)

| Source | PNG |
|---|---|
| `icones/icone-a-corail.svg`, `icone-b-timer.svg`, `icone-c-creme.svg` (glyphe vectorisé, sans police) | `exports/icone-*-1024.png`, comparaison 180/60/29 px : `exports/icones-planche-comparaison.png` (source `icones/planche.html`) |
| `visuels/captures.html?n=1..3&os=ios|android` (les écrans sont les vraies maquettes en iframe) | `exports/capture-{1,2,3}-*-ios-1320x2868.png`, `exports/capture-{1,2,3}-*-android-1080x1920.png` |
| `visuels/partage-score.html?s=8&serie=6` | `exports/partage-score-8-sur-10.png` |
| `visuels/tiktok-miniature.html?q=0` | `exports/tiktok-miniature-tu-as-x-sur-10.png` |

Rendu : Chromium headless (Playwright), viewport logique × 3 (`device_scale_factor=3`), en capturant l'élément `.cap` ou `.v`.

## Tailles stores retenues (à revérifier dans les consoles avant envoi)
- App Store : iPhone 6,9" 1320×2868 (portrait). Apple réduit automatiquement pour les tailles plus petites.
- Google Play : 1080×1920 (9:16). Pour être éligible aux mises en avant, Play demande en général au moins 4 captures ≥ 1080 px : **prévoir une 4e capture** (ex. classement ou feedback avec explication).
