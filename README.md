# App_quiz
## AdMob

Par défaut, l'app utilise les App ID de **test** Google. Pour tester avec le vrai App ID sur ton appareil, sans jamais le committer :
- Android : ajoute `admob.appId=ca-app-pub-…~…` dans `android/local.properties` (ignoré par git), ou exporte `ORG_GRADLE_PROJECT_admobAppId` (jamais dans `gradle.properties`, suivi). Build store : `ORG_GRADLE_PROJECT_requireRealAdmobId=true flutter build appbundle` échoue si le release est resté sur l'ID de test.
- iOS : copie `ios/Flutter/Admob.xcconfig.example` en `ios/Flutter/Admob.xcconfig` (ignoré par git) et remplace `ADMOB_APP_ID`. Debug EEE : `--dart-define=UMP_DEBUG_EEA=true` (+ `UMP_TEST_DEVICE_ID=<id haché>`).

### Bannières (T20)

- En debug et profile, toujours l'ID de test Google « bannière adaptative ancrée » (Android `ca-app-pub-3940256099942544/9214589741`, iOS `ca-app-pub-3940256099942544/2435281174`).
- En release, les vrais ID de bloc sont injectés au build, jamais écrits dans le dépôt : `--dart-define=ADMOB_BANNER_ANDROID=ca-app-pub-…/…` et `--dart-define=ADMOB_BANNER_IOS=ca-app-pub-…/…`, ou ces clés dans un `config/*.json` (ignoré par git) passé avec `--dart-define-from-file`. ID absent ou mal formé : repli sur l'ID de test, avec un message dans les logs (pas de plantage).
- `--dart-define=REQUIRE_REAL_AD_UNITS=true` (posé par `tool/build_store.sh`) : en release, l'app lève une `StateError` dès le démarrage si l'ID de bloc de la plateforme manque, est mal formé ou est un ID de test (au lieu du repli silencieux).
- Placement : au moins 12 dp entre la bannière et la barre de navigation (accueil), 24 dp entre la bannière et tout bouton (résultats) ; annonces classées au plus « T » (13+, `maxAdContentRating`) ; bannières rechargées après « Gérer mes choix de confidentialité ».

### Builds stores : `tool/build_store.sh` (seul chemin documenté)

```sh
ADMOB_BANNER_ANDROID=ca-app-pub-…/… ADMOB_BANNER_IOS=ca-app-pub-…/… \
  tool/build_store.sh [android|ios|all]   # défaut : all
```

- Prérequis : `config/prod.json` (ignoré par git), vrais App ID dans `android/local.properties` et `ios/Flutter/Admob.xcconfig` (ignorés), signature Android et iOS (T26).
- Le script lance `tool/check_config.sh`, vérifie les deux ID de bloc (format `ca-app-pub-<16 chiffres>/<10 chiffres>`, jamais un ID de test ; seuls les premiers caractères sont affichés), exporte `ORG_GRADLE_PROJECT_requireRealAdmobId=true` (Gradle échoue si l'App ID Android est celui de test), puis lance `flutter build appbundle` et/ou `flutter build ipa` en `--release --obfuscate --split-debug-info=build/symbols --dart-define-from-file=config/prod.json --dart-define=REQUIRE_REAL_AD_UNITS=true` avec les deux ID en `--dart-define`.
- iOS : la phase Xcode « Garde App ID AdMob » (cible Runner) fait échouer tout build `Release` (y compris `flutter run --release`) si `ADMOB_APP_ID` est l'App ID de test.
- Conserver `build/symbols` (symbolisation des plantages) hors dépôt.
- `tool/check_config.sh` refuse tout vrai ID AdMob (ID d'éditeur seul, App ID ou ID de bloc ; filtrage par ID, fichier et ligne affichés) dans les fichiers texte suivis, indexés ou non suivis non ignorés ; il échoue hors d'un dépôt git.
- Une bannière n'est chargée que si `bannerAllowedProvider` est vrai (`adsReadyProvider` et pas d'achat « sans pub », `adsRemovedProvider`, à brancher en T23) et si l'écran est visible ; elle est libérée sinon (retrait du consentement, quiz par-dessus l'accueil, onglet caché).
