import 'question.dart';

enum QuizMode { dailyChallenge, category, mix }

/// Valeur du paramètre `mode` de la RPC `start_quiz`.
String quizModeParam(QuizMode mode) => switch (mode) {
      QuizMode.dailyChallenge => 'daily',
      QuizMode.category => 'category',
      QuizMode.mix => 'mix',
    };

/// Quiz servi par le serveur (RPC `start_quiz`) : identifiant de session à
/// reprendre dans `answer_question`, `next_question` et `submit_quiz`.
///
/// Questions servies une à une : [questions] ne contient que la question en
/// cours (sans bonne réponse ni explication), précédée des questions déjà
/// répondues en cas de reprise ; les suivantes viennent de `next_question`.
/// [total] : nombre de questions du quiz.
///
/// Défi du jour déjà commencé : même session reprise ([resumed]), avec les
/// réponses déjà enregistrées ([answered], dans l'ordre) ; ces questions
/// arrivent déjà corrigées.
///
/// [secondsLeft] : chrono restant de la question en cours, calculé par le
/// serveur depuis son heure d'envoi (moins de 30 s à la reprise du défi).
///
/// [day] : jour du défi selon le serveur (`challenge_day`, jour de Paris au
/// début de la session), `null` hors défi du jour.
class ServedQuiz {
  const ServedQuiz({
    required this.id,
    required this.questions,
    int? total,
    this.answered = const [],
    this.resumed = false,
    this.secondsLeft,
    this.day,
  }) : total = total ?? questions.length;

  final String id;
  final List<Question> questions;
  final int total;
  final List<ServedAnswer> answered;
  final bool resumed;
  final int? secondsLeft;
  final DateTime? day;

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
      total: (json['total'] as num?)?.toInt(),
      answered: answered,
      resumed: json['resumed'] as bool? ?? false,
      secondsLeft: (json['seconds_left'] as num?)?.toInt(),
      day: parseServerDay(json['day']),
    );
  }
}

/// Jour calendaire `AAAA-MM-JJ` envoyé par le serveur (colonne `date`), en
/// minuit local, sans conversion de fuseau : « 2026-11-26 » reste le 26
/// partout. `null` si absent ou illisible.
DateTime? parseServerDay(Object? value) {
  if (value is! String) return null;
  final match = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(value);
  if (match == null) return null;
  final y = int.parse(match[1]!);
  final m = int.parse(match[2]!);
  final d = int.parse(match[3]!);
  final day = DateTime(y, m, d);
  // Refuse les dates impossibles (« 2026-02-30 »).
  if (day.year != y || day.month != m || day.day != d) return null;
  return day;
}

/// Question suivante d'un quiz servi (RPC `next_question`), sans bonne
/// réponse ni explication. [position] : 1 à 10. [secondsLeft] : chrono
/// restant calculé par le serveur (moins de 30 s si la question était déjà
/// servie, par exemple après un réessai).
class ServedQuestion {
  const ServedQuestion({
    required this.position,
    required this.question,
    this.secondsLeft,
  });

  final int position;
  final Question question;
  final int? secondsLeft;

  factory ServedQuestion.fromJson(Map<String, dynamic> json) => ServedQuestion(
        position: (json['position'] as num).toInt(),
        question:
            Question.fromServerJson(json['question'] as Map<String, dynamic>),
        secondsLeft: (json['seconds_left'] as num?)?.toInt(),
      );
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
    this.timedOut = false,
  });

  final bool correct;

  /// Position affichée de la bonne réponse (0 à 3).
  final int correctChoice;
  final String explanation;

  /// Temps écoulé selon le serveur (plus de 30 s depuis l'envoi de la
  /// question, tolérance comprise) : réponse comptée fausse.
  final bool timedOut;

  factory AnswerCorrection.fromJson(Map<String, dynamic> json) =>
      AnswerCorrection(
        correct: json['correct'] as bool? ?? false,
        correctChoice: (json['correct_choice'] as num).toInt(),
        explanation: json['explanation'] as String? ?? '',
        timedOut: json['timed_out'] as bool? ?? false,
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
    this.secondsLeft,
    this.day,
    int? total,
  }) : total = total ?? questions.length;

  /// Jour du quiz, figé au début : jour du défi selon le serveur (quiz
  /// servi) ou jour du téléphone au lancement (quiz local, ou serveur muet).
  /// Sert au numéro du défi et à la date de l'image de partage.
  final DateTime? day;

  /// Quiz servi : chrono restant de la question en cours (serveur) ; `null`
  /// = 30 s.
  final int? secondsLeft;

  /// Quiz local : toutes les questions. Quiz servi : questions déjà servies
  /// (réponses de la reprise puis question en cours).
  final List<Question> questions;

  /// Nombre de questions du quiz.
  final int total;

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
