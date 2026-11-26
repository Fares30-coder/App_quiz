import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/quiz_session.dart';

/// Accès Supabase aux quiz servis : `start_quiz` (questions sans réponse) et
/// `answer_question` (correction après chaque réponse). Lève une erreur en
/// cas de problème réseau ou de refus du serveur.
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

  /// [choice] : position affichée (0 à 3), `null` si le temps est écoulé.
  Future<AnswerCorrection> answer({
    required String quizId,
    required String questionId,
    required int? choice,
    required int timeMs,
  }) async {
    final json = await _client.rpc<Map<String, dynamic>>(
      'answer_question',
      params: {
        'quiz_id': quizId,
        'question_id': questionId,
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
