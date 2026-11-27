#!/bin/sh
# Seul chemin vers les stores (voir README § AdMob) : vérifie la config puis
# construit l'AAB (Android) et/ou l'IPA (iOS) en release.
#
# Usage : ADMOB_BANNER_ANDROID=ca-app-pub-…/… ADMOB_BANNER_IOS=ca-app-pub-…/… \
#           tool/build_store.sh [android|ios|all]   (défaut : all)
#
# Prérequis : config/prod.json (ignoré par git), vrais App ID AdMob dans
# android/local.properties et ios/Flutter/Admob.xcconfig (ignorés par git).
set -eu
cd "$(dirname "$0")/.."

TARGET=${1:-all}
case "$TARGET" in
  android | ios | all) ;;
  *)
    echo "Usage : tool/build_store.sh [android|ios|all]" >&2
    exit 1
    ;;
esac

sh tool/check_config.sh

if [ ! -f config/prod.json ]; then
  echo "ERREUR : config/prod.json absent (copier config/dev.example.json)." >&2
  exit 1
fi

# Affiche seulement le début de l'ID (jamais l'ID complet dans les logs).
masked() {
  printf '%s' "$1" | cut -c1-15
}

# $1 : nom de la variable, $2 : valeur.
check_unit_id() {
  if [ -z "$2" ]; then
    echo "ERREUR : variable $1 absente (ID de bloc bannière AdMob)." >&2
    exit 1
  fi
  if ! printf '%s' "$2" | grep -Eq '^ca-app-pub-[0-9]{16}/[0-9]{10}$'; then
    echo "ERREUR : $1 mal formé (attendu ca-app-pub-<16 chiffres>/<10 chiffres>)." >&2
    exit 1
  fi
  case "$2" in
    *3940256099942544*)
      echo "ERREUR : $1 est un ID de test Google ($(masked "$2")…)." >&2
      exit 1
      ;;
  esac
  echo "$1 : $(masked "$2")… OK"
}

ADMOB_BANNER_ANDROID=${ADMOB_BANNER_ANDROID:-}
ADMOB_BANNER_IOS=${ADMOB_BANNER_IOS:-}
check_unit_id ADMOB_BANNER_ANDROID "$ADMOB_BANNER_ANDROID"
check_unit_id ADMOB_BANNER_IOS "$ADMOB_BANNER_IOS"

# Gradle : échec si le release Android est resté sur l'App ID de test.
export ORG_GRADLE_PROJECT_requireRealAdmobId=true

build() {
  flutter build "$1" \
    --release \
    --obfuscate \
    --split-debug-info=build/symbols \
    --dart-define-from-file=config/prod.json \
    --dart-define=REQUIRE_REAL_AD_UNITS=true \
    --dart-define=ADMOB_BANNER_ANDROID="$ADMOB_BANNER_ANDROID" \
    --dart-define=ADMOB_BANNER_IOS="$ADMOB_BANNER_IOS"
}

if [ "$TARGET" = android ] || [ "$TARGET" = all ]; then
  build appbundle
fi
if [ "$TARGET" = ios ] || [ "$TARGET" = all ]; then
  # Phase « Garde App ID AdMob » (Xcode) : échec si ADMOB_APP_ID est l'ID de test.
  build ipa
fi
echo "Builds stores terminés ($TARGET). Symboles : build/symbols (à conserver, ne pas committer)."
