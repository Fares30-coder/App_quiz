import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:quizzeo/backend/backend_config.dart';
import 'package:quizzeo/backend/supabase_provider.dart';
import 'package:quizzeo/data/progress_repository.dart';
import 'package:quizzeo/data/question_repository.dart';
import 'package:quizzeo/models/question.dart';
import 'package:quizzeo/main.dart';
import 'package:quizzeo/reminder/notification_service.dart';
import 'package:quizzeo/share/share_content.dart';
import 'package:quizzeo/share/share_service.dart';
import 'package:quizzeo/sound/sound_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fake_notifications.dart';
import 'fakes.dart';
import 'fonts.dart';

final questions = [
  for (final e
      in jsonDecode(File('assets/questions.json').readAsStringSync()) as List)
    Question.fromJson(e as Map<String, dynamic>),
];

Future<void> pumpApp(
  WidgetTester tester,
  Map<String, Object> prefs, {
  double height = 1100,
  SoundService sounds = const SilentSoundService(),
  FakeNotificationService? notifications,
  FakeShareService? share,
}) async {
  // Format téléphone des maquettes (390×844), assez haut pour tout l'écran objectif.
  tester.view.physicalSize = Size(390, height);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  SharedPreferences.setMockInitialValues(prefs);
  final instance = await SharedPreferences.getInstance();
  await tester.pumpWidget(ProviderScope(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(instance),
      questionRepositoryProvider
          .overrideWithValue(QuestionRepository(questions: questions)),
      soundServiceProvider.overrideWithValue(sounds),
      notificationServiceProvider
          .overrideWithValue(notifications ?? FakeNotificationService()),
      shareServiceProvider.overrideWithValue(share ?? FakeShareService()),
    ],
    child: const QuizzeoApp(),
  ));
  await tester.pump();
}

