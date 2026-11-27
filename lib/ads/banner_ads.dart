import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:material_ui/material_ui.dart';

import 'consent_service.dart';

/// ID de test Google « bannière adaptative ancrée » (doc AdMob « test ads »).
const testBannerIdAndroid = 'ca-app-pub-3940256099942544/9214589741';
const testBannerIdIos = 'ca-app-pub-3940256099942544/2435281174';

final _adUnitIdFormat = RegExp(r'^ca-app-pub-\d{16}/\d{10}$');

/// ID de bloc bannière. Les vrais ID viennent de `--dart-define`
/// (`ADMOB_BANNER_ANDROID`, `ADMOB_BANNER_IOS`, voir README § AdMob) et ne
/// servent qu'en release : en debug et profile, toujours l'ID de test.
/// En release, ID absent, mal formé ou de test : repli sur l'ID de test avec un
/// log, ou [StateError] si `--dart-define=REQUIRE_REAL_AD_UNITS=true` (builds
/// stores, vérifié dès le démarrage dans `main()`).
String bannerAdUnitId({
  TargetPlatform? platform,
  bool releaseMode = kReleaseMode,
  bool requireReal = const bool.fromEnvironment('REQUIRE_REAL_AD_UNITS'),
  String androidId = const String.fromEnvironment('ADMOB_BANNER_ANDROID'),
  String iosId = const String.fromEnvironment('ADMOB_BANNER_IOS'),
}) {
  final ios = (platform ?? defaultTargetPlatform) == TargetPlatform.iOS;
  final testId = ios ? testBannerIdIos : testBannerIdAndroid;
  final realId = ios ? iosId : androidId;
  if (!releaseMode) return testId;
  if (_adUnitIdFormat.hasMatch(realId) &&
      !realId.contains('3940256099942544')) {
    return realId;
  }
  final define = ios ? 'ADMOB_BANNER_IOS' : 'ADMOB_BANNER_ANDROID';
  if (requireReal) {
    throw StateError('AdMob : vrai ID de bannière requis en release '
        '(REQUIRE_REAL_AD_UNITS=true) : --dart-define=$define absent, '
        'mal formé ou ID de test.');
  }
  if (kDebugMode) {
    debugPrint('AdMob : ID de bannière réel absent ou invalide en release, '
        'ID de test utilisé (--dart-define=$define).');
  }
  return testId;
}

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
    final ad = BannerAd(
      adUnitId: bannerAdUnitId(),
      size: size,
      request: const AdRequest(),
      listener: BannerAdListener(
        // Arrivée après le délai : la pub a déjà été libérée, on l'ignore.
        onAdLoaded: (ad) {
          if (!done.isCompleted) done.complete(_GoogleBanner(ad as BannerAd));
        },
        onAdFailedToLoad: (ad, error) {
          ad.dispose();
          if (kDebugMode) debugPrint('Bannière non chargée : $error');
          if (!done.isCompleted) done.complete(null);
        },
      ),
    );
    return awaitAdLoad(done, ad.load, ad.dispose);
  }
}

/// Au-delà, un chargement de pub est abandonné (SDK sans réponse).
const adLoadTimeout = Duration(seconds: 30);

/// Lance [load] et attend [done], complété par les callbacks du SDK.
/// `null` si [load] lève ou si rien n'arrive avant [timeout] : la pub est
/// alors libérée par [dispose]. Les callbacks doivent ignorer une réponse
/// tardive (`done.isCompleted`). Même règle pour les pubs de T22.
Future<T?> awaitAdLoad<T>(
  Completer<T?> done,
  Future<void> Function() load,
  void Function() dispose, {
  Duration timeout = adLoadTimeout,
}) {
  void giveUp(String reason) {
    if (done.isCompleted) return;
    if (kDebugMode) debugPrint('Pub non chargée : $reason');
    dispose();
    done.complete(null);
  }

  final timer = Timer(timeout, () => giveUp('délai dépassé'));
  Future<void>.sync(load).catchError((Object e) => giveUp('$e'));
  return done.future.whenComplete(timer.cancel);
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
