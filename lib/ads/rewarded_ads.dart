import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import '../engagement/progress_controller.dart';
import '../engagement/progress_sync.dart';
import '../quiz/quiz_controller.dart';
import 'ad_unit_id.dart';
import 'banner_ads.dart';
import 'consent_service.dart';

/// ID de test Google « vidéo avec récompense » (doc AdMob « test ads »).
const testRewardedIdAndroid = 'ca-app-pub-3940256099942544/5224354917';
const testRewardedIdIos = 'ca-app-pub-3940256099942544/1712485313';

/// ID de bloc « récompense » : même règle que [bannerAdUnitId], avec
/// `--dart-define=ADMOB_REWARDED_ANDROID` / `ADMOB_REWARDED_IOS`
/// (release seulement ; vérifié dès le démarrage dans `main()`).
String rewardedAdUnitId({
  TargetPlatform? platform,
  bool releaseMode = kReleaseMode,
  bool requireReal = const bool.fromEnvironment('REQUIRE_REAL_AD_UNITS'),
  String androidId = const String.fromEnvironment('ADMOB_REWARDED_ANDROID'),
  String iosId = const String.fromEnvironment('ADMOB_REWARDED_IOS'),
}) =>
    resolveAdUnitId(
      label: 'de pub récompensée',
      androidDefine: 'ADMOB_REWARDED_ANDROID',
      iosDefine: 'ADMOB_REWARDED_IOS',
      testAndroidId: testRewardedIdAndroid,
      testIosId: testRewardedIdIos,
      androidId: androidId,
      iosId: iosId,
      releaseMode: releaseMode,
      requireReal: requireReal,
      platform: platform,
    );

/// Pub récompensée chargée, prête à afficher.
abstract class LoadedRewarded {
  /// Affiche la vidéo. Se termine à sa fermeture : `true` seulement si le
  /// SDK a signalé la récompense (`onUserEarnedReward`, vidéo regardée
  /// jusqu'au bout) ; `false` si elle a été fermée avant ou n'a pas pu
  /// s'afficher. La pub est ensuite libérée.
  Future<bool> show();

  /// Libère une pub jamais affichée.
  void dispose();
}

/// Chargement des pubs récompensées (SDK Google). Remplacé par un faux dans
/// les tests.
abstract class RewardedLoader {
  /// `null` en cas d'échec (pas de réseau, pas de pub disponible…).
  Future<LoadedRewarded?> load();
}

/// Aucune pub récompensée : valeur par défaut (tests), remplacée dans `main()`.
class DisabledRewardedLoader implements RewardedLoader {
  const DisabledRewardedLoader();

  @override
  Future<LoadedRewarded?> load() async => null;
}

class GoogleRewardedLoader implements RewardedLoader {
  const GoogleRewardedLoader();

  @override
  Future<LoadedRewarded?> load() {
    final done = Completer<LoadedRewarded?>();
    RewardedAd.load(
      adUnitId: rewardedAdUnitId(),
      request: const AdRequest(),
      rewardedAdLoadCallback: RewardedAdLoadCallback(
        onAdLoaded: (ad) => done.complete(_GoogleRewarded(ad)),
        onAdFailedToLoad: (error) {
          if (kDebugMode) debugPrint('Pub récompensée non chargée : $error');
          done.complete(null);
        },
      ),
    );
    return done.future;
  }
}

class _GoogleRewarded implements LoadedRewarded {
  _GoogleRewarded(this._ad);

  /// La récompense peut être signalée juste après la fermeture (selon la
  /// plateforme) : courte attente avant de conclure « pas de récompense ».
  static const _rewardGrace = Duration(milliseconds: 500);

  final RewardedAd _ad;

  @override
  Future<bool> show() {
    final done = Completer<bool>();
    var earned = false;
    void finish(bool value) {
      if (!done.isCompleted) done.complete(value);
    }

    _ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (ad) {
        ad.dispose();
        if (earned) {
          finish(true);
        } else {
          Future<void>.delayed(_rewardGrace, () => finish(earned));
        }
      },
      onAdFailedToShowFullScreenContent: (ad, error) {
        ad.dispose();
        if (kDebugMode) debugPrint('Pub récompensée non affichée : $error');
        finish(false);
      },
    );
    _ad.show(onUserEarnedReward: (_, __) => earned = true);
    return done.future;
  }

  @override
  void dispose() => _ad.dispose();
}

final rewardedLoaderProvider =
    Provider<RewardedLoader>((ref) => const DisabledRewardedLoader());

