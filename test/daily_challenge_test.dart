import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:quizzeo/engagement/daily_challenge.dart';
import 'package:quizzeo/models/question.dart';

void main() {
  final questions = [
    for (final e
        in jsonDecode(File('assets/questions.json').readAsStringSync()) as List)
      Question.fromJson(e as Map<String, dynamic>),
  ];
  final day = DateTime(2026, 11, 25);

  List<String> ids(List<Question> qs) => [for (final q in qs) q.id];

  test('même date : même quiz (questions et ordre des réponses)', () {
    final a = pickDailyChallenge(questions, day);
    final b = pickDailyChallenge(questions, day.add(const Duration(hours: 23)));
    expect(ids(a), ids(b));
    expect([for (final q in a) q.answers], [for (final q in b) q.answers]);
  });

  test('indépendant de l\'ordre de la liste source', () {
    final a = pickDailyChallenge(questions, day);
    final b = pickDailyChallenge(questions.reversed.toList(), day);
    expect(ids(a), ids(b));
  });

  test('10 questions distinctes, bonne réponse conservée', () {
    final a = pickDailyChallenge(questions, day);
    expect(a, hasLength(dailyChallengeLength));
    expect(ids(a).toSet(), hasLength(dailyChallengeLength));
    final byId = {for (final q in questions) q.id: q};
    for (final q in a) {
      final source = byId[q.id]!;
      expect(q.answers[q.correctIndex], source.answers[source.correctIndex]);
    }
  });

  test('change d\'un jour à l\'autre', () {
    final days = [for (var i = 0; i < 7; i++) DateTime(2026, 11, 25 + i)];
    final sets = {
      for (final d in days) ids(pickDailyChallenge(questions, d)).join(',')
    };
    expect(sets.length, greaterThan(1));
  });

  test('SeededRandom est déterministe', () {
    final a = SeededRandom(20261125);
    final b = SeededRandom(20261125);
    expect([for (var i = 0; i < 20; i++) a.nextInt(1000)],
        [for (var i = 0; i < 20; i++) b.nextInt(1000)]);
    final d = SeededRandom(1).nextDouble();
    expect(d, inInclusiveRange(0, 1));
  });
}
