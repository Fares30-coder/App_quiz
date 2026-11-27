import 'package:flutter/foundation.dart';

final _adUnitIdFormat = RegExp(r'^ca-app-pub-\d{16}/\d{10}$');

/// Règle commune aux ID de bloc (bannière, interstitiel) : en debug et
/// profile, toujours l'ID de test ; en release, le vrai ID injecté par
/// `--dart-define`. Vrai ID absent, mal formé ou de test en release : repli
/// sur l'ID de test avec un log, ou [StateError] si [requireReal]
/// (`--dart-define=REQUIRE_REAL_AD_UNITS=true`, builds stores).
///
/// [label] : « de bannière », « d'interstitiel »… (messages d'erreur) ;
/// [androidDefine] / [iosDefine] : noms des variables `--dart-define`.
String resolveAdUnitId({
  required String label,
  required String androidDefine,
  required String iosDefine,
  required String testAndroidId,
  required String testIosId,
  required String androidId,
  required String iosId,
  required bool releaseMode,
  required bool requireReal,
  TargetPlatform? platform,
}) {
  final ios = (platform ?? defaultTargetPlatform) == TargetPlatform.iOS;
  final testId = ios ? testIosId : testAndroidId;
  final realId = ios ? iosId : androidId;
  if (!releaseMode) return testId;
  if (_adUnitIdFormat.hasMatch(realId) &&
      !realId.contains('3940256099942544')) {
    return realId;
  }
  final define = ios ? iosDefine : androidDefine;
  if (requireReal) {
    throw StateError('AdMob : vrai ID $label requis en release '
        '(REQUIRE_REAL_AD_UNITS=true) : --dart-define=$define absent, '
        'mal formé ou ID de test.');
  }
  debugPrint('AdMob : ID $label réel absent ou invalide en release, '
      'ID de test utilisé (--dart-define=$define).');
  return testId;
}
