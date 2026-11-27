import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:quizzeo/ads/banner_ads.dart';
import 'package:quizzeo/ads/consent_service.dart';
import 'package:quizzeo/ads/interstitial_ads.dart';
import 'package:quizzeo/ads/interstitial_pacing.dart';
import 'package:quizzeo/engagement/progress_controller.dart';
import 'package:quizzeo/main.dart';
import 'package:quizzeo/screens/quiz_screen.dart';

import 'widget_test.dart' show playChallenge, pumpApp;

class FakeInterstitial implements LoadedInterstitial {
  FakeInterstitial({this.showFails = false});

  final bool showFails;
  bool shown = false;
  bool disposed = false;

  /// Si non nul, la pub reste « à l'écran » jusqu'à ce que le test le complète.
  Completer<void>? closing;

  @override
  Future<bool> show() async {
    shown = true;
    await closing?.future;
    disposed = true;
    return !showFails;
  }

  @override
  void dispose() => disposed = true;
}

/// Faux SDK : enregistre les chargements ; [pending] retient le prochain.
class FakeInterstitialLoader implements InterstitialLoader {
  bool fail = false;
  bool error = false;
  bool showFails = false;
  Completer<void>? pending;
  final ads = <FakeInterstitial>[];
  int loads = 0;

  @override
  Future<LoadedInterstitial?> load() async {
    loads++;
    await pending?.future;
    if (error) throw StateError('SDK');
    if (fail) return null;
    final ad = FakeInterstitial(showFails: showFails);
    ads.add(ad);
    return ad;
  }
}

final _ready = StateProvider<bool>((ref) => false);
final _removed = StateProvider<bool>((ref) => false);

