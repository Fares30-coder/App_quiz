import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:material_ui/material_ui.dart';

import 'ad_unit_id.dart';
import 'consent_service.dart';

/// ID de test Google « bannière adaptative ancrée » (doc AdMob « test ads »).
const testBannerIdAndroid = 'ca-app-pub-3940256099942544/9214589741';
const testBannerIdIos = 'ca-app-pub-3940256099942544/2435281174';

/// ID de bloc bannière. Les vrais ID viennent de `--dart-define`
/// (`ADMOB_BANNER_ANDROID`, `ADMOB_BANNER_IOS`, voir README § AdMob) et ne
/// servent qu'en release : en debug et profile, toujours l'ID de test.
/// En release, ID absent, mal formé ou de test : repli sur l'ID de test avec un
/// log, ou [StateError] si `--dart-define=REQUIRE_REAL_AD_UNITS=true` (builds
/// stores, vérifié dès le démarrage dans `main()`). Voir [resolveAdUnitId].
String bannerAdUnitId({
  TargetPlatform? platform,
  bool releaseMode = kReleaseMode,
  bool requireReal = const bool.fromEnvironment('REQUIRE_REAL_AD_UNITS'),
  String androidId = const String.fromEnvironment('ADMOB_BANNER_ANDROID'),
  String iosId = const String.fromEnvironment('ADMOB_BANNER_IOS'),
}) =>
    resolveAdUnitId(
      label: 'de bannière',
      androidDefine: 'ADMOB_BANNER_ANDROID',
      iosDefine: 'ADMOB_BANNER_IOS',
      testAndroidId: testBannerIdAndroid,
      testIosId: testBannerIdIos,
      androidId: androidId,
      iosId: iosId,
      releaseMode: releaseMode,
      requireReal: requireReal,
      platform: platform,
    );

/// Bannière chargée, prête à afficher. [dispose] la libère côté SDK.
abstract class LoadedBanner {
  Widget get view;
  void dispose();
}

/// Chargement des bannières (SDK Google). Remplacé par un faux dans les tests.
abstract class BannerLoader {
  /// Taille adaptative ancrée pour la largeur de l'écran ; `null` si indisponible.
  Future<AdSize?> anchoredSize(int width);

  /// `null` en cas d'échec (pas de réseau, pas de pub disponible…).
  Future<LoadedBanner?> load(AdSize size);
}

/// Aucune bannière : valeur par défaut (tests), remplacée dans `main()`.
class DisabledBannerLoader implements BannerLoader {
  const DisabledBannerLoader();

  @override
  Future<AdSize?> anchoredSize(int width) async => null;

  @override
  Future<LoadedBanner?> load(AdSize size) async => null;
}

class GoogleBannerLoader implements BannerLoader {
  const GoogleBannerLoader();

  @override
  Future<AdSize?> anchoredSize(int width) =>
      AdSize.getLargeAnchoredAdaptiveBannerAdSize(width);

  @override
  Future<LoadedBanner?> load(AdSize size) {
    final done = Completer<LoadedBanner?>();
    BannerAd(
      adUnitId: bannerAdUnitId(),
      size: size,
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (ad) => done.complete(_GoogleBanner(ad as BannerAd)),
        onAdFailedToLoad: (ad, error) {
          ad.dispose();
          if (kDebugMode) debugPrint('Bannière non chargée : $error');
          done.complete(null);
        },
      ),
    ).load();
    return done.future;
  }
}

class _GoogleBanner implements LoadedBanner {
  _GoogleBanner(this._ad);

  final BannerAd _ad;

  @override
  Widget get view => AdWidget(ad: _ad);

  @override
  void dispose() => _ad.dispose();
}

final bannerLoaderProvider =
    Provider<BannerLoader>((ref) => const DisabledBannerLoader());

/// Achat « sans pub » (T23, pas encore fait) : à brancher sur le statut d'achat.
final adsRemovedProvider = Provider<bool>((ref) => false);

/// Bannière autorisée : consentement et SDK prêts, et pas d'achat « sans pub ».
final bannerAllowedProvider = Provider<bool>(
  (ref) => ref.watch(adsReadyProvider) && !ref.watch(adsRemovedProvider),
);
