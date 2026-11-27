import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:quizzeo/models/question.dart';

import '../tool/generate_seed.dart';

List<Question> _load(String path) => [
      for (final e in jsonDecode(File(path).readAsStringSync()) as List)
        Question.fromJson(e as Map<String, dynamic>),
    ];

void _expectValid(List<Question> questions) {
  expect(questions, isNotEmpty);
  expect(questions.map((q) => q.id).toSet().length, questions.length,
      reason: 'id en double');
  for (final q in questions) {
    expect(q.id, matches(RegExp(r'^[a-z0-9-]{1,40}$')), reason: q.id);
    expect(q.answers.length, 4, reason: q.id);
    expect(q.answers.toSet().length, 4, reason: '${q.id} : réponses en double');
    expect(q.correctIndex, inInclusiveRange(0, 3), reason: q.id);
    expect(categories.keys, contains(q.category), reason: q.id);
    expect(q.difficulty, inInclusiveRange(1, 3), reason: q.id);
    expect(q.explanation.trim(), isNotEmpty, reason: q.id);
    // Source facultative : libellé court (ex. « Larousse »), sans URL.
    final source = q.source;
    if (source != null) {
      expect(source.trim(), isNotEmpty, reason: '${q.id} : source vide');
      expect(source.trim(), source, reason: '${q.id} : espaces autour');
      expect(source.length, lessThanOrEqualTo(60),
          reason: '${q.id} : source de plus de 60 caractères');
      expect(source.toLowerCase().contains('http'), isFalse,
          reason: '${q.id} : pas d\'URL dans la source');
    }
  }
}

String _normalize(String text) => text.toLowerCase().trim();

void main() {
  /// Lot hors ligne, embarqué dans l'app.
  final offline = _load(offlineQuestionsPath);

  /// Questions servies par le serveur (hors bundle).
  final server = _load(questionsPath);

  test('le lot hors ligne (assets) est valide', () => _expectValid(offline));

  test('le fichier des questions du serveur est valide', () {
    _expectValid(server);
    for (final c in categories.keys) {
      expect(
          server.where((q) => q.category == c).length, greaterThanOrEqualTo(10),
          reason: '$c : au moins 10 questions pour un quiz par catégorie');
    }
  });

  test('aucun identifiant commun entre le lot hors ligne et le serveur', () {
    final offlineIds = {for (final q in offline) q.id};
    final serverIds = {for (final q in server) q.id};
    expect(offlineIds.intersection(serverIds), isEmpty,
        reason: 'une question du serveur ne doit jamais être dans l\'app '
            '(et inversement : le lot hors ligne est désactivé en base)');
  });

  test('aucune question du serveur dans les assets de l\'app', () {
    final assets = Directory('assets')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.json'))
        .map((f) => f.readAsStringSync().toLowerCase())
        .join('\n');
    for (final q in server) {
      expect(assets.contains('"${q.id}"'), isFalse,
          reason: '${q.id} trouvé dans assets/');
      expect(assets.contains(_normalize(q.question)), isFalse,
          reason: '${q.id} : énoncé trouvé dans assets/');
    }
    final offlineTexts = {for (final q in offline) _normalize(q.question)};
    expect(server.where((q) => offlineTexts.contains(_normalize(q.question))),
        isEmpty,
        reason: 'même énoncé dans le lot hors ligne et sur le serveur');
  });

  test('le fichier du serveur n\'est jamais embarqué (pubspec.yaml)', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    expect(pubspec.contains('supabase/'), isFalse);
    expect(questionsPath.startsWith('assets/'), isFalse);
  });

  test('shuffled garde la bonne réponse', () {
    final r = Random(42);
    for (final q in offline) {
      final s = q.shuffled(r);
      expect(s.answers[s.correctIndex], q.answers[q.correctIndex]);
    }
  });
}
