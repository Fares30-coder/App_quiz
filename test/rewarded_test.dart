import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:quizzeo/ads/banner_ads.dart';
import 'package:quizzeo/ads/consent_service.dart';
import 'package:quizzeo/ads/rewarded_ads.dart';
import 'package:quizzeo/data/progress_repository.dart';
import 'package:quizzeo/engagement/dates.dart';
import 'package:quizzeo/engagement/progress_controller.dart';
import 'package:quizzeo/models/player_progress.dart';
import 'package:quizzeo/models/streak.dart';
import 'package:quizzeo/screens/streak_screen.dart';
import 'package:quizzeo/theme/app_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FakeRewarded implements LoadedRewarded {
  FakeRewarded({required this.earns});

  final bool earns;
  int shows = 0;
  bool disposed = false;

  /// Si non nul, la vidéo reste « à l'écran » jusqu'à ce que le test le complète.
  Completer<void>? closing;

  @override
  Future<bool> show() async {
    shows++;
    await closing?.future;
    disposed = true;
    return earns;
  }

  @override
  void dispose() => disposed = true;
}

/// Faux SDK : enregistre les chargements ; [pending] retient le prochain.
class FakeRewardedLoader implements RewardedLoader {
  bool fail = false;
  bool earns = true;
  Completer<void>? pending;
  Completer<void>? closing;
  final ads = <FakeRewarded>[];
  int loads = 0;

  @override
  Future<LoadedRewarded?> load() async {
    loads++;
    await pending?.future;
    if (fail) return null;
    final ad = FakeRewarded(earns: earns)..closing = closing;
    ads.add(ad);
    return ad;
  }
}

class FakeGranter implements FreezeGranter {
  FakeGranter({this.onGrant});

  bool isReady = true;
  RewardedFreezeOutcome outcome = RewardedFreezeOutcome.granted;
  int grants = 0;
  final void Function()? onGrant;

  @override
  bool get ready => isReady;

  @override
  Future<RewardedFreezeOutcome> grant() async {
    grants++;
    onGrant?.call();
    return outcome;
  }
}

final _ready = StateProvider<bool>((ref) => false);
final _removed = StateProvider<bool>((ref) => false);

