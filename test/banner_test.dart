import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:material_ui/material_ui.dart';
import 'package:quizzeo/ads/banner_ads.dart';
import 'package:quizzeo/ads/consent_service.dart';
import 'package:quizzeo/theme/app_theme.dart';
import 'package:quizzeo/widgets/ad_slot.dart';

import 'widget_test.dart' show playChallenge, pumpApp;

class FakeBanner implements LoadedBanner {
  bool disposed = false;

  @override
  Widget get view => const SizedBox(key: Key('fake-banner'));

  @override
  void dispose() => disposed = true;
}

/// Faux SDK : enregistre les chargements ; [pending] retient le prochain.
class FakeBannerLoader implements BannerLoader {
  FakeBannerLoader({this.fail = false});

  bool fail;
  Completer<void>? pending;

  /// Si non nuls, `anchoredSize` ou `load` lèvent cette erreur.
  Object? sizeError;
  Object? loadError;
  final banners = <FakeBanner>[];
  int loads = 0;
  final widths = <int>[];

  @override
  Future<AdSize?> anchoredSize(int width) async {
    widths.add(width);
    if (sizeError != null) throw sizeError!;
    return AdSize(width: width, height: 62);
  }

  @override
  Future<LoadedBanner?> load(AdSize size) async {
    loads++;
    await pending?.future;
    if (loadError != null) throw loadError!;
    if (fail) return null;
    final banner = FakeBanner();
    banners.add(banner);
    return banner;
  }
}

final _ready = StateProvider<bool>((ref) => false);
final _removed = StateProvider<bool>((ref) => false);
final _choices = StateProvider<int>((ref) => 0);

Future<ProviderContainer> pumpSlot(
  WidgetTester tester,
  FakeBannerLoader loader, {
  bool ready = false,
  bool tickerEnabled = true,
  EdgeInsets padding = EdgeInsets.zero,
}) async {
  final container = ProviderContainer(overrides: [
    adsReadyProvider.overrideWith((ref) => ref.watch(_ready)),
    adsRemovedProvider.overrideWith((ref) => ref.watch(_removed)),
    bannerLoaderProvider.overrideWithValue(loader),
    consentChoicesVersionProvider.overrideWith((ref) => ref.watch(_choices)),
  ]);
  addTearDown(container.dispose);
  container.read(_ready.notifier).state = ready;
  await tester.pumpWidget(UncontrolledProviderScope(
    container: container,
    child: MaterialApp(
      theme: AppTheme.light,
      home: Scaffold(
        body:
            TickerMode(enabled: tickerEnabled, child: AdSlot(padding: padding)),
      ),
    ),
  ));
  await tester.pump();
  await tester.pump();
  return container;
}

/// Construit par morceaux : `tool/check_config.sh` refuse tout vrai ID écrit en clair.
final _fakeRealId = 'ca-app-pub-${'1' * 16}/${'2' * 10}';

final _banner = find.byKey(const Key('fake-banner'));
final _slot = find.byKey(const Key('ad-slot'));

