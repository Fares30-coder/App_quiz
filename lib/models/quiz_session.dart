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
///
/// Défi du jour déjà commencé : même session reprise ([resumed]), avec les
/// réponses déjà enregistrées ([answered], dans l'ordre) ; ces questions
/// arrivent déjà corrigées.
class ServedQuiz {
  const ServedQuiz({
    required this.id,
    required this.questions,
    this.answered = const [],
    this.resumed = false,
  });

  final String id;
  final List<Question> questions;
  final List<ServedAnswer> answered;
  final bool resumed;

  factory ServedQuiz.fromJson(Map<String, dynamic> json) {
    final questions = <Question>[];
    final answered = <ServedAnswer>[];
    for (final raw in json['questions'] as List) {
      final q = raw as Map<String, dynamic>;
      var question = Question.fromServerJson(q);
      final answer = q['answer'];
      // Réponses enregistrées : toujours les premières (ordre imposé).
      if (answer is Map<String, dynamic> &&
          answered.length == questions.length) {
        final a = ServedAnswer.fromJson(answer);
        answered.add(a);
        question = question.withCorrection(a.correctChoice, a.explanation);
      }
      questions.add(question);
    }
    return ServedQuiz(
      id: json['quiz_id'] as String,
      questions: questions,
      answered: answered,
      resumed: json['resumed'] as bool? ?? false,
    );
  }
}

/// Réponse déjà enregistrée par le serveur (reprise du défi du jour).
class ServedAnswer {
  const ServedAnswer({
    required this.choice,
    required this.correct,
    required this.correctChoice,
    required this.explanation,
    required this.timeMs,
  });

  /// Position affichée choisie, `null` si le temps était écoulé.
  final int? choice;
  final bool correct;
  final int correctChoice;
  final String explanation;
  final int timeMs;

  factory ServedAnswer.fromJson(Map<String, dynamic> json) => ServedAnswer(
        choice: (json['choice'] as num?)?.toInt(),
        correct: json['correct'] as bool? ?? false,
        correctChoice: (json['correct_choice'] as num).toInt(),
        explanation: json['explanation'] as String? ?? '',
        timeMs: (json['time_ms'] as num).toInt(),
      );
}

/// Défi du jour déjà joué sur le serveur (`start_quiz` : `23505`), par
/// exemple sur un autre appareil. [score] et [total] : résultat enregistré,
/// `null` s'ils sont illisibles.
class DailyChallengeAlreadyPlayed implements Exception {
  const DailyChallengeAlreadyPlayed({this.score, this.total});

  final int? score;
  final int? total;

  @override
  String toString() => 'DailyChallengeAlreadyPlayed';
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
    this.answered = const [],
  });

  final List<Question> questions;

  /// Défi du jour repris : réponses déjà enregistrées (les premières
  /// questions), à ne pas rejouer.
  final List<ServedAnswer> answered;

  /// Session `start_quiz`, `null` pour un quiz local.
  final String? quizId;

  /// Compte qui a commencé le quiz servi.
  final String? userId;

  /// Renseigné quand le serveur est configuré mais que le quiz est local.
  final UnrankedReason? unranked;

  bool get isServed => quizId != null;
}