Future<void> settle() async {
  for (var i = 0; i < 5; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

class Harness {
  Harness({bool ready = true}) {
    container = ProviderContainer(overrides: [
      adsReadyProvider.overrideWith((ref) => ref.watch(_ready)),
      adsRemovedProvider.overrideWith((ref) => ref.watch(_removed)),
      rewardedLoaderProvider.overrideWithValue(loader),
      freezeGranterProvider.overrideWithValue(granter),
      clockProvider.overrideWithValue(() => now),
    ]);
    container.read(_ready.notifier).state = ready;
    container.listen(rewardedFreezeControllerProvider, (_, __) {});
  }

  final loader = FakeRewardedLoader();
  final granter = FakeGranter();
  late final ProviderContainer container;
  DateTime now = DateTime(2026, 11, 27, 21);

  RewardedFreezeController get ads =>
      container.read(rewardedFreezeControllerProvider.notifier);
  RewardedStatus get status => container.read(rewardedFreezeControllerProvider);

  set ready(bool value) => container.read(_ready.notifier).state = value;
  set removed(bool value) => container.read(_removed.notifier).state = value;
}

Harness harness({bool ready = true}) {
  final h = Harness(ready: ready);
  addTearDown(h.container.dispose);
  return h;
}

/// Construit par morceaux : `tool/check_config.sh` refuse tout vrai ID écrit en clair.
final _fakeRealId = 'ca-app-pub-${'1' * 16}/${'2' * 10}';

void main() {
  group('rewardedAdUnitId', () {
    test('debug : ID de test, même avec un vrai ID', () {
      expect(
          rewardedAdUnitId(
              platform: TargetPlatform.android,
              releaseMode: false,
              androidId: _fakeRealId),
          testRewardedIdAndroid);
      expect(rewardedAdUnitId(platform: TargetPlatform.iOS, releaseMode: false),
          testRewardedIdIos);
    });

    test('release : vrai ID, ou erreur si exigé et absent', () {
      expect(
          rewardedAdUnitId(
              platform: TargetPlatform.iOS,
              releaseMode: true,
              iosId: _fakeRealId),
          _fakeRealId);
      expect(
          () => rewardedAdUnitId(
              platform: TargetPlatform.android,
              releaseMode: true,
              requireReal: true),
          throwsStateError);
    });
  });

  group('RewardedFreezeController', () {
    test('rien chargé tant que l\'offre n\'est pas ouverte', () async {
      final h = harness();
      await settle();
      expect(h.loader.loads, 0);
      expect(h.status, RewardedStatus.unavailable);
    });

    test('pubs non autorisées : aucun chargement', () async {
      final h = harness(ready: false);
      h.ads.prepare();
      await settle();
      expect(h.loader.loads, 0);

      h.ready = true;
      h.removed = true;
      h.ads.prepare();
      await settle();
      expect(h.loader.loads, 0, reason: 'achat « sans pub »');
    });

    test('prepare : chargement puis prête', () async {
      final h = harness();
      h.loader.pending = Completer<void>();
      h.ads.prepare();
      await settle();
      expect(h.status, RewardedStatus.loading);
      h.loader.pending!.complete();
      await settle();
      expect(h.status, RewardedStatus.ready);
      h.ads.prepare();
      await settle();
      expect(h.loader.loads, 1, reason: 'pas de second chargement');
    });

    test('vidéo regardée jusqu\'au bout : gel demandé, pas de rechargement',
        () async {
      final h = harness();
      h.ads.prepare();
      await settle();

      final outcome = await h.ads.watchForFreeze();
      expect(outcome, RewardedFreezeOutcome.granted);
      expect(h.granter.grants, 1);
      expect(h.loader.ads.single.shows, 1);
      expect(h.loader.ads.single.disposed, isTrue);
      await settle();
      expect(h.loader.loads, 1);
      expect(h.status, RewardedStatus.unavailable);
    });

    test('vidéo interrompue : aucun gel, nouvelle pub chargée', () async {
      final h = harness();
      h.loader.earns = false;
      h.ads.prepare();
      await settle();

      expect(await h.ads.watchForFreeze(), RewardedFreezeOutcome.notEarned);
      expect(h.granter.grants, 0);
      await settle();
      expect(h.loader.loads, 2);
      expect(h.status, RewardedStatus.ready);
    });

    test('refus du serveur transmis', () async {
      final h = harness();
      h.granter.outcome = RewardedFreezeOutcome.dailyLimit;
      h.ads.prepare();
      await settle();
      expect(await h.ads.watchForFreeze(), RewardedFreezeOutcome.dailyLimit);
    });

    test('pas de session : la vidéo n\'est pas montrée', () async {
      final h = harness();
      h.granter.isReady = false;
      h.ads.prepare();
      await settle();

      expect(await h.ads.watchForFreeze(), RewardedFreezeOutcome.failed);
      expect(h.loader.ads.single.shows, 0);
      expect(h.status, RewardedStatus.ready, reason: 'pub gardée');
    });

    test('aucune pub prête : unavailable, rien de montré', () async {
      final h = harness();
      h.loader.fail = true;
      h.ads.prepare();
      await settle();
      expect(await h.ads.watchForFreeze(), RewardedFreezeOutcome.unavailable);
      expect(h.granter.grants, 0);
    });

    test('double appui : une seule vidéo', () async {
      final h = harness();
      h.loader.closing = Completer<void>();
      h.ads.prepare();
      await settle();

      final first = h.ads.watchForFreeze();
      final second = h.ads.watchForFreeze();
      await settle();
      expect(h.status, RewardedStatus.busy);
      h.loader.closing!.complete();
      expect(await first, RewardedFreezeOutcome.granted);
      expect(await second, RewardedFreezeOutcome.granted);
      expect(h.loader.ads.single.shows, 1);
      expect(h.granter.grants, 1);
    });

    test('consentement retiré : pub libérée, rechargée s\'il revient',
        () async {
      final h = harness();
      h.ads.prepare();
      await settle();

      h.ready = false;
      await settle();
      expect(h.loader.ads.single.disposed, isTrue);
      expect(h.status, RewardedStatus.unavailable);
      expect(await h.ads.watchForFreeze(), RewardedFreezeOutcome.unavailable);

      h.ready = true;
      await settle();
      expect(h.loader.loads, 2);
      expect(h.status, RewardedStatus.ready);
    });

    test('échec de chargement : nouvel essai après le délai', () async {
      final h = harness();
      h.loader.fail = true;
      h.ads.prepare();
      await settle();
      h.ads.prepare();
      await settle();
      expect(h.loader.loads, 1, reason: 'dans le délai');

      h.loader.fail = false;
      h.now = h.now.add(RewardedFreezeController.retryDelay);
      h.ads.prepare();
      await settle();
      expect(h.loader.loads, 2);
      expect(h.status, RewardedStatus.ready);
    });

    test('pub trop ancienne : remplacée, jamais montrée', () async {
      final h = harness();
      h.ads.prepare();
      await settle();
      h.now = h.now.add(RewardedFreezeController.maxAdAge);

      expect(await h.ads.watchForFreeze(), RewardedFreezeOutcome.unavailable);
      expect(h.loader.ads.first.shows, 0);
      expect(h.loader.ads.first.disposed, isTrue);
      await settle();
      expect(h.loader.loads, 2);
    });
  });

  group('écran Série (danger)', () {
    final now = DateTime(2026, 11, 27, 21);
    final today = dayOf(now);

    Future<FakeRewardedLoader> pumpDanger(
      WidgetTester tester, {
      bool ready = true,
      bool removed = false,
      bool earns = true,
    }) async {
      tester.view.physicalSize = const Size(390, 1100);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final progress = PlayerProgress(
        onboardingDone: true,
        streak: Streak(
          count: 4,
          lastPlayed: addDays(today, -1),
          playedDays: {addDays(today, -1)},
        ),
      );
      SharedPreferences.setMockInitialValues(
          {'progress_v1': jsonEncode(progress.toJson())});
      final prefs = await SharedPreferences.getInstance();
      final loader = FakeRewardedLoader()..earns = earns;
      await tester.pumpWidget(ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          clockProvider.overrideWithValue(() => now),
          adsReadyProvider.overrideWithValue(ready),
          adsRemovedProvider.overrideWithValue(removed),
          rewardedLoaderProvider.overrideWithValue(loader),
          freezeGranterProvider.overrideWith((ref) => FakeGranter(
              onGrant: () => ref
                  .read(progressControllerProvider.notifier)
                  .addStreakFreeze())),
        ],
        child: MaterialApp(
          theme: AppTheme.light,
          home: const StreakScreen(mode: StreakScreenMode.danger),
        ),
      ));
      await tester.pump();
      await tester.pump();
      return loader;
    }

    testWidgets('pub prête : gel ajouté à la fin de la vidéo', (tester) async {
      final loader = await pumpDanger(tester);
      expect(loader.loads, 1, reason: 'pub chargée à l\'ouverture');
      expect(find.text('Pas le temps aujourd\'hui ?'), findsOneWidget);

      await tester.tap(find.text('Regarder une pub pour un gel'));
      await tester.pump();
      await tester.pump();

      expect(find.text('Gel ajouté ! Ta série est protégée.'), findsOneWidget);
      expect(find.text('Ta série est protégée'), findsOneWidget);
      expect(find.text('Regarder une pub pour un gel'), findsNothing);
    });

    testWidgets('vidéo interrompue : aucun gel', (tester) async {
      await pumpDanger(tester, earns: false);
      await tester.tap(find.text('Regarder une pub pour un gel'));
      await tester.pump();
      await tester.pump();

      expect(
          find.text('Vidéo interrompue : aucun gel ajouté.'), findsOneWidget);
      expect(find.text('Pas le temps aujourd\'hui ?'), findsOneWidget);
    });

    testWidgets('pas de consentement : bouton désactivé', (tester) async {
      final loader = await pumpDanger(tester, ready: false);
      expect(loader.loads, 0);
      final button = tester.widget<ButtonStyleButton>(find.ancestor(
          of: find.text('Pas de pub disponible pour le moment'),
          matching: find.byWidgetPredicate((w) => w is ButtonStyleButton)));
      expect(button.onPressed, isNull);
    });

    testWidgets('achat « sans pub » : pas d\'offre de pub', (tester) async {
      final loader = await pumpDanger(tester, removed: true);
      expect(loader.loads, 0);
      expect(find.byIcon(Icons.smart_display_outlined), findsNothing);
    });
  });
}
