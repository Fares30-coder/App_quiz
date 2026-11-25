import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:quizzeo/models/question.dart';

void main() {
  final questions = [
    for (final e
        in jsonDecode(File('assets/questions.json').readAsStringSync()) as List)
      Question.fromJson(e as Map<String, dynamic>),
  ];

  test('le fichier de questions est valide', () {
    expect(questions, isNotEmpty);
    expect(questions.map((q) => q.id).toSet().length, questions.length,
        reason: 'id en double');
    for (final q in questions) {
      expect(q.answers.length, 4, reason: q.id);
      expect(q.answers.toSet().length, 4,
          reason: '${q.id} : réponses en double');
      expect(q.correctIndex, inInclusiveRange(0, 3), reason: q.id);
      expect(categories.keys, contains(q.category), reason: q.id);
      expect(q.difficulty, inInclusiveRange(1, 3), reason: q.id);
      expect(q.explanation.trim(), isNotEmpty, reason: q.id);
    }
  });

  test('shuffled garde la bonne réponse', () {
    final r = Random(42);
    for (final q in questions) {
      final s = q.shuffled(r);
      expect(s.answers[s.correctIndex], q.answers[q.correctIndex]);
    }
  });
}
