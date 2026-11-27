import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import '../engagement/progress_controller.dart';
import '../quiz/quiz_controller.dart';
import 'ad_unit_id.dart';
import 'banner_ads.dart';
import 'consent_service.dart';
import 'interstitial_pacing.dart';

/// ID de test Google « interstitiel » (doc AdMob « test ads »).
const testInterstitialIdAndroid = 'ca-app-pub-3940256099942544/1033173712';
const testInterstitialIdIos = 'ca-app-pub-3940256099942544/4411468910';

/// ID de bloc interstitiel : même règle que [bannerAdUnitId], avec
/// `--dart-define=ADMOB_INTERSTITIAL_ANDROID` / `ADMOB_INTERSTITIAL_IOS`
/// (release seulement ; vérifié dès le démarrage dans `main()`).
String interstitialAdUnitId({
  TargetPlatform? platform,
  bool releaseMode = kReleaseMode,
  bool requireReal = const bool.fromEnvironment('REQUIRE_REAL_AD_UNITS'),
  String androidId = const String.fromEnvironment('ADMOB_INTERSTITIAL_ANDROID'),
  String iosId = const String.fromEnvironment('ADMOB_INTERSTITIAL_IOS'),
}) =>
    resolveAdUnitId(
      label: "d'interstitiel",
      androidDefine: 'ADMOB_INTERSTITIAL_ANDROID',
      iosDefine: 'ADMOB_INTERSTITIAL_IOS',
      testAndroidId: testInterstitialIdAndroid,
      testIosId: testInterstitialIdIos,
      androidId: androidId,
      iosId: iosId,
      releaseMode: releaseMode,
      requireReal: requireReal,
      platform: platform,
    );

/// Interstitiel chargé, prêt à afficher.
abstract class LoadedInterstitial {
  /// Affiche la pub en plein écran. Se termine quand elle est fermée (`true`)
  /// ou si elle n'a pas pu s'afficher (`false`) ; la pub est alors libérée.
  Future<bool> show();

  /// Libère une pub jamais affichée.
  void dispose();
}

/// Chargement des interstitiels (SDK Google). Remplacé par un faux dans les
/// tests.
abstract class InterstitialLoader {
  /// `null` en cas d'échec (pas de réseau, pas de pub disponible…).
  Future<LoadedInterstitial?> load();
}

/// Aucun interstitiel : valeur par défaut (tests), remplacée dans `main()`.
class DisabledInterstitialLoader implements InterstitialLoader {
  const DisabledInterstitialLoader();

  @override
  Future<LoadedInterstitial?> load() async => null;
}

class GoogleInterstitialLoader implements InterstitialLoader {
  const GoogleInterstitialLoader();

  @override
  Future<LoadedInterstitial?> load() {
    final done = Completer<LoadedInterstitial?>();
    InterstitialAd.load(
      adUnitId: interstitialAdUnitId(),
      request: const AdRequest(),
      adLoadCallback: InterstitialAdLoadCallback(
        onAdLoaded: (ad) => done.complete(_GoogleInterstitial(ad)),
        onAdFailedToLoad: (error) {
          if (kDebugMode) debugPrint('Interstitiel non chargé : $error');
          done.complete(null);
        },
      ),
    );
    return done.future;
  }
}

class _GoogleInterstitial implements LoadedInterstitial {
  _GoogleInterstitial(this._ad);

  final InterstitialAd _ad;

  @override
  Future<bool> show() {
    final done = Completer<bool>();
    _ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (ad) {
        ad.dispose();
        done.complete(true);
      },
      onAdFailedToShowFullScreenContent: (ad, error) {
        ad.dispose();
        if (kDebugMode) debugPrint('Interstitiel non affiché : $error');
        done.complete(false);
      },
    );
    _ad.show();
    return done.future;
  }

  @override
  void dispose() => _ad.dispose();
}

final interstitialLoaderProvider =
    Provider<InterstitialLoader>((ref) => const DisabledInterstitialLoader());

/// Interstitiel autorisé : consentement et SDK prêts, et pas d'achat
/// « sans pub » (même règle que les bannières).
final interstitialAllowedProvider = Provider<bool>(
  (ref) => ref.watch(adsReadyProvider) && !ref.watch(adsRemovedProvider),
);

