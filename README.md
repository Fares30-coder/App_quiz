# App_quiz
## AdMob

Par défaut, l'app utilise les App ID de **test** Google. Pour tester avec le vrai App ID sur ton appareil, sans jamais le committer :
- Android : ajoute `admob.appId=ca-app-pub-…~…` dans `android/local.properties` (ignoré par git), ou exporte `ORG_GRADLE_PROJECT_admobAppId` (jamais dans `gradle.properties`, suivi). Build store : `ORG_GRADLE_PROJECT_requireRealAdmobId=true flutter build appbundle` échoue si le release est resté sur l'ID de test.
- iOS : copie `ios/Flutter/Admob.xcconfig.example` en `ios/Flutter/Admob.xcconfig` (ignoré par git) et remplace `ADMOB_APP_ID`. Debug EEE : `--dart-define=UMP_DEBUG_EEA=true` (+ `UMP_TEST_DEVICE_ID=<id haché>`).
