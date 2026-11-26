import 'dart:convert';
import 'dart:math';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../engagement/daily_challenge.dart';
import '../models/question.dart';

const quizLength = 10;

/// Questions locales (assets/questions.json). Sera remplacé par le back-end à l'étape 2.
class QuestionRepository {
  /// [questions] : liste déjà chargée (tests).
  QuestionRepository({AssetBundle? bundle, List<Question>? questions})
      : _bundle = bundle ?? rootBundle,
        _cache = questions;

  final AssetBundle _bundle;
  List<Question>? _cache;

  Future<List<Question>> all() async {
    if (_cache != null) return _cache!;
    final raw = await _bundle.loadString('assets/questions.json');
    final list = jsonDecode(raw) as List;
    return _cache = [
      for (final e in list) Question.fromJson(e as Map<String, dynamic>),
    ];
  }

  /// Tire jusqu'à [count] questions au hasard, filtrées par [category] si fournie.
  Future<List<Question>> pickQuiz({
    String? category,
    int count = quizLength,
    Random? random,
  }) async {
    final r = random ?? Random();
    final pool = (await all())
        .where((q) => category == null || q.category == category)
        .toList()
      ..shuffle(r);
    return [for (final q in pool.take(count)) q.shuffled(r)];
  }

  /// Défi du jour : mêmes questions pour tous à une date donnée.
  Future<List<Question>> dailyChallenge(DateTime day) async =>
      pickDailyChallenge(await all(), day);
}

final questionRepositoryProvider = Provider((ref) => QuestionRepository());
