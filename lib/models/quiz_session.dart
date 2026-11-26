import 'question.dart';

enum QuizMode { dailyChallenge, category, mix }

/// Valeur du paramètre `mode` de la RPC `start_quiz`.
String quizModeParam(QuizMode mode) => switch (mode) {
      QuizMode.dailyChallenge => 'daily',
      QuizMode.category => 'category',
      QuizMode.mix => 'mix',
    };

/// Quiz servi par le serveur (RPC `start_quiz`) : questions sans bonne
/// réponse ni explication, identifiant de session à reprendre dans
/// `answer_question` et `submit_quiz`.
class ServedQuiz {
  const ServedQuiz({required this.id, required this.questions});

  final String id;
  final List<Question> questions;

  factory ServedQuiz.fromJson(Map<String, dynamic> json) => ServedQuiz(
        id: json['quiz_id'] as String,
        questions: [
          for (final q in json['questions'] as List)
            Question.fromServerJson(q as Map<String, dynamic>),
        ],
      );
}

/// Correction d'une réponse (RPC `answer_question`).
class AnswerCorrection {
  const AnswerCorrection({
    required this.correct,
    required this.correctChoice,
    required this.explanation,
  });

  final bool correct;

  /// Position affichée de la bonne réponse (0 à 3).
  final int correctChoice;
  final String explanation;

  factory AnswerCorrection.fromJson(Map<String, dynamic> json) =>
      AnswerCorrection(
        correct: json['correct'] as bool? ?? false,
        correctChoice: (json['correct_choice'] as num).toInt(),
        explanation: json['explanation'] as String? ?? '',
      );
}

/// Pourquoi un quiz est joué en local alors que le serveur est configuré.
enum UnrankedReason {
  /// Pas de session, hors ligne ou serveur indisponible.
  offline,

  /// Pas assez de questions sur le serveur pour ce mode (moins de 10).
  notEnoughQuestions,
}

/// Quiz prêt à jouer : servi par le serveur ([quizId] renseigné, compte au
/// classement) ou tiré en local (ne compte pas au classement).
class QuizStart {
  const QuizStart({
    required this.questions,
    this.quizId,
    this.userId,
    this.unranked,
  });

  final List<Question> questions;

  /// Session `start_quiz`, `null` pour un quiz local.
  final String? quizId;

  /// Compte qui a commencé le quiz servi.
  final String? userId;

  /// Renseigné quand le serveur est configuré mais que le quiz est local.
  final UnrankedReason? unranked;

  bool get isServed => quizId != null;
}
