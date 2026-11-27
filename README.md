# App_quiz
## AdMob

Par défaut, l'app utilise les App ID de **test** Google. Pour tester avec le vrai App ID sur ton appareil, sans jamais le committer :
- Android : ajoute `admob.appId=ca-app-pub-…~…` dans `android/local.properties` (ignoré par git), ou exporte `ORG_GRADLE_PROJECT_admobAppId` (jamais dans `gradle.properties`, suivi). Build store : `ORG_GRADLE_PROJECT_requireRealAdmobId=true flutter build appbundle` échoue si le release est resté sur l'ID de test.
- iOS : copie `ios/Flutter/Admob.xcconfig.example` en `ios/Flutter/Admob.xcconfig` (ignoré par git) et remplace `ADMOB_APP_ID`. Debug EEE : `--dart-define=UMP_DEBUG_EEA=true` (+ `UMP_TEST_DEVICE_ID=<id haché>`).

### Bannières (T20)

- En debug et profile, toujours l'ID de test Google « bannière adaptative ancrée » (Android `ca-app-pub-3940256099942544/9214589741`, iOS `ca-app-pub-3940256099942544/2435281174`).
- En release, les vrais ID de bloc sont injectés au build, jamais écrits dans le dépôt : `--dart-define=ADMOB_BANNER_ANDROID=ca-app-pub-…/…` et `--dart-define=ADMOB_BANNER_IOS=ca-app-pub-…/…`, ou ces clés dans un `config/*.json` (ignoré par git) passé avec `--dart-define-from-file`. ID absent ou mal formé : repli sur l'ID de test, avec un message dans les logs (pas de plantage).
- **Builds stores** : ajouter `--dart-define=REQUIRE_REAL_AD_UNITS=true`. En release, l'app lève alors une `StateError` dès le démarrage si l'ID de bloc de la plateforme manque, est mal formé ou est un ID de test (au lieu du repli silencieux).
- `tool/check_config.sh` refuse tout vrai ID AdMob (ID d'éditeur seul, App ID ou ID de bloc ; filtrage par ID, fichier et ligne affichés) dans les fichiers suivis, indexés ou non suivis non ignorés.
- Une bannière n'est chargée que si `bannerAllowedProvider` est vrai (`adsReadyProvider` et pas d'achat « sans pub », `adsRemovedProvider`, à brancher en T23) et si l'écran est visible ; elle est libérée sinon (retrait du consentement, quiz par-dessus l'accueil, onglet caché).
