#!/bin/sh
# À lancer avant tout `flutter build` : refuse une clé secrète Supabase dans config/*.json
# (les valeurs --dart-define sont compilées dans le binaire et extractibles).
set -e
cd "$(dirname "$0")/.."
if grep -qE 'sb_secret_|service_role|eyJhbGci' config/*.json 2>/dev/null; then
  echo "ERREUR : clé secrète Supabase dans config/*.json — n'utiliser que la clé sb_publishable_." >&2
  exit 1
fi
echo "config OK"
