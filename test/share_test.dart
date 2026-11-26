import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:quizzeo/engagement/dates.dart';
import 'package:quizzeo/quiz/quiz_controller.dart';
import 'package:quizzeo/share/share_content.dart';
import 'package:quizzeo/share/share_image.dart';
import 'package:quizzeo/theme/app_theme.dart';
import 'package:quizzeo/widgets/share_card.dart';

import 'fonts.dart';

final day = DateTime(2026, 11, 25);

List<bool> answersFor(int score) => [for (var i = 0; i < 10; i++) i < score];

ShareContent daily(int score, {int streak = 6}) => scoreShareContent(
      mode: QuizMode.dailyChallenge,
      score: score,
      total: 10,
      answers: answersFor(score),
      streakDays: streak,
      day: day,
    );

/// Largeur et hauteur lues dans l'en-tête IHDR du PNG.
(int, int) pngSize(Uint8List png) {
  final data = ByteData.sublistView(png);
  return (data.getUint32(16), data.getUint32(20));
}

void main() {
  group('contenu', () {
    test('défi du jour 8/10 : textes de la maquette', () {
      final c = daily(8);
      expect(c.kind, ShareKind.score);
      expect(c.overline, 'DÉFI DU JOUR · 25 NOV.');
      expect(c.headline, 'J\'ai eu 8/10\nau défi du jour');
      expect(c.streakLabel, '6 jours de série');
      expect(c.challenge, 'Tu fais mieux ?');
      expect(c.cta, 'Joue le défi sur Quizzéo');
      expect(c.answers.where((a) => a), hasLength(8));
      expect(c.fileName, 'quizzeo-score-8-sur-10.png');
      // 25 nov. 2026 : avant le défi n° 1, donc pas de numéro.
      expect(
          c.message,
          'Quizzéo · 8/10\n'
          '🟩🟩🟩🟩🟩🟩🟩🟩🟥🟥\n'
          '🔥 6\n'
          '\n'
          'Tu fais mieux ?');
    });

    test('accroche selon le score', () {
      expect(daily(10).challenge, 'Qui fait aussi bien ?');
      expect(daily(5).challenge, 'Tu fais mieux ?');
      expect(daily(4).challenge, 'Tu as combien ?');
      expect(daily(0).challenge, 'Tu as combien ?');
    });

    test('catégorie et mélange', () {
      final histoire = scoreShareContent(
        mode: QuizMode.category,
        category: 'histoire',
        score: 7,
        total: 10,
        answers: answersFor(7),
        streakDays: 1,
        day: DateTime(2026, 2, 3),
      );
      expect(histoire.overline, 'HISTOIRE · 3 FÉVR.');
      expect(histoire.headline, 'J\'ai eu 7/10\nen histoire');
      expect(histoire.cta, 'Joue sur Quizzéo');
      expect(histoire.streakLabel, '1 jour de série');

      final mix = scoreShareContent(
        mode: QuizMode.mix,
        score: 6,
        total: 10,
        answers: answersFor(6),
        streakDays: 0,
        day: DateTime(2026, 8, 15),
      );
      expect(mix.overline, 'MÉLANGE · 15 AOÛT');
      expect(mix.headline, 'J\'ai eu 6/10\nen culture G');
      expect(mix.streakLabel, isNull);
    });

    test('série', () {
      final c = streakShareContent(streakDays: 12, day: day);
      expect(c.kind, ShareKind.streak);
      expect(c.overline, 'MA SÉRIE · 25 NOV.');
      expect(c.message, startsWith('12 jours de série sur Quizzéo.'));
      expect(c.fileName, 'quizzeo-serie-12.png');
      expect(streakShareContent(streakDays: 1, day: day).message,
          startsWith('1 jour de série'));
    });

    test('pas de lien de store tant que l\'app n\'est pas publiée', () {
      expect(shareStoreLink, isNull);
      expect(daily(8).message, isNot(contains('http')));
    });
  });

  group('grille de partage', () {
    final start = challengeStartDay;
    final mixed = [
      true,
      false,
      true,
      true,
      false,
      true,
      true,
      true,
      false,
      true,
    ];

    ShareContent score(QuizMode mode,
            {List<bool>? answers, int streak = 6, DateTime? on}) =>
        scoreShareContent(
          mode: mode,
          category: mode == QuizMode.category ? 'histoire' : null,
          score: (answers ?? mixed).where((a) => a).length,
          total: 10,
          answers: answers ?? mixed,
          streakDays: streak,
          day: on ?? addDays(start, 41),
        );

    List<String> lines(ShareContent c) => c.message.split('\n');

    test('10 cases dans l\'ordre des réponses', () {
      final grid = lines(score(QuizMode.dailyChallenge))[1];
      expect(grid, '🟩🟥🟩🟩🟥🟩🟩🟩🟥🟩');
      expect(grid.runes, hasLength(10));
    });

    test('temps écoulé (réponse fausse) = case rouge', () {
      final answers = [for (var i = 0; i < 10; i++) i != 9];
      expect(lines(score(QuizMode.mix, answers: answers))[1],
          '🟩🟩🟩🟩🟩🟩🟩🟩🟩🟥');
    });

    test('numéro seulement pour le défi du jour', () {
      expect(lines(score(QuizMode.dailyChallenge))[0],
          'Quizzéo · Défi n°\u00a042 · 7/10');
      expect(lines(score(QuizMode.mix))[0], 'Quizzéo · 7/10');
      expect(lines(score(QuizMode.category))[0], 'Quizzéo · 7/10');
    });

    test('numéro du défi : n° 1 au départ, null avant', () {
      expect(challengeNumber(start), 1);
      expect(
          challengeNumber(DateTime(start.year, start.month, start.day, 23)), 1);
      expect(challengeNumber(addDays(start, 1)), 2);
      expect(challengeNumber(addDays(start, 41)), 42);
      expect(challengeNumber(addDays(start, -1)), isNull);
      expect(challengeNumber(DateTime(2020)), isNull);
    });

    test('numéro du défi : passage à l\'heure d\'été sans décalage', () {
      // 2026-12-01 → 2027-03-29 : 118 jours, le 28 mars 2027 change d'heure.
      expect(challengeNumber(DateTime(2027, 3, 29)), 119);
      expect(challengeNumber(DateTime(2027, 3, 29, 23, 30)), 119);
    });

    test('pas de ligne vide si aucune réponse', () {
      final g = shareGrid(
        mode: QuizMode.mix,
        score: 0,
        total: 0,
        answers: const [],
        streakDays: 6,
        day: start,
      );
      expect(g, 'Quizzéo · 0/0\n🔥 6');
    });

    test('série affichée si > 0, absente si 0', () {
      expect(lines(score(QuizMode.dailyChallenge, streak: 12))[2], '🔥 12');
      final none = score(QuizMode.dailyChallenge, streak: 0);
      expect(none.message, isNot(contains('🔥')));
      expect(lines(none)[2], '');
    });

    test('aucun texte de question ni de réponse', () {
      final c = score(QuizMode.dailyChallenge);
      expect(
          c.message,
          'Quizzéo · Défi n°\u00a042 · 7/10\n'
          '🟩🟥🟩🟩🟥🟩🟩🟩🟥🟩\n'
          '🔥 6\n'
          '\n'
          'Tu fais mieux ?');
    });
  });

  group('image 1080×1920 avec les vraies polices', () {
    setUpAll(loadFonts);

    final cases = <String, ShareContent>{
      'partage-8-sur-10': daily(8),
      'partage-10-sur-10': daily(10, streak: 365),
      'partage-0-sur-10': daily(0, streak: 1),
      'partage-categorie': scoreShareContent(
        mode: QuizMode.category,
        category: 'sciences',
        score: 7,
        total: 10,
        answers: [
          true,
          false,
          true,
          true,
          false,
          true,
          true,
          true,
          false,
          true
        ],
        streakDays: 12,
        day: DateTime(2026, 12, 31),
      ),
      'partage-serie': streakShareContent(streakDays: 1000, day: day),
    };

    for (final MapEntry(key: name, value: content) in cases.entries) {
      testWidgets('$name : sans débordement', (tester) async {
        // Affichage à 1080×1920 physiques (360×640 logiques × 3).
        tester.view.physicalSize = const Size(1080, 1920);
        tester.view.devicePixelRatio = ShareCard.pixelRatio;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(MediaQuery(
          data: const MediaQueryData(
            size: ShareCard.size,
            devicePixelRatio: ShareCard.pixelRatio,
          ),
          child: Directionality(
            textDirection: TextDirection.ltr,
            child: Theme(
              data: AppTheme.light,
              child: ShareCard(content: content),
            ),
          ),
        ));
        expect(tester.takeException(), isNull);
        expect(tester.getSize(find.byType(ShareCard)), ShareCard.size);

        // Rendu hors écran réel (celui du partage) + aperçu dans build/.
        final png = await tester.runAsync(() => renderShareImage(content));
        expect(tester.takeException(), isNull);
        expect(pngSize(png!), (1080, 1920));
        final out = File('build/share_preview/$name.png');
        await tester.runAsync(() async {
          await out.parent.create(recursive: true);
          await out.writeAsBytes(png);
        });
      });
    }
  });
}
