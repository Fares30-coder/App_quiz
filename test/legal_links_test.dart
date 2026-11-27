import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:quizzeo/data/progress_repository.dart';
import 'package:quizzeo/legal/legal_links.dart';
import 'package:quizzeo/screens/consent_screen.dart';
import 'package:quizzeo/screens/profile_screen.dart';
import 'package:quizzeo/theme/app_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late List<Uri> opened;
  late bool succeed;

  setUp(() {
    opened = [];
    succeed = true;
  });

  Future<void> pump(WidgetTester tester, Widget body) async {
    tester.view.physicalSize = const Size(390, 1100);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        urlOpenerProvider.overrideWithValue((url) async {
          opened.add(url);
          return succeed;
        }),
      ],
      child: MaterialApp(theme: AppTheme.light, home: Scaffold(body: body)),
    ));
    await tester.pump();
  }

  test('URLs des pages légales', () {
    expect(LegalLinks.privacy.toString(),
        'https://legal.quizzeo.workers.dev/confidentialite/');
    expect(LegalLinks.dataDeletion.toString(),
        'https://legal.quizzeo.workers.dev/suppression/');
    expect(LegalLinks.legalNotice.toString(),
        'https://legal.quizzeo.workers.dev/mentions-legales/');
  });

  group('Consentement', () {
    testWidgets('« Politique de confidentialité » ouvre la politique',
        (tester) async {
      await pump(tester, const ConsentScreen());
      await tester.tap(find.text('Politique de confidentialité'));
      await tester.pump();
      expect(opened, [LegalLinks.privacy]);
      expect(find.textContaining('bientôt en ligne'), findsNothing);
      expect(find.byType(SnackBar), findsNothing);
    });

    testWidgets('échec d\'ouverture : message, pas de crash', (tester) async {
      succeed = false;
      await pump(tester, const ConsentScreen());
      await tester.tap(find.text('Politique de confidentialité'));
      await tester.pump();
      expect(
          find.textContaining('Impossible d\'ouvrir la page'), findsOneWidget);
    });

    testWidgets('exception du lanceur : message, pas de crash', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      await tester.pumpWidget(ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          urlOpenerProvider
              .overrideWithValue((url) async => throw Exception('aucun')),
        ],
        child: MaterialApp(
            theme: AppTheme.light, home: const Scaffold(body: ConsentScreen())),
      ));
      await tester.tap(find.text('Politique de confidentialité'));
      await tester.pump();
      expect(
          find.textContaining('Impossible d\'ouvrir la page'), findsOneWidget);
    });
  });

  group('Profil', () {
    for (final (label, url) in [
      ('Politique de confidentialité', LegalLinks.privacy),
      ('Supprimer mes données', LegalLinks.dataDeletion),
      ('Mentions légales', LegalLinks.legalNotice),
    ]) {
      testWidgets('« $label » ouvre $url', (tester) async {
        await pump(tester, const ProfileScreen());
        final tile = find.text(label);
        await tester.scrollUntilVisible(tile, 100);
        await tester.tap(tile);
        await tester.pump();
        expect(opened, [url]);
      });
    }

    testWidgets('« Supprimer mon compte » toujours présent', (tester) async {
      await pump(tester, const ProfileScreen());
      final tile = find.text('Supprimer mon compte');
      await tester.scrollUntilVisible(tile, 100);
      expect(tile, findsOneWidget);
    });
  });
}