void main() {
  group('bannerAdUnitId', () {
    test('debug : ID de test, même si un vrai ID est fourni', () {
      expect(
        bannerAdUnitId(
          platform: TargetPlatform.android,
          releaseMode: false,
          androidId: _fakeRealId,
        ),
        testBannerIdAndroid,
      );
      expect(
        bannerAdUnitId(platform: TargetPlatform.iOS, releaseMode: false),
        testBannerIdIos,
      );
    });

    test('release : vrai ID injecté par --dart-define', () {
      expect(
        bannerAdUnitId(
          platform: TargetPlatform.iOS,
          releaseMode: true,
          iosId: _fakeRealId,
        ),
        _fakeRealId,
      );
    });

    test('REQUIRE_REAL_AD_UNITS : erreur en release sans vrai ID', () {
      for (final id in ['', 'ca-app-pub-1234~5678', testBannerIdAndroid]) {
        expect(
          () => bannerAdUnitId(
            platform: TargetPlatform.android,
            releaseMode: true,
            requireReal: true,
            androidId: id,
          ),
          throwsStateError,
          reason: 'ID « $id »',
        );
      }
      expect(
        bannerAdUnitId(
          platform: TargetPlatform.iOS,
          releaseMode: true,
          requireReal: true,
          iosId: _fakeRealId,
        ),
        _fakeRealId,
      );
      // En debug, toujours l'ID de test, sans erreur.
      expect(
        bannerAdUnitId(
          platform: TargetPlatform.iOS,
          releaseMode: false,
          requireReal: true,
        ),
        testBannerIdIos,
      );
    });

    test('release sans ID ou ID invalide : repli sur l\'ID de test', () {
      expect(
        bannerAdUnitId(platform: TargetPlatform.android, releaseMode: true),
        testBannerIdAndroid,
      );
      expect(
        bannerAdUnitId(
          platform: TargetPlatform.android,
          releaseMode: true,
          androidId: 'ca-app-pub-1234~5678',
        ),
        testBannerIdAndroid,
      );
    });
  });

  group('AdSlot', () {
    testWidgets('adsReady faux : aucun chargement, rien affiché',
        (tester) async {
      final loader = FakeBannerLoader();
      await pumpSlot(tester, loader);
      expect(loader.loads, 0);
      expect(_slot, findsNothing);
    });

    testWidgets('adsReady vrai : bannière chargée et affichée', (tester) async {
      final loader = FakeBannerLoader();
      await pumpSlot(tester, loader, ready: true);
      expect(loader.loads, 1);
      expect(_banner, findsOneWidget);
      expect(tester.getSize(_slot).height, 63);
    });

    testWidgets('adsReady passe à vrai plus tard : chargement à ce moment',
        (tester) async {
      final loader = FakeBannerLoader();
      final container = await pumpSlot(tester, loader);
      container.read(_ready.notifier).state = true;
      await tester.pump();
      await tester.pump();
      expect(loader.loads, 1);
      expect(_banner, findsOneWidget);
    });

    testWidgets('adsReady repasse à faux : bannière libérée et retirée',
        (tester) async {
      final loader = FakeBannerLoader();
      final container = await pumpSlot(tester, loader, ready: true);
      container.read(_ready.notifier).state = false;
      await tester.pump();
      expect(loader.banners.single.disposed, isTrue);
      expect(_slot, findsNothing);
      await tester.pump(const Duration(seconds: 5));
      expect(loader.loads, 1);
    });

    testWidgets('retrait pendant le chargement : pub libérée dès son arrivée',
        (tester) async {
      final loader = FakeBannerLoader()..pending = Completer<void>();
      final container = await pumpSlot(tester, loader, ready: true);
      expect(_slot, findsOneWidget, reason: 'hauteur réservée');
      container.read(_ready.notifier).state = false;
      await tester.pump();
      expect(_slot, findsNothing);
      loader.pending!.complete();
      await tester.pump();
      expect(loader.banners.single.disposed, isTrue);
      expect(_banner, findsNothing);
    });

    testWidgets('échec de chargement : aucun espace vide', (tester) async {
      final loader = FakeBannerLoader(fail: true);
      await pumpSlot(tester, loader, ready: true);
      expect(loader.loads, 1);
      expect(_slot, findsNothing);
    });

    testWidgets('achat « sans pub » : aucun chargement', (tester) async {
      final loader = FakeBannerLoader();
      final container = await pumpSlot(tester, loader);
      container.read(_removed.notifier).state = true;
      container.read(_ready.notifier).state = true;
      await tester.pump();
      await tester.pump();
      expect(loader.loads, 0);
      expect(_slot, findsNothing);
    });

    testWidgets('écran caché (TickerMode inactif) : aucun chargement',
        (tester) async {
      final loader = FakeBannerLoader();
      await pumpSlot(tester, loader, ready: true, tickerEnabled: false);
      expect(loader.loads, 0);
    });

    testWidgets('rotation (largeur changée) : bannière libérée et rechargée',
        (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final loader = FakeBannerLoader();
      await pumpSlot(tester, loader, ready: true);
      expect(loader.widths, [390]);
      tester.view.physicalSize = const Size(844, 390);
      await tester.pump();
      await tester.pump();
      expect(loader.banners.first.disposed, isTrue);
      expect(loader.widths, [390, 844]);
      expect(loader.banners.last.disposed, isFalse);
      expect(_banner, findsOneWidget);
      expect(tester.getSize(_banner).width, 844);
    });

    testWidgets('largeur disponible (pas celle de l\'écran)', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final loader = FakeBannerLoader();
      final container = ProviderContainer(overrides: [
        adsReadyProvider.overrideWithValue(true),
        bannerLoaderProvider.overrideWithValue(loader),
      ]);
      addTearDown(container.dispose);
      await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.light,
          home: const Scaffold(
            body: Padding(
              padding: EdgeInsets.symmetric(horizontal: 30),
              child: AdSlot(),
            ),
          ),
        ),
      ));
      await tester.pump();
      await tester.pump();
      expect(loader.widths, [330]);
    });

    testWidgets('marge (padding) seulement quand la bannière est là',
        (tester) async {
      final loader = FakeBannerLoader();
      final container = await pumpSlot(tester, loader,
          ready: true, padding: const EdgeInsets.only(top: 24));
      expect(tester.getSize(find.byType(AdSlot)).height, 63 + 24);
      container.read(_ready.notifier).state = false;
      await tester.pump();
      expect(tester.getSize(find.byType(AdSlot)).height, 0);
    });

    testWidgets('anchoredSize lève : rien affiché, nouvel essai possible',
        (tester) async {
      final loader = FakeBannerLoader()..sizeError = Exception('SDK');
      final container = await pumpSlot(tester, loader, ready: true);
      expect(_slot, findsNothing);
      expect(tester.takeException(), isNull);

      loader.sizeError = null;
      container.read(_ready.notifier).state = false;
      await tester.pump();
      container.read(_ready.notifier).state = true;
      await tester.pump();
      await tester.pump();
      expect(_banner, findsOneWidget);
    });

    testWidgets('load lève : espace retiré, pas de blocage', (tester) async {
      final loader = FakeBannerLoader()..loadError = Exception('SDK');
      final container = await pumpSlot(tester, loader, ready: true);
      expect(_slot, findsNothing);
      expect(loader.loads, 1);

      loader.loadError = null;
      container.read(_choices.notifier).state++;
      await tester.pump();
      await tester.pump();
      expect(loader.loads, 2);
      expect(_banner, findsOneWidget);
    });

    testWidgets('chargement sans réponse puis retrait : rechargement possible',
        (tester) async {
      final loader = FakeBannerLoader()..pending = Completer<void>();
      final container = await pumpSlot(tester, loader, ready: true);
      container.read(_ready.notifier).state = false;
      await tester.pump();
      loader.pending = null;
      container.read(_ready.notifier).state = true;
      await tester.pump();
      await tester.pump();
      expect(loader.loads, 2);
      expect(_banner, findsOneWidget);
    });

    testWidgets('choix de confidentialité modifiés : bannière rechargée',
        (tester) async {
      final loader = FakeBannerLoader();
      final container = await pumpSlot(tester, loader, ready: true);
      container.read(_choices.notifier).state++;
      await tester.pump();
      await tester.pump();
      expect(loader.banners.first.disposed, isTrue);
      expect(loader.loads, 2);
      expect(loader.banners.last.disposed, isFalse);
      expect(_banner, findsOneWidget);
    });

    testWidgets('démontage : bannière libérée', (tester) async {
      final loader = FakeBannerLoader();
      await pumpSlot(tester, loader, ready: true);
      await tester.pumpWidget(const SizedBox());
      expect(loader.banners.single.disposed, isTrue);
    });
  });

  group('awaitAdLoad', () {
    testWidgets('chargé : pub rendue, pas de libération', (tester) async {
      final done = Completer<String?>();
      var disposed = false;
      final result = awaitAdLoad(
          done, () async => done.complete('pub'), () => disposed = true);
      expect(await result, 'pub');
      await tester.pump(const Duration(seconds: 31));
      expect(disposed, isFalse);
    });

    testWidgets('load lève : null et pub libérée', (tester) async {
      final done = Completer<String?>();
      var disposed = 0;
      final result = awaitAdLoad<String>(
          done, () => throw Exception('SDK'), () => disposed++);
      expect(await result, isNull);
      expect(disposed, 1);
    });

    testWidgets('aucune réponse : null après 30 s et pub libérée',
        (tester) async {
      final done = Completer<String?>();
      var disposed = 0;
      String? value = 'en attente';
      unawaited(awaitAdLoad<String>(done, () async {}, () => disposed++)
          .then((v) => value = v));
      await tester.pump(const Duration(seconds: 29));
      expect(value, 'en attente');
      await tester.pump(const Duration(seconds: 2));
      expect(value, isNull);
      expect(disposed, 1);
      expect(done.isCompleted, isTrue, reason: 'réponse tardive ignorée');
    });
  });

  testWidgets('accueil et résultats avec bannière, jamais pendant le quiz',
      (tester) async {
    final loader = FakeBannerLoader();
    await pumpApp(
      tester,
      {'progress_v1': '{"onboardingDone":true}'},
      overrides: [
        adsReadyProvider.overrideWithValue(true),
        bannerLoaderProvider.overrideWithValue(loader),
      ],
    );
    await tester.pump();
    expect(_banner, findsOneWidget, reason: 'accueil');
    expect(
      tester.getTopLeft(find.byType(NavigationBar)).dy -
          tester.getBottomLeft(_slot).dy,
      greaterThanOrEqualTo(12),
      reason: 'écart bannière / barre de navigation',
    );
    final home = loader.banners.single;

    await tester.ensureVisible(find.text('Jouer le défi'));
    await tester.tap(find.text('Jouer le défi'));
    for (var i = 0; i < 20 && find.text('A').evaluate().isEmpty; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('A'), findsWidgets, reason: 'écran de question');
    expect(home.disposed, isTrue, reason: 'bannière de l\'accueil libérée');
    expect(_banner.hitTestable(), findsNothing);
    expect(loader.loads, 1, reason: 'aucun chargement pendant le quiz');
  });

  testWidgets('résultats : bannière chargée après le quiz', (tester) async {
    final loader = FakeBannerLoader();
    await pumpApp(
      tester,
      {'progress_v1': '{"onboardingDone":true}'},
      height: 844,
      overrides: [
        adsReadyProvider.overrideWithValue(true),
        bannerLoaderProvider.overrideWithValue(loader),
      ],
    );
    await playChallenge(tester);
    await tester.pump(const Duration(seconds: 2));
    expect(find.text('XP gagnés'), findsOneWidget);
    expect(_banner, findsOneWidget);
    expect(loader.loads, 2, reason: 'accueil puis résultats');
    // Zone défilante (boutons) : au moins 24 dp au-dessus de la bannière.
    expect(
      tester.getTopLeft(_slot).dy -
          tester.getBottomLeft(find.byType(ListView).last).dy,
      greaterThanOrEqualTo(24),
    );
  });
}
