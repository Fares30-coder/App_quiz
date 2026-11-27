#!/bin/sh
# À lancer avant tout `flutter build` : refuse une clé secrète Supabase dans config/*.json
# (les valeurs --dart-define sont compilées dans le binaire et extractibles).
set -e
cd "$(dirname "$0")/.."
if grep -qE 'sb_secret_|service_role|eyJhbGci' config/*.json 2>/dev/null; then
  echo "ERREUR : clé secrète Supabase dans config/*.json — n'utiliser que la clé sb_publishable_." >&2
  exit 1
fi
# Aucun vrai ID AdMob suivi par git (seuls les ID de test Google 3940256099942544).
if git grep -nE 'ca-app-pub-[0-9]{16}' | grep -v 3940256099942544; then
  echo "ERREUR : vrai ID AdMob suivi par git — le mettre dans android/local.properties ou ios/Flutter/Admob.xcconfig (voir README § AdMob)." >&2
  exit 1
fi
echo "config OK"
