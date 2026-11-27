import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:material_ui/material_ui.dart';
import 'package:quizzeo/ads/consent_service.dart';
import 'package:quizzeo/data/progress_repository.dart';
import 'package:quizzeo/screens/profile_screen.dart';
import 'package:quizzeo/theme/app_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Faux SDK : enregistre l'ordre des appels.
class FakeAdsPlatform implements AdsPlatform {
  FakeAdsPlatform({
    this.canRequest = true,
    this.optionsRequired = false,
    this.updateError,
    this.pendingUpdate,
    this.pendingPrivacyForm,
    this.pendingInit,
    this.initError,
  });

  /// Valeur de `canRequestAds()` (cache UMP de la session précédente si la
  /// mise à jour échoue).
  bool canRequest;
  bool optionsRequired;
  Object? updateError;
  Object? initError;

  /// Si non nuls, l'appel attend que le test complète ces futures.
  Completer<void>? pendingUpdate;
  Completer<void>? pendingPrivacyForm;
  Completer<void>? pendingInit;
  final calls = <String>[];

  @override
  Future<void> requestConsentInfoUpdate() async {
    calls.add('update');
    if (pendingUpdate != null) return pendingUpdate!.future;
    if (updateError != null) throw updateError!;
  }

  @override
  Future<void> showConsentFormIfRequired() async => calls.add('form');

  @override
  Future<bool> canRequestAds() async {
    calls.add('canRequestAds');
    return canRequest;
  }

  @override
  Future<bool> privacyOptionsRequired() async => optionsRequired;

  @override
  Future<void> showPrivacyOptionsForm() async {
    calls.add('privacyForm');
    await pendingPrivacyForm?.future;
  }

  @override
  Future<void> initializeMobileAds() async {
    calls.add('initialize');
    await pendingInit?.future;
    if (initError != null) throw initError!;
  }

  int count(String call) => calls.where((c) => c == call).length;
}

ProviderContainer containerWith(FakeAdsPlatform platform) {
  final container = ProviderContainer(
    overrides: [adsPlatformProvider.overrideWithValue(platform)],
  );
  addTearDown(container.dispose);
  return container;
}

