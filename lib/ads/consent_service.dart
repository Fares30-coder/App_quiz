import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

/// Réglages de debug UMP, seulement en debug (`kDebugMode`), jamais en release :
/// `--dart-define=UMP_DEBUG_EEA=true` force la géographie EEE, et
/// `--dart-define=UMP_TEST_DEVICE_ID=<id haché>` (affiché dans les logs natifs
/// au premier lancement) l'applique à un appareil réel.
ConsentDebugSettings? consentDebugSettings({
  bool debugMode = kDebugMode,
  bool forceEea = const bool.fromEnvironment('UMP_DEBUG_EEA'),
  String testDeviceId = const String.fromEnvironment('UMP_TEST_DEVICE_ID'),
}) {
  if (!debugMode || !forceEea) return null;
  return ConsentDebugSettings(
    debugGeography: DebugGeography.debugGeographyEea,
    testIdentifiers: testDeviceId.isEmpty ? null : [testDeviceId],
  );
}

/// Échec UMP (hors ligne, formulaire non configuré…). Jamais bloquant.
class ConsentFailure implements Exception {
  const ConsentFailure(this.code, this.message);

  final int code;
  final String message;

  @override
  String toString() => 'ConsentFailure($code) : $message';
}

/// Appels au SDK Google (UMP + MobileAds). Remplacé par un faux dans les tests.
abstract class AdsPlatform {
  /// Met à jour les infos de consentement (réseau). Lève une erreur si échec.
  Future<void> requestConsentInfoUpdate();

  /// Affiche le formulaire RGPD (et, sur iOS, le message IDFA puis l'ATT)
  /// seulement si nécessaire.
  Future<void> showConsentFormIfRequired();

  /// Valeur mise en cache par UMP : celle de la session précédente si la mise
  /// à jour a échoué.
  Future<bool> canRequestAds();

  /// `true` si Google exige un accès aux options de confidentialité (EEE…).
  Future<bool> privacyOptionsRequired();

  Future<void> showPrivacyOptionsForm();

  /// Initialise le SDK pub. À n'appeler qu'après [canRequestAds] == `true`.
  Future<void> initializeMobileAds();
}

/// Aucune pub : valeur par défaut (tests), remplacée dans `main()`.
class DisabledAdsPlatform implements AdsPlatform {
  const DisabledAdsPlatform();

  @override
  Future<void> requestConsentInfoUpdate() async {}

  @override
  Future<void> showConsentFormIfRequired() async {}

  @override
  Future<bool> canRequestAds() async => false;

  @override
  Future<bool> privacyOptionsRequired() async => false;

  @override
  Future<void> showPrivacyOptionsForm() async {}

  @override
  Future<void> initializeMobileAds() async {}
}

/// Implémentation réelle : `google_mobile_ads` (UMP inclus).
class GoogleAdsPlatform implements AdsPlatform {
  /// Réglages de debug ignorés hors `kDebugMode`, même passés explicitement.
  GoogleAdsPlatform({ConsentDebugSettings? debugSettings})
      : _debugSettings =
            kDebugMode ? (debugSettings ?? consentDebugSettings()) : null;

  final ConsentDebugSettings? _debugSettings;

  @override
  Future<void> requestConsentInfoUpdate() {
    final done = Completer<void>();
    ConsentInformation.instance.requestConsentInfoUpdate(
      ConsentRequestParameters(consentDebugSettings: _debugSettings),
      () => done.complete(),
      (e) => done.completeError(ConsentFailure(e.errorCode, e.message)),
    );
    return done.future;
  }

  @override
  Future<void> showConsentFormIfRequired() {
    final done = Completer<void>();
    ConsentForm.loadAndShowConsentFormIfRequired((e) => e == null
        ? done.complete()
        : done.completeError(ConsentFailure(e.errorCode, e.message)));
    return done.future;
  }

  @override
  Future<bool> canRequestAds() => ConsentInformation.instance.canRequestAds();

  @override
  Future<bool> privacyOptionsRequired() async =>
      await ConsentInformation.instance.getPrivacyOptionsRequirementStatus() ==
      PrivacyOptionsRequirementStatus.required;

