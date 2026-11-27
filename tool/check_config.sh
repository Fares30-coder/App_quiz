#!/bin/sh
# À lancer avant tout `flutter build` : refuse une clé secrète Supabase dans config/*.json
# (les valeurs --dart-define sont compilées dans le binaire et extractibles).
set -e
cd "$(dirname "$0")/.."
if grep -qE 'sb_secret_|service_role|eyJhbGci' config/*.json 2>/dev/null; then
  echo "ERREUR : clé secrète Supabase dans config/*.json — n'utiliser que la clé sb_publishable_." >&2
  exit 1
fi
# Aucun vrai ID AdMob (ID d'éditeur seul, App ID `…~…` ou ID de bloc `…/…`)
# dans le dépôt : fichiers suivis, index (git add) et fichiers non suivis non
# ignorés. Filtre par ID (pas par ligne) : seuls les ID de test Google
# (éditeur 3940256099942544) sont admis.
ADMOB_ID='ca-app-pub-[0-9]{16}([~/][0-9]{10})?'
admob_ids() {
  git grep --untracked -ohE "$ADMOB_ID" || true
  git grep --cached -ohE "$ADMOB_ID" || true
}
REAL_IDS=$(admob_ids | grep -v '^ca-app-pub-3940256099942544' | sort -u || true)
if [ -n "$REAL_IDS" ]; then
  echo "ERREUR : vrai ID AdMob dans le dépôt :" >&2
  for id in $REAL_IDS; do
    { git grep --untracked -nF "$id" || true; git grep --cached -nF "$id" || true; } | sort -u >&2
  done
  echo "App ID : android/local.properties ou ios/Flutter/Admob.xcconfig ; ID de bloc : --dart-define ou config/*.json (ignoré) — voir README § AdMob." >&2
  exit 1
fi
echo "config OK"