void main() {
  group('ConsentController', () {
    test('rien avant gather : aucune initialisation, pas de pub', () {
      final platform = FakeAdsPlatform();
      final container = containerWith(platform);
      expect(container.read(adsReadyProvider), isFalse);
      expect(platform.calls, isEmpty);
    });

    test('MobileAds initialisé seulement après mise à jour + formulaire',
        () async {
      final platform = FakeAdsPlatform();
      final container = containerWith(platform);
      await container.read(consentControllerProvider.notifier).gather();
      expect(platform.calls, ['update', 'form', 'canRequestAds', 'initialize']);
      expect(container.read(adsReadyProvider), isTrue);
    });

    test('consentement refusé (canRequestAds faux) : jamais initialisé',
        () async {
      final platform = FakeAdsPlatform(canRequest: false);
      final container = containerWith(platform);
      await container.read(consentControllerProvider.notifier).gather();
      expect(platform.calls, isNot(contains('initialize')));
      expect(container.read(adsReadyProvider), isFalse);
    });

    test('hors ligne : pas de formulaire, cache de la session précédente',
        () async {
      final platform =
          FakeAdsPlatform(updateError: const ConsentFailure(1, 'hors ligne'));
      final container = containerWith(platform);
      await container.read(consentControllerProvider.notifier).gather();
      expect(platform.calls, ['update', 'canRequestAds', 'initialize']);
      expect(container.read(adsReadyProvider), isTrue);
    });

    test('hors ligne au premier lancement : aucune pub, pas de crash',
        () async {
      final platform =
          FakeAdsPlatform(canRequest: false, updateError: Exception('réseau'));
      final container = containerWith(platform);
      await container.read(consentControllerProvider.notifier).gather();
      expect(platform.calls, isNot(contains('initialize')));
      expect(container.read(adsReadyProvider), isFalse);
    });

    testWidgets('mise à jour sans réponse : délai de 10 s puis cache',
        (tester) async {
      final platform = FakeAdsPlatform(pendingUpdate: Completer());
      final container = containerWith(platform);
      var done = false;
      unawaited(container
          .read(consentControllerProvider.notifier)
          .gather()
          .then((_) => done = true));

      await tester.pump(const Duration(seconds: 9));
      expect(done, isFalse);
      expect(platform.calls, ['update']);

      await tester.pump(const Duration(seconds: 2));
      expect(done, isTrue);
      expect(platform.calls, ['update', 'canRequestAds', 'initialize']);
      expect(container.read(adsReadyProvider), isTrue);
    });

    testWidgets('réponse tardive après le délai : statut relu', (tester) async {
      final update = Completer<void>();
      final platform =
          FakeAdsPlatform(canRequest: false, pendingUpdate: update);
      final container = containerWith(platform);
      final gathering =
          container.read(consentControllerProvider.notifier).gather();
      await tester.pump(const Duration(seconds: 11));
      await gathering;
      expect(container.read(adsReadyProvider), isFalse);
      expect(platform.count('initialize'), 0);

      platform.canRequest = true;
      update.complete();
      await tester.pump();
      expect(platform.count('canRequestAds'), 2);
      expect(platform.count('initialize'), 1);
      expect(container.read(adsReadyProvider), isTrue);
      await tester.pump(const Duration(milliseconds: 1)); // file de Riverpod
    });

    test('double appui : un seul formulaire d\'options', () async {
      final form = Completer<void>();
      final platform =
          FakeAdsPlatform(optionsRequired: true, pendingPrivacyForm: form);
      final container = containerWith(platform);
      final notifier = container.read(consentControllerProvider.notifier);
      final first = notifier.showPrivacyOptions();
      final second = notifier.showPrivacyOptions();
      await Future<void>.delayed(Duration.zero);
      expect(platform.count('privacyForm'), 1);
      form.complete();
      await Future.wait([first, second]);

      // Formulaire fermé : un nouvel appui le rouvre.
      platform.pendingPrivacyForm = null;
      await notifier.showPrivacyOptions();
      expect(platform.count('privacyForm'), 2);
    });

    test('MobileAds initialisé une seule fois, même en parallèle', () async {
      final init = Completer<void>();
      final platform = FakeAdsPlatform(pendingInit: init);
      final container = containerWith(platform);
      final notifier = container.read(consentControllerProvider.notifier);
      final a = notifier.gather();
      final b = notifier.showPrivacyOptions();
      await Future<void>.delayed(Duration.zero);
      init.complete();
      await Future.wait([a, b]);
      await notifier.showPrivacyOptions();
      expect(platform.count('initialize'), 1);
      expect(container.read(adsReadyProvider), isTrue);
    });

    test('échec de l\'initialisation : pas de pub, nouvel essai ensuite',
        () async {
      final platform = FakeAdsPlatform(initError: Exception('SDK'));
      final container = containerWith(platform);
      final notifier = container.read(consentControllerProvider.notifier);
      await notifier.gather();
      expect(container.read(adsReadyProvider), isFalse);

      platform.initError = null;
      await notifier.showPrivacyOptions();
      expect(platform.count('initialize'), 2);
      expect(container.read(adsReadyProvider), isTrue);
    });

    test('une seule demande par lancement', () async {
      final platform = FakeAdsPlatform();
      final container = containerWith(platform);
      final notifier = container.read(consentControllerProvider.notifier);
      await Future.wait([notifier.gather(), notifier.gather()]);
      await notifier.gather();
      expect(platform.calls.where((c) => c == 'update'), hasLength(1));
      expect(platform.calls.where((c) => c == 'initialize'), hasLength(1));
    });

    test('options de confidentialité : acceptation ensuite → pubs prêtes',
        () async {
      final platform =
          FakeAdsPlatform(canRequest: false, optionsRequired: true);
      final container = containerWith(platform);
      final notifier = container.read(consentControllerProvider.notifier);
      await notifier.gather();
      expect(container.read(privacyOptionsRequiredProvider), isTrue);
      expect(container.read(adsReadyProvider), isFalse);

      platform.canRequest = true;
      await notifier.showPrivacyOptions();
      expect(platform.calls.sublist(platform.calls.indexOf('privacyForm')),
          ['privacyForm', 'canRequestAds', 'initialize']);
      expect(container.read(adsReadyProvider), isTrue);
    });
  });

  group('debug EEE', () {
    test('jamais actif en release', () {
      expect(
        consentDebugSettings(
            debugMode: false, forceEea: true, testDeviceId: 'abc'),
        isNull,
      );
    });

    test('inactif en debug sans UMP_DEBUG_EEA', () {
      expect(consentDebugSettings(debugMode: true, forceEea: false), isNull);
    });

    test('debug + UMP_DEBUG_EEA : géographie EEE et appareil de test', () {
      final s = consentDebugSettings(
          debugMode: true, forceEea: true, testDeviceId: 'abc');
      expect(s?.debugGeography, DebugGeography.debugGeographyEea);
      expect(s?.testIdentifiers, ['abc']);
      expect(
        consentDebugSettings(debugMode: true, forceEea: true, testDeviceId: '')
            ?.testIdentifiers,
        isNull,
      );
    });

    test('valeur par défaut des tests : aucun réglage de debug', () {
      expect(consentDebugSettings(), isNull);
    });
  });

  group('Profil', () {
    Future<FakeAdsPlatform> pumpProfile(WidgetTester tester,
        {required bool optionsRequired}) async {
      tester.view.physicalSize = const Size(390, 1100);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final platform = FakeAdsPlatform(optionsRequired: optionsRequired);
      await tester.pumpWidget(ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          adsPlatformProvider.overrideWithValue(platform),
        ],
        child: Consumer(
          builder: (context, ref, _) {
            ref.watch(consentStartupProvider);
            return MaterialApp(
              theme: AppTheme.light,
              home: const Scaffold(body: ProfileScreen()),
            );
          },
        ),
      ));
      await tester.pumpAndSettle();
      return platform;
    }

    const label = 'Gérer mes choix de confidentialité';

    testWidgets('entrée affichée si UMP l\'exige, ouvre le formulaire',
        (tester) async {
      final platform = await pumpProfile(tester, optionsRequired: true);
      expect(find.text(label), findsOneWidget);
      await tester.tap(find.text(label));
      await tester.pumpAndSettle();
      expect(platform.calls, contains('privacyForm'));
    });

    testWidgets('entrée masquée sinon', (tester) async {
      await pumpProfile(tester, optionsRequired: false);
      expect(find.text(label), findsNothing);
    });
  });
}
