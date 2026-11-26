import 'dart:convert';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/quiz_session.dart';

/// Accès Supabase aux quiz servis : `start_quiz` (première question, sans
/// réponse), `next_question` (questions suivantes, une à une) et
/// `answer_question` (correction après chaque réponse, temps mesuré par le
/// serveur). Lève une erreur en cas de problème réseau ou de refus du
/// serveur.
class SupabaseQuizSource {
  SupabaseQuizSource(this._client);

  final SupabaseClient _client;

  Future<ServedQuiz> start(QuizMode mode, {String? category}) async {
    final json = await _client.rpc<Map<String, dynamic>>(
      'start_quiz',
      params: {
        'mode': quizModeParam(mode),
        if (mode == QuizMode.category) 'category': category,
      },
    );
    return ServedQuiz.fromJson(json);
  }

  /// Question suivante (après la réponse à la question en cours). Rappeler
  /// renvoie la même question sans relancer son chrono serveur.
  Future<ServedQuestion> next(String quizId) async {
    final json = await _client.rpc<Map<String, dynamic>>(
      'next_question',
      params: {'quiz_id': quizId},
    );
    return ServedQuestion.fromJson(json);
  }

  /// [position] : numéro de la question dans le quiz (1 à 10 ; le serveur
  /// n'envoie pas les identifiants). [choice] : position affichée (0 à 3),
  /// `null` si le temps est écoulé.
  Future<AnswerCorrection> answer({
    required String quizId,
    required int position,
    required int? choice,
    required int timeMs,
  }) async {
    final json = await _client.rpc<Map<String, dynamic>>(
      'answer_question',
      params: {
        'quiz_id': quizId,
        'position': position,
        'choice': choice,
        'time_ms': timeMs,
      },
    );
    return AnswerCorrection.fromJson(json);
  }
}

/// Le serveur n'a pas assez de questions pour ce mode (`P0002`).
bool isNotEnoughQuestions(Object error) =>
    error is PostgrestException && error.code == 'P0002';

/// Défi du jour déjà soumis (`23505`, détail `{"score": n, "total": n}`).
/// Renvoie null pour toute autre erreur.
DailyChallengeAlreadyPlayed? challengeAlreadyPlayed(Object error) {
  if (error is! PostgrestException || error.code != '23505') return null;
  int? score;
  int? total;
  try {
    final details = error.details;
    final json = details is String ? jsonDecode(details) : details;
    if (json is Map) {
      score = (json['score'] as num?)?.toInt();
      total = (json['total'] as num?)?.toInt();
    }
  } on FormatException {
    // Détail illisible : défi déjà joué, score inconnu.
  }
  return DailyChallengeAlreadyPlayed(score: score, total: total);
}