void main() {
  setUpAll(loadFonts);

  testWidgets('premier lancement : écran de consentement', (tester) async {
    await pumpApp(tester, {});
    expect(find.text('Avant de jouer'), findsOneWidget);
    expect(find.text('Continuer'), findsOneWidget);
  });

  testWidgets('sans config Supabase : démarrage en mode local', (tester) async {
    const config = BackendConfig.fromEnvironment();
    expect(config.isConfigured, isFalse);
    expect(await initBackend(config), isNull);
    await pumpApp(tester, {});
    final container = ProviderScope.containerOf(
      tester.element(find.byType(QuizzeoApp)),
    );
    expect(container.read(backendAvailableProvider), isFalse);
    expect(find.text('Avant de jouer'), findsOneWidget);
  });

  testWidgets('premier lancement : objectif 2 quiz et 20 h 30 par défaut',
      (tester) async {
    await pumpApp(tester, {});
    await tester.tap(find.text('Continuer'));
    await tester.pumpAndSettle();
    expect(find.text('Ton objectif du jour'), findsOneWidget);
    expect(find.text('20 h 30'), findsOneWidget);
    await tester.tap(find.text('C\'est parti'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Jouer le défi'), findsOneWidget);
  });

  testWidgets('premier lancement : autorisation demandée après le choix',
      (tester) async {
    final notifications = FakeNotificationService(grant: false);
    await pumpApp(tester, {}, notifications: notifications);
    await tester.tap(find.text('Continuer'));
    await tester.pumpAndSettle();
    expect(notifications.permissionRequests, 0);
    await tester.tap(find.text('C\'est parti'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(notifications.permissionRequests, 1);
    expect(notifications.scheduled.first.when.hour, 20);
    // Refus : l'app continue normalement.
    expect(find.text('Jouer le défi'), findsOneWidget);
  });

  testWidgets('« Pas de rappel » : aucune demande d\'autorisation',
      (tester) async {
    final notifications = FakeNotificationService();
    await pumpApp(tester, {}, notifications: notifications);
    await tester.tap(find.text('Continuer'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Pas de rappel'));
    await tester.tap(find.text('C\'est parti'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(notifications.permissionRequests, 0);
    expect(notifications.scheduled, isEmpty);
  });

  testWidgets('accueil après le premier lancement', (tester) async {
    await pumpApp(tester, {'progress_v1': '{"onboardingDone":true}'});
    expect(find.text('Jouer le défi'), findsOneWidget);
    expect(find.text('Objectif du jour'), findsOneWidget);
    expect(find.text('Niveau 1'), findsOneWidget);
  });

  testWidgets('profil : réglage « Sons » activé par défaut et persisté',
      (tester) async {
    await pumpApp(tester, {'progress_v1': '{"onboardingDone":true}'});
    await tester.tap(find.text('Profil'));
    await tester.pump(const Duration(milliseconds: 500));
    final toggle = find.widgetWithText(SwitchListTile, 'Sons');
    await tester.scrollUntilVisible(toggle, 100);
    expect(tester.widget<SwitchListTile>(toggle).value, isTrue);
    await tester.tap(toggle);
    await tester.pump(const Duration(milliseconds: 300));
    expect(tester.widget<SwitchListTile>(toggle).value, isFalse);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('progress_v1'), contains('"soundEnabled":false'));
  });

  testWidgets('partage du score puis de la série', (tester) async {
    final share = FakeShareService();
    await pumpApp(tester, {'progress_v1': '{"onboardingDone":true}'},
        height: 844, share: share);
    await playChallenge(tester);
    await tester.pump(const Duration(seconds: 2));
    await tester.tap(find.text('Partager mon score'));
    await tester.pump();
    expect(share.shared, hasLength(1));
    final score = share.shared.single;
    expect(score.kind, ShareKind.score);
    expect(score.overline, startsWith('DÉFI DU JOUR · '));
    expect(score.answers, hasLength(10));
    expect(score.streakLabel, '1 jour de série');
    // Ancre de la feuille de partage (popover iPad) : la zone du bouton.
    expect(share.origins.single, isNotNull);
    expect(share.origins.single!.isEmpty, isFalse);

    await tester.scrollUntilVisible(find.text('Continuer').hitTestable(), 200);
    await tester.tap(find.text('Continuer'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.tap(find.text('Partager ma série'));
    await tester.pump();
    expect(share.shared.last.kind, ShareKind.streak);
    expect(share.shared.last.streakDays, 1);
  });

  testWidgets('partage en échec : message, puis bouton de nouveau actif',
      (tester) async {
    final share = FakeShareService()..error = Exception('échec');
    await pumpApp(tester, {'progress_v1': '{"onboardingDone":true}'},
        height: 844, share: share);
    await playChallenge(tester);
    await tester.pump(const Duration(seconds: 2));
    await tester.tap(find.text('Partager mon score'));
    await tester.pump();
    expect(
        find.text('Le partage n\'a pas fonctionné. Réessaie.'), findsOneWidget);
    await tester.tap(find.text('Partager mon score'));
    await tester.pump();
    expect(share.shared, hasLength(2));
  });

  journeyTests(1);
  journeyTests(1.3);
}

Future<void> playChallenge(WidgetTester tester) async {
  await tester.ensureVisible(find.text('Jouer le défi'));
  await tester.tap(find.text('Jouer le défi'));
  // Le chargement de assets/questions.json est une vraie I/O asynchrone.
  for (var i = 0; i < 20 && find.text('A').evaluate().isEmpty; i++) {
    await tester
        .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pump(const Duration(milliseconds: 100));
  }
  await tester.pump(const Duration(milliseconds: 400));
  for (var i = 0; i < 10; i++) {
    await tester.tap(find.text('A').first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(
      find.textContaining(RegExp(r'^(Bien vu|Raté)')),
      findsOneWidget,
    );
    final next = i == 9 ? 'Voir le résultat' : 'Question suivante';
    await tester.ensureVisible(find.text(next));
    await tester.tap(find.text(next));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }
}

void journeyTests(double textScale) {
  testWidgets('parcours défi -> résultats -> série (texte x$textScale)',
      (tester) async {
    tester.platformDispatcher.textScaleFactorTestValue = textScale;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final sounds = FakeSoundService();
    await pumpApp(tester, {'progress_v1': '{"onboardingDone":true}'},
        height: 844, sounds: sounds);
    await playChallenge(tester);
    await tester.pump(const Duration(seconds: 2));
    expect(find.text('XP gagnés'), findsOneWidget);
    // hitTestable : le bouton peut être construit dans le cache de la liste,
    // caché sous le bandeau pub ; on défile jusqu'à ce qu'il soit touchable.
    await tester.scrollUntilVisible(find.text('Continuer').hitTestable(), 200);
    await tester.tap(find.text('Continuer'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Série validée !'), findsOneWidget);
    // Un son par réponse, puis la « flamme » de la série.
    expect(
      sounds.played.where((s) => s == Sfx.correct || s == Sfx.wrong),
      hasLength(10),
    );
    expect(sounds.played.last, Sfx.streak);
    await tester.tap(find.text('Continuer'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.scrollUntilVisible(find.textContaining('Ton score'), -200);
    expect(find.textContaining('Ton score'), findsOneWidget);
  });
}