/// Pub récompensée autorisée : consentement et SDK prêts, et pas d'achat
/// « sans pub » (ces joueurs auront 1 gel offert par semaine, T23).
final rewardedAllowedProvider = Provider<bool>(
  (ref) => ref.watch(adsReadyProvider) && !ref.watch(adsRemovedProvider),
);

/// Résultat d'une demande de gel par pub récompensée.
enum RewardedFreezeOutcome {
  /// Gel ajouté.
  granted,

  /// Gel déjà obtenu aujourd'hui par une pub (1 par jour).
  dailyLimit,

  /// 2 gels déjà en réserve.
  full,

  /// Vidéo fermée avant la fin ou non affichée : aucun gel.
  notEarned,

  /// Aucune pub prête (rien n'a été affiché).
  unavailable,

  /// Vidéo regardée mais gel non enregistré (réseau, pas de session).
  failed,
}

/// Octroi du gel une fois la récompense obtenue. Remplacé par un faux dans
/// les tests.
abstract class FreezeGranter {
  /// Un gel peut-il être enregistré maintenant ? Sinon, inutile de montrer
  /// la vidéo (mode Supabase sans session, ou progression en attente
  /// d'envoi). Envoie d'abord les quiz en attente. Ne lève jamais.
  Future<bool> ready();

  Future<RewardedFreezeOutcome> grant();
}

/// Mode Supabase : RPC `grant_rewarded_freeze` (le serveur fait foi, 1 gel
/// par jour). Mode 100 % local (dev sans `config/dev.json`) : gel ajouté sur
/// l'appareil.
class ProgressFreezeGranter implements FreezeGranter {
  ProgressFreezeGranter(this._ref);

  /// Un nouvel essai après une erreur passagère (réseau).
  static const retryDelay = Duration(seconds: 2);

  final Ref _ref;

  @override
  Future<bool> ready() async {
    final sync = _ref.read(progressSyncProvider);
    return sync == null || await sync.readyForFreezeGrant();
  }

  @override
  Future<RewardedFreezeOutcome> grant() async {
    final sync = _ref.read(progressSyncProvider);
    if (sync == null) {
      _ref.read(progressControllerProvider.notifier).addStreakFreeze();
      return RewardedFreezeOutcome.granted;
    }
    for (var attempt = 0; attempt < 2; attempt++) {
      if (attempt > 0) await Future<void>.delayed(retryDelay);
      try {
        final result = await sync.grantRewardedFreeze();
        if (result.granted) return RewardedFreezeOutcome.granted;
        return switch (result.reason) {
          'daily_limit' => RewardedFreezeOutcome.dailyLimit,
          'full' => RewardedFreezeOutcome.full,
          _ => RewardedFreezeOutcome.failed,
        };
      } catch (e) {
        if (kDebugMode) debugPrint('Gel non enregistré : ${e.runtimeType}');
      }
    }
    return RewardedFreezeOutcome.failed;
  }
}

final freezeGranterProvider =
    Provider<FreezeGranter>((ref) => ProgressFreezeGranter(ref));

enum RewardedStatus {
  /// Rien à proposer (pubs non autorisées, pas de pub servie).
  unavailable,
  loading,
  ready,

  /// Vidéo à l'écran ou gel en cours d'enregistrement.
  busy,
}

/// Pub récompensée pour obtenir un gel (écran Série, état « danger »).
///
/// - Chargée à la demande ([prepare], à l'ouverture de l'offre), jamais en
///   continu : pas de requête pub inutile.
/// - Libérée dès que [rewardedAllowedProvider] repasse à faux (retrait du
///   consentement, achat « sans pub ») ; rechargée s'il redevient vrai et
///   que l'offre est encore ouverte.
/// - Le gel n'est demandé au serveur que si la vidéo a été regardée jusqu'au
///   bout ([LoadedRewarded.show] vrai). Jamais pendant un quiz.
class RewardedFreezeController extends Notifier<RewardedStatus> {
  /// Après un échec de chargement, nouvel essai au plus tôt ce délai plus
  /// tard (à la prochaine ouverture de l'offre).
  static const retryDelay = Duration(minutes: 1);

  /// Une pub chargée depuis trop longtemps n'est plus servie par la régie.
  static const maxAdAge = Duration(minutes: 55);

  LoadedRewarded? _ad;
  DateTime? _loadedAt;
  DateTime? _failedAt;
  bool _wanted = false;
  bool _loading = false;
  bool _busy = false;
  bool _disposed = false;
  Future<RewardedFreezeOutcome>? _watching;