/// Laisse passer les `await` des faux chargements.
Future<void> settle() async {
  for (var i = 0; i < 5; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

/// Vrai si [future] se termine sans aide extérieure (pas d'attente du loader).
Future<bool> finishesAlone(Future<void> future) async {
  var done = false;
  unawaited(future.then((_) => done = true));
  await settle();
  return done;
}

class Harness {
  Harness({bool ready = true, bool removed = false}) {
    container = ProviderContainer(overrides: [
      adsReadyProvider.overrideWith((ref) => ref.watch(_ready)),
      adsRemovedProvider.overrideWith((ref) => ref.watch(_removed)),
      interstitialLoaderProvider.overrideWithValue(loader),
      clockProvider.overrideWithValue(() => now),
    ]);
    container.read(_ready.notifier).state = ready;
    container.read(_removed.notifier).state = removed;
    // Garde le contrôleur en vie, comme `RootGate` dans l'app.
    container.listen(interstitialControllerProvider, (_, __) {});
  }

  final loader = FakeInterstitialLoader();
  late final ProviderContainer container;
  DateTime now = DateTime(2026, 11, 27, 12);

  InterstitialController get ads =>
      container.read(interstitialControllerProvider.notifier);
  bool get loaded => container.read(interstitialControllerProvider);

  set ready(bool value) => container.read(_ready.notifier).state = value;
  set removed(bool value) => container.read(_removed.notifier).state = value;

  void completeQuizzes(int n) {
    for (var i = 0; i < n; i++) {
      ads.quizCompleted();
    }
  }
}

Harness harness({bool ready = true, bool removed = false}) {
  final h = Harness(ready: ready, removed: removed);
  addTearDown(h.container.dispose);
  return h;
}

/// Construit par morceaux : `tool/check_config.sh` refuse tout vrai ID écrit en clair.
final _fakeRealId = 'ca-app-pub-${'1' * 16}/${'2' * 10}';

void main() {
  group('InterstitialPacing', () {
    late DateTime now;
    late InterstitialPacing pacing;

    setUp(() {
      now = DateTime(2026, 11, 27, 12);
      pacing = InterstitialPacing(clock: () => now);
    });

    test('valeurs par défaut', () {
      expect(InterstitialPacing.defaultQuizzesPerAd, 2);
      expect(InterstitialPacing.defaultMinInterval, const Duration(minutes: 3));
      expect(InterstitialPacing.defaultFirstAdAfterQuizzes, 2);
    });

    test('rien avant le premier quiz ni après le premier quiz de la session',
        () {
      expect(pacing.canShow, isFalse);
      pacing.quizCompleted();
      expect(pacing.canShow, isFalse);
      pacing.quizCompleted();
      expect(pacing.canShow, isTrue);
    });

    test('compteur : au plus 1 pub tous les 2 quiz terminés', () {
      pacing
        ..quizCompleted()
        ..quizCompleted()
        ..adShown();
      now = now.add(const Duration(hours: 1));
      expect(pacing.canShow, isFalse);
      pacing.quizCompleted();
      expect(pacing.canShow, isFalse);
      pacing.quizCompleted();
      expect(pacing.canShow, isTrue);
    });

    test('délai : au plus 1 pub toutes les 3 min', () {
      pacing
        ..quizCompleted()
        ..quizCompleted()
        ..adShown()
        ..quizCompleted()
        ..quizCompleted();
      now = now.add(const Duration(minutes: 2, seconds: 59));
      expect(pacing.canShow, isFalse);
      now = now.add(const Duration(seconds: 1));
      expect(pacing.canShow, isTrue);
    });

    test('seuils modifiables', () {
      final p = InterstitialPacing(
        clock: () => now,
        quizzesPerAd: 1,
        minInterval: Duration.zero,
        firstAdAfterQuizzes: 1,
      );
      p.quizCompleted();
      expect(p.canShow, isTrue);
      p.adShown();
      expect(p.canShow, isFalse);
      p.quizCompleted();
      expect(p.canShow, isTrue);
    });
  });

  group('interstitialAdUnitId', () {
    test('debug : ID de test, même si un vrai ID est fourni', () {
      expect(
        interstitialAdUnitId(
          platform: TargetPlatform.android,
          releaseMode: false,
          androidId: _fakeRealId,
        ),
        testInterstitialIdAndroid,
      );
      expect(
        interstitialAdUnitId(platform: TargetPlatform.iOS, releaseMode: false),
        testInterstitialIdIos,
      );
    });

    test('release : vrai ID injecté, sinon repli sur l\'ID de test', () {
      expect(
        interstitialAdUnitId(
          platform: TargetPlatform.iOS,
          releaseMode: true,
          iosId: _fakeRealId,
        ),
        _fakeRealId,
      );
      expect(
        interstitialAdUnitId(
            platform: TargetPlatform.android, releaseMode: true),
        testInterstitialIdAndroid,
      );
    });

    test('REQUIRE_REAL_AD_UNITS : erreur en release sans vrai ID', () {
      for (final id in ['', 'ca-app-pub-1234~5678', testInterstitialIdIos]) {
        expect(
          () => interstitialAdUnitId(
            platform: TargetPlatform.iOS,
            releaseMode: true,
            requireReal: true,
            iosId: id,
          ),
          throwsStateError,
          reason: 'ID « $id »',
        );
      }
    });
  });

  group('InterstitialController', () {
    test('sans consentement : aucune requête à la régie', () async {
      final h = harness(ready: false);
      await settle();
      h.completeQuizzes(3);
      await h.ads.showIfDue();
      await settle();
      expect(h.loader.loads, 0);
      expect(h.loaded, isFalse);
    });

    test('consentement donné : préchargement unique', () async {
      final h = harness(ready: false);
      h.ready = true;
      await settle();
      expect(h.loader.loads, 1);
      expect(h.loaded, isTrue);
      h.completeQuizzes(1);
      await settle();
      expect(h.loader.loads, 1, reason: 'déjà chargée');
    });

    test('consentement retiré : pub chargée libérée, pas de rechargement',
        () async {
      final h = harness();
      await settle();
      h.ready = false;
      await settle();
      expect(h.loader.ads.single.disposed, isTrue);
      expect(h.loaded, isFalse);
      h.completeQuizzes(2);
      await h.ads.showIfDue();
      expect(h.loader.loads, 1);
      expect(h.loader.ads.single.shown, isFalse);
    });

    test('consentement retiré pendant le chargement : pub libérée à l\'arrivée',
        () async {
      final h = harness(ready: false);
      h.loader.pending = Completer<void>();
      h.ready = true;
      await settle();
      h.ready = false;
      await settle();
      h.loader.pending!.complete();
      await settle();
      expect(h.loader.ads.single.disposed, isTrue);
      expect(h.loaded, isFalse);
    });

    test('« sans pub » : aucun chargement, pub déjà chargée libérée', () async {
      final none = harness(removed: true);
      await settle();
      none.completeQuizzes(2);
      await none.ads.showIfDue();
      expect(none.loader.loads, 0);

      final h = harness();
      await settle();
      h.removed = true;
      await settle();
      expect(h.loader.ads.single.disposed, isTrue);
      expect(h.loaded, isFalse);
    });

    test('premier quiz de la session : pas de pub', () async {
      final h = harness();
      await settle();
      h.completeQuizzes(1);
      await h.ads.showIfDue();
      expect(h.loader.ads.single.shown, isFalse);
      expect(h.loaded, isTrue, reason: 'gardée pour plus tard');
    });

    test('affichée au 2e quiz puis rechargée ; plafond compteur et délai',
        () async {
      final h = harness();
      await settle();
      h.completeQuizzes(2);
      await h.ads.showIfDue();
      await settle();
      expect(h.loader.ads.first.shown, isTrue);
      expect(h.loader.loads, 2, reason: 'rechargée après affichage');
      expect(h.loaded, isTrue);

      // 2 quiz de plus mais moins de 3 min : rien.
      h.completeQuizzes(2);
      h.now = h.now.add(const Duration(minutes: 2));
      await h.ads.showIfDue();
      expect(h.loader.ads[1].shown, isFalse);

      // 3 min passées : affichée.
      h.now = h.now.add(const Duration(minutes: 1));
      await h.ads.showIfDue();
      expect(h.loader.ads[1].shown, isTrue);

      // Délai écoulé mais un seul quiz depuis : rien.
      await settle();
      h.completeQuizzes(1);
      h.now = h.now.add(const Duration(minutes: 10));
      await h.ads.showIfDue();
      expect(h.loader.ads[2].shown, isFalse);
    });

    test('pub pas prête : ne bloque pas, rien affiché', () async {
      final h = harness(ready: false);
      h.loader.pending = Completer<void>(); // jamais terminé
      h.ready = true;
      await settle();
      h.completeQuizzes(2);
      expect(await finishesAlone(h.ads.showIfDue()), isTrue);
      expect(h.loader.loads, 1, reason: 'pas de 2e chargement en parallèle');
    });

    test('nouvel essai après échec : showIfDue n\'attend pas le chargement',
        () async {
      final h = harness(ready: false);
      h.loader.fail = true;
      h.ready = true;
      await settle();
      h.completeQuizzes(2);
      h.now = h.now.add(InterstitialController.retryDelay);
      h.loader.pending = Completer<void>(); // jamais terminé
      expect(await finishesAlone(h.ads.showIfDue()), isTrue);
      expect(h.loader.loads, 2, reason: 'nouvel essai lancé en arrière-plan');
    });

    test('pub trop ancienne : showIfDue n\'attend pas son remplacement',
        () async {
      final h = harness();
      await settle();
      h.completeQuizzes(2);
      h.now = h.now.add(InterstitialController.maxAdAge);
      h.loader.pending = Completer<void>(); // jamais terminé
      expect(await finishesAlone(h.ads.showIfDue()), isTrue);
      expect(h.loader.ads.single.shown, isFalse);
      expect(h.loader.ads.single.disposed, isTrue);
      expect(h.loader.loads, 2);
    });

    test('après fermeture : showIfDue n\'attend pas le rechargement', () async {
      final h = harness();
      await settle();
      h.completeQuizzes(2);
      h.loader.pending = Completer<void>(); // rechargement jamais terminé
      expect(await finishesAlone(h.ads.showIfDue()), isTrue);
      expect(h.loader.ads.single.shown, isTrue);
      expect(h.loader.loads, 2);
    });

    test('pub à l\'écran : un 2e appel attend la même fermeture', () async {
      final h = harness();
      await settle();
      h.completeQuizzes(2);
      final closing = h.loader.ads.first.closing = Completer<void>();
      final first = h.ads.showIfDue();
      final second = h.ads.showIfDue();
      expect(await finishesAlone(second), isFalse, reason: 'pub à l\'écran');
      expect(h.loader.loads, 1, reason: 'pas de rechargement pendant la pub');
      closing.complete();
      await Future.wait([first, second]);
      await settle();
      expect(h.loader.ads.first.shown, isTrue);
      expect(h.loader.loads, 2);
      expect(h.ads.pacing.quizzesSinceAd, 0, reason: 'une seule pub comptée');
    });

    test('loader en erreur : traité comme un échec', () async {
      final h = harness(ready: false);
      h.loader.error = true;
      h.ready = true;
      await settle();
      expect(h.loaded, isFalse);
      h.now = h.now.add(InterstitialController.retryDelay);
      h.loader.error = false;
      h.completeQuizzes(1);
      await settle();
      expect(h.loader.loads, 2, reason: '_loading bien remis à faux');
      expect(h.loaded, isTrue);
    });

    test('échec d\'affichage : pas compté, pub rechargée', () async {
      final h = harness();
      h.loader.showFails = true;
      await settle();
      h.completeQuizzes(2);
      await h.ads.showIfDue();
      await settle();
      expect(h.ads.pacing.quizzesSinceAd, 2);
      expect(h.loader.loads, 2);
    });

    test('échec de chargement : nouvel essai espacé, sans boucle', () async {
      final h = harness(ready: false);
      h.loader.fail = true;
      h.ready = true;
      await settle();
      expect(h.loader.loads, 1);
      h.completeQuizzes(1);
      await h.ads.showIfDue();
      await settle();
      expect(h.loader.loads, 1, reason: 'délai de nouvel essai non écoulé');

      h.now = h.now.add(InterstitialController.retryDelay);
      h.loader.fail = false;
      h.completeQuizzes(1);
      await settle();
      expect(h.loader.loads, 2);
      expect(h.loaded, isTrue);
    });

    test('pub trop ancienne : remplacée au lieu d\'être affichée', () async {
      final h = harness();
      await settle();
      h.completeQuizzes(2);
      h.now = h.now.add(InterstitialController.maxAdAge);
      await h.ads.showIfDue();
      await settle();
      expect(h.loader.ads.first.shown, isFalse);
      expect(h.loader.ads.first.disposed, isTrue);
      expect(h.loader.loads, 2);
    });

    test('démontage : pub libérée', () async {
      final h = Harness();
      await settle();
      h.container.dispose();
      expect(h.loader.ads.single.disposed, isTrue);
    });
  });

  testWidgets(
      'parcours : pas de pub pendant le quiz ni la série, '
      'affichée en revenant à l\'accueil', (tester) async {
    final loader = FakeInterstitialLoader();
    await pumpApp(
      tester,
      {'progress_v1': '{"onboardingDone":true}'},
      height: 844,
      overrides: [
        adsReadyProvider.overrideWithValue(true),
        interstitialLoaderProvider.overrideWithValue(loader),
      ],
    );
    await tester.pump();
    final container =
        ProviderScope.containerOf(tester.element(find.byType(QuizzeoApp)));
    final ads = container.read(interstitialControllerProvider.notifier);
    expect(loader.loads, 1, reason: 'préchargée à l\'accueil');
    // Un quiz déjà terminé plus tôt dans la session.
    ads.quizCompleted();

    await playChallenge(tester);
    expect(ads.pacing.quizzesInSession, 2, reason: 'quiz terminé compté');
    await tester.pump(const Duration(seconds: 2));
    expect(find.text('XP gagnés'), findsOneWidget);
    expect(loader.ads.single.shown, isFalse, reason: 'quiz et résultats');

    final ad = loader.ads.single;
    final closing = ad.closing = Completer<void>();
    await tester.scrollUntilVisible(find.text('Continuer').hitTestable(), 200);
    await tester.tap(find.text('Continuer'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    expect(find.text('Série validée !'), findsOneWidget);

    // Fermeture demandée en pleine animation de série : la pub attend la fin.
    await tester.tap(find.widgetWithText(FilledButton, 'Continuer'));
    await tester.pump(const Duration(milliseconds: 100));
    expect(ad.shown, isFalse, reason: 'animation de série en cours');
    await tester.pump(const Duration(seconds: 1));
    expect(ad.shown, isTrue, reason: 'après l\'animation');
    // La pub sert de transition : l'écran Série reste dessous jusqu'à sa
    // fermeture (accueil jamais touchable avant la pub).
    expect(find.text('Série validée !'), findsOneWidget);
    expect(loader.loads, 1, reason: 'pas de rechargement pendant la pub');

    closing.complete();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Série validée !'), findsNothing, reason: 'accueil');
    expect(loader.loads, 2, reason: 'rechargée après affichage');
  });

  testWidgets(
      'quiz lancé pendant une pub : démarre après sa fermeture, '
      'sans attendre le rechargement', (tester) async {
    final loader = FakeInterstitialLoader();
    await pumpApp(
      tester,
      {'progress_v1': '{"onboardingDone":true}'},
      overrides: [
        adsReadyProvider.overrideWithValue(true),
        interstitialLoaderProvider.overrideWithValue(loader),
      ],
    );
    await tester.pump();
    final container =
        ProviderScope.containerOf(tester.element(find.byType(QuizzeoApp)));
    final ads = container.read(interstitialControllerProvider.notifier);
    ads
      ..quizCompleted()
      ..quizCompleted();
    final closing = loader.ads.single.closing = Completer<void>();
    loader.pending = Completer<void>(); // rechargement jamais terminé

    // Pub ouverte depuis les résultats, puis quiz lancé.
    unawaited(ads.showIfDue());
    await tester.pump();
    expect(loader.ads.single.shown, isTrue);
    await tester.ensureVisible(find.text('Jouer le défi'));
    await tester.tap(find.text('Jouer le défi'));
    for (var i = 0; i < 5; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.byType(QuizScreen), findsNothing, reason: 'pub à l\'écran');

    closing.complete();
    for (var i = 0; i < 20 && find.text('A').evaluate().isEmpty; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(QuizScreen), findsOneWidget);
    expect(loader.loads, 2, reason: 'rechargement en cours, pas attendu');
  });
}
