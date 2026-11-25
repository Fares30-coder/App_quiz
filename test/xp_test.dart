import 'package:flutter_test/flutter_test.dart';
import 'package:quizzeo/engagement/xp.dart';

AnswerResult ok([int seconds = 15]) =>
    AnswerResult(correct: true, elapsed: Duration(seconds: seconds));
AnswerResult ko() =>
    const AnswerResult(correct: false, elapsed: Duration(seconds: 15));

void main() {
  group('answerXp', () {
    test('mauvaise réponse : 0 XP', () {
      expect(
        answerXp(correct: false, elapsed: Duration.zero, combo: 0).total,
        0,
      );
    });

    test('bonne réponse lente : +10', () {
      final xp = answerXp(
          correct: true, elapsed: const Duration(seconds: 12), combo: 1);
      expect((xp.base, xp.speed, xp.combo, xp.total), (10, 0, 0, 10));
    });

    test('bonus rapidité seulement en moins de 10 s', () {
      expect(
        answerXp(
                correct: true,
                elapsed: const Duration(milliseconds: 9999),
                combo: 1)
            .speed,
        5,
      );
      expect(
        answerXp(correct: true, elapsed: const Duration(seconds: 10), combo: 1)
            .speed,
        0,
      );
    });

    test('bonus combo à partir de x3', () {
      expect(
          answerXp(
                  correct: true, elapsed: const Duration(seconds: 20), combo: 2)
              .combo,
          0);
      expect(
          answerXp(
                  correct: true, elapsed: const Duration(seconds: 20), combo: 3)
              .combo,
          5);
      expect(
          answerXp(correct: true, elapsed: const Duration(seconds: 5), combo: 7)
              .total,
          20);
    });

    test('nextCombo', () {
      expect(nextCombo(2, true), 3);
      expect(nextCombo(5, false), 0);
    });
  });

  group('quizXp', () {
    test('7/10 de la maquette : +115 XP', () {
      final xp = quizXp([
        ok(5),
        ok(5),
        ok(5),
        ko(),
        ok(5),
        ok(),
        ko(),
        ok(),
        ko(),
        ok(),
      ]);
      expect(xp.correctXp, 70);
      expect(xp.speedXp, 20);
      expect(xp.comboXp, 5);
      expect(xp.completedXp, 20);
      expect(xp.perfect, isFalse);
      expect(xp.perfectXp, 0);
      expect(xp.maxCombo, 3);
      expect(xp.total, 115);
    });

    test('10/10 de la maquette : +220 XP', () {
      final xp = quizXp([
        ok(3),
        ok(3),
        ok(3),
        ok(3),
        ok(3),
        ok(3),
        ok(),
        ok(),
        ok(),
        ok(),
      ]);
      expect(xp.correctXp, 100);
      expect(xp.speedXp, 30);
      expect(xp.comboCount, 8);
      expect(xp.comboXp, 40);
      expect(xp.perfect, isTrue);
      expect(xp.perfectXp, 30);
      expect(xp.maxCombo, 10);
      expect(xp.total, 220);
    });

    test('0/10 : seulement le bonus quiz terminé', () {
      final xp = quizXp(List.generate(10, (_) => ko()));
      expect(xp.total, 20);
      expect(xp.perfect, isFalse);
    });

    test('combo remis à 0 après une erreur', () {
      final xp = quizXp([ok(), ok(), ko(), ok(), ok(), ok()]);
      expect(xp.comboCount, 1);
      expect(xp.maxCombo, 3);
    });
  });

  group('niveaux', () {
    test('coût par niveau : 100 + 50 × (n − 1)', () {
      expect(xpToNextLevel(1), 100);
      expect(xpToNextLevel(2), 150);
      expect(xpToNextLevel(7), 400);
      expect(xpToNextLevel(8), 450);
    });

    test('levelFor', () {
      expect(levelFor(0).level, 1);
      expect(levelFor(99).level, 1);
      expect(levelFor(100).level, 2);
      expect(levelFor(100).xpInLevel, 0);
      expect(levelFor(249).level, 2);
      expect(levelFor(250).level, 3);
      expect(levelFor(-5).level, 1);
    });

    test('scénario maquette : niveau 7, 240/400 puis 355/400', () {
      const toLevel7 = 100 + 150 + 200 + 250 + 300 + 350; // 1350
      final before = levelFor(toLevel7 + 240);
      expect((before.level, before.xpInLevel, before.xpForNext), (7, 240, 400));
      expect(before.xpRemaining, 160);
      final after = levelFor(toLevel7 + 240 + 115);
      expect((after.level, after.xpInLevel), (7, 355));
    });

    test('scénario maquette 10/10 : passage au niveau 8, 60/450', () {
      final p = levelFor(1350 + 240 + 220);
      expect((p.level, p.xpInLevel, p.xpForNext), (8, 60, 450));
    });
  });
}
