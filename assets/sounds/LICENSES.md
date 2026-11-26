# Sons — sources et licences

Tous les fichiers de ce dossier sont **générés par synthèse** avec le script
`tool/generate_sounds.py` (Python, bibliothèque standard uniquement). Aucun
échantillon externe n'est utilisé.

| Fichier | Moment | Durée |
|---|---|---|
| `correct.wav` | Bonne réponse (« ding ») | 300 ms |
| `wrong.wav` | Mauvaise réponse / temps écoulé (son neutre, discret) | 220 ms |
| `streak.wav` | Série validée (« flamme ») | 500 ms |
| `fanfare.wav` | 10/10 ou montée de niveau (« fanfare ») | 1 s |

Licence : créés pour Quizzéo et versés dans le domaine public,
[CC0 1.0](https://creativecommons.org/publicdomain/zero/1.0/deed.fr).
Usage commercial libre, sans attribution.

Pour les régénérer : `python3 tool/generate_sounds.py`.