  @override
  Future<void> showPrivacyOptionsForm() {
    final done = Completer<void>();
    ConsentForm.showPrivacyOptionsForm((e) => e == null
        ? done.complete()
        : done.completeError(ConsentFailure(e.errorCode, e.message)));
    return done.future;
  }

  @override
  Future<void> initializeMobileAds() => MobileAds.instance.initialize();
}

final adsPlatformProvider =
    Provider<AdsPlatform>((ref) => const DisabledAdsPlatform());

class ConsentState {
  const ConsentState({
    this.adsReady = false,
    this.privacyOptionsRequired = false,
  });

  /// Consentement traité, `canRequestAds()` vrai et MobileAds initialisé :
  /// seule condition pour charger une pub (T20-T22).
  final bool adsReady;

  /// Afficher « Gérer mes choix de confidentialité » dans Profil.
  final bool privacyOptionsRequired;
}

/// Consentement UMP puis initialisation des pubs. Aucune requête pub avant.
class ConsentController extends Notifier<ConsentState> {
  /// Au-delà, on continue sans attendre (hors ligne) : nouvel essai au
  /// prochain lancement.
  static const updateTimeout = Duration(seconds: 10);

  Future<void>? _gathering;
  Future<void>? _privacy;
  Future<void>? _init;

  @override
  ConsentState build() => const ConsentState();

  AdsPlatform get _platform => ref.read(adsPlatformProvider);

  /// Une fois par lancement (après l'écran d'explication au premier).
  /// Les appels suivants réutilisent le même résultat. Ne lève jamais.
  Future<void> gather() => _gathering ??= _gather();

  Future<void> _gather() async {
    final update = _platform.requestConsentInfoUpdate();
    try {
      await update.timeout(updateTimeout);
      await _platform.showConsentFormIfRequired();
    } on TimeoutException {
      _log('Consentement UMP : pas de réponse, on continue avec le cache');
      // Réponse tardive : statut relu (le formulaire attendra le prochain
      // lancement).
      unawaited(update.then(
        (_) => _refresh(),
        onError: (Object e) => _log('Consentement UMP indisponible : $e'),
      ));
    } catch (e) {
      _log('Consentement UMP indisponible : $e');
    }
    await _refresh();
  }

  /// Formulaire « options de confidentialité » (Profil), puis mise à jour.
  /// Un double appui n'ouvre qu'un formulaire.
  Future<void> showPrivacyOptions() =>
      _privacy ??= _showPrivacyOptions().whenComplete(() => _privacy = null);

  Future<void> _showPrivacyOptions() async {
    try {
      await _platform.showPrivacyOptionsForm();
    } catch (e) {
      _log('Options de confidentialité indisponibles : $e');
    }
    await _refresh();
  }

  Future<void> _refresh() async {
    var canRequest = false;
    var options = false;
    try {
      canRequest = await _platform.canRequestAds();
      options = await _platform.privacyOptionsRequired();
    } catch (e) {
      _log('Statut du consentement illisible : $e');
    }
    final ready = canRequest && await _initializeAds();
    state = ConsentState(adsReady: ready, privacyOptionsRequired: options);
  }

  /// MobileAds initialisé une seule fois ; nouvel essai après une erreur.
  Future<bool> _initializeAds() async {
    try {
      await (_init ??= _platform.initializeMobileAds());
      return true;
    } catch (e) {
      _init = null;
      _log('Initialisation des pubs impossible : $e');
      return false;
    }
  }
}

void _log(String message) {
  if (kDebugMode) debugPrint(message);
}

final consentControllerProvider =
    NotifierProvider<ConsentController, ConsentState>(ConsentController.new);

/// À lire avant tout chargement de pub (bannière, interstitiel, récompensée).
final adsReadyProvider = Provider<bool>(
  (ref) => ref.watch(consentControllerProvider.select((s) => s.adsReady)),
);

final privacyOptionsRequiredProvider = Provider<bool>(
  (ref) => ref
      .watch(consentControllerProvider.select((s) => s.privacyOptionsRequired)),
);

/// Lancements suivants (premier lancement déjà passé) : consentement en
/// arrière-plan, le formulaire ne s'affiche que si UMP le redemande.
final consentStartupProvider = Provider<void>((ref) {
  unawaited(ref.read(consentControllerProvider.notifier).gather());
});