  /// Incrémenté à chaque libération : un chargement commencé avant est ignoré.
  int _generation = 0;

  DateTime _now() => ref.read(clockProvider)();

  @override
  RewardedStatus build() {
    ref.listen<bool>(rewardedAllowedProvider, (_, allowed) {
      if (allowed) {
        if (_wanted) unawaited(_load());
      } else {
        _release();
      }
    });
    ref.onDispose(() {
      _disposed = true;
      _generation++;
      _ad?.dispose();
      _ad = null;
    });
    return RewardedStatus.unavailable;
  }

  void _emit() {
    if (_disposed) return;
    state = _busy
        ? RewardedStatus.busy
        : _ad != null
            ? RewardedStatus.ready
            : _loading
                ? RewardedStatus.loading
                : RewardedStatus.unavailable;
  }

  /// L'offre de gel est affichée : charge une pub si besoin.
  void prepare() {
    _wanted = true;
    final loadedAt = _loadedAt;
    if (_ad != null &&
        loadedAt != null &&
        _now().difference(loadedAt) >= maxAdAge) {
      _release();
    }
    unawaited(_load());
  }

  /// Affiche la vidéo puis, si elle a été regardée jusqu'au bout, demande le
  /// gel. Un double appui ne lance qu'une vidéo.
  Future<RewardedFreezeOutcome> watchForFreeze() =>
      _watching ??= _watch().whenComplete(() => _watching = null);

  Future<RewardedFreezeOutcome> _watch() async {
    final ad = _ad;
    if (ad == null || !ref.read(rewardedAllowedProvider)) {
      prepare();
      return RewardedFreezeOutcome.unavailable;
    }
    final quiz = ref.read(quizControllerProvider);
    if (quiz.questions.isNotEmpty && !quiz.isFinished) {
      return RewardedFreezeOutcome.unavailable;
    }
    if (_now().difference(_loadedAt!) >= maxAdAge) {
      _release();
      prepare();
      return RewardedFreezeOutcome.unavailable;
    }
    final granter = ref.read(freezeGranterProvider);
    _busy = true;
    _emit();
    var outcome = RewardedFreezeOutcome.notEarned;
    try {
      // Quiz en attente envoyés avant la vidéo (voir FreezeGranter.ready).
      if (!await granter.ready()) {
        outcome = RewardedFreezeOutcome.failed;
        return outcome;
      }
      // Pub libérée entre-temps (consentement retiré) : rien à montrer.
      if (!identical(_ad, ad) || _disposed) {
        outcome = RewardedFreezeOutcome.unavailable;
        return outcome;
      }
      _ad = null;
      final earned = await ad.show();
      if (earned) outcome = await granter.grant();
    } catch (e) {
      if (kDebugMode) debugPrint('Pub récompensée : ${e.runtimeType}');
    } finally {
      _busy = false;
      _emit();
    }
    // Vidéo interrompue, ou non montrée : le joueur peut réessayer.
    if ((outcome == RewardedFreezeOutcome.notEarned ||
            outcome == RewardedFreezeOutcome.unavailable) &&
        !_disposed) {
      unawaited(_load());
    } else {
      _wanted = false;
    }
    return outcome;
  }

  Future<void> _load() async {
    if (_disposed || _ad != null || _loading || _busy) return;
    if (!ref.read(rewardedAllowedProvider)) return;
    final failedAt = _failedAt;
    if (failedAt != null && _now().difference(failedAt) < retryDelay) return;
    final generation = _generation;
    _loading = true;
    _emit();
    LoadedRewarded? ad;
    try {
      ad = await ref.read(rewardedLoaderProvider).load();
    } catch (e) {
      if (kDebugMode) debugPrint('Pub récompensée non chargée : $e');
    } finally {
      if (generation == _generation) _loading = false;
    }
    if (generation != _generation || _disposed) {
      ad?.dispose();
      return;
    }
    if (ad == null) {
      _failedAt = _now();
    } else {
      _failedAt = null;
      _ad = ad;
      _loadedAt = _now();
    }
    _emit();
  }

  void _release() {
    _generation++;
    _loading = false;
    final ad = _ad;
    _ad = null;
    ad?.dispose();
    _emit();
  }
}

final rewardedFreezeControllerProvider =
    NotifierProvider<RewardedFreezeController, RewardedStatus>(
        RewardedFreezeController.new);