/// Interstitiel entre deux quiz. État : `true` si une pub est chargée.
///
/// - Préchargé dès que [interstitialAllowedProvider] est vrai, libéré dès
///   qu'il repasse à faux (retrait du consentement, achat « sans pub »).
/// - Rechargé après chaque affichage ; après un échec, nouvel essai au plus
///   tôt [retryDelay] plus tard, au prochain quiz terminé ou à la prochaine
///   occasion d'affichage (aucune boucle de rechargement).
/// - Affiché seulement par [showIfDue], appelé aux transitions après les
///   résultats ; fréquence plafonnée par [InterstitialPacing].
class InterstitialController extends Notifier<bool> {
  static const retryDelay = Duration(minutes: 2);

  /// Une pub chargée depuis trop longtemps n'est plus servie par la régie :
  /// on la remplace (par prudence, un peu moins d'une heure).
  static const maxAdAge = Duration(minutes: 55);

  InterstitialPacing? _pacing;
  LoadedInterstitial? _ad;
  DateTime? _loadedAt;
  DateTime? _failedAt;
  bool _loading = false;
  bool _showing = false;
  bool _disposed = false;

  /// Affichage en cours : tout appel à [showIfDue] attend la même fermeture.
  Future<void>? _showFuture;

  /// Incrémenté à chaque libération : un chargement commencé avant est ignoré.
  int _generation = 0;

  InterstitialPacing get pacing => _pacing!;

  DateTime _now() => ref.read(clockProvider)();

  @override
  bool build() {
    _pacing ??= InterstitialPacing(clock: _now);
    ref.listen<bool>(interstitialAllowedProvider, (_, allowed) {
      allowed ? _load() : _release();
    }, fireImmediately: true);
    // Quiz terminé (pas un abandon) : résultat qui apparaît.
    ref.listen<QuizOutcome?>(quizControllerProvider.select((s) => s.outcome),
        (previous, next) {
      if (previous == null && next != null) quizCompleted();
    });
    ref.onDispose(() {
      _disposed = true;
      _generation++;
      _ad?.dispose();
      _ad = null;
    });
    return false;
  }

  /// Un quiz vient d'être terminé : compté pour le plafond ; nouvel essai de
  /// chargement si le précédent a échoué.
  void quizCompleted() {
    pacing.quizCompleted();
    _load();
  }

  /// Affiche la pub si elle est prête et que le plafond le permet ; sinon ne
  /// fait rien. Ne dépend jamais d'un chargement réseau : se termine tout de
  /// suite, ou à la fermeture de la pub. Si une pub est déjà à l'écran, renvoie
  /// la même attente (un quiz lancé entre-temps démarre après sa fermeture).
  /// À n'appeler qu'entre deux quiz, jamais pendant.
  Future<void> showIfDue() =>
      _showFuture ??= _showIfDue().whenComplete(() => _showFuture = null);

  Future<void> _showIfDue() async {
    final ad = _ad;
    if (ad == null) {
      unawaited(_load());
      return;
    }
    if (!ref.read(interstitialAllowedProvider)) return;
    final quiz = ref.read(quizControllerProvider);
    if (quiz.questions.isNotEmpty && !quiz.isFinished) return;
    if (!pacing.canShow) return;
    if (_now().difference(_loadedAt!) >= maxAdAge) {
      _release();
      unawaited(_load());
      return;
    }
    _ad = null;
    _showing = true;
    state = false;
    final bool shown;
    try {
      shown = await ad.show();
    } finally {
      _showing = false;
    }
    if (_disposed) return;
    if (shown) pacing.adShown();
    unawaited(_load());
  }

  Future<void> _load() async {
    if (_disposed || _ad != null || _loading || _showing) return;
    if (!ref.read(interstitialAllowedProvider)) return;
    final failedAt = _failedAt;
    if (failedAt != null && _now().difference(failedAt) < retryDelay) return;
    final generation = _generation;
    _loading = true;
    LoadedInterstitial? ad;
    try {
      ad = await ref.read(interstitialLoaderProvider).load();
    } catch (e) {
      if (kDebugMode) debugPrint('Interstitiel non chargé : $e');
    } finally {
      // Sinon déjà remis à faux par `_release` (un autre chargement peut
      // avoir commencé depuis).
      if (generation == _generation) _loading = false;
    }
    if (generation != _generation) {
      ad?.dispose();
      return;
    }
    if (ad == null) {
      _failedAt = _now();
      return;
    }
    _failedAt = null;
    _ad = ad;
    _loadedAt = _now();
    state = true;
  }

  void _release() {
    _generation++;
    _loading = false;
    final ad = _ad;
    if (ad == null) return;
    _ad = null;
    ad.dispose();
    state = false;
  }
}

final interstitialControllerProvider =
    NotifierProvider<InterstitialController, bool>(InterstitialController.new);
