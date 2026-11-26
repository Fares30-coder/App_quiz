import 'dart:math';

/// Catégories du MVP : identifiant (dans le JSON) → libellé affiché.
const categories = <String, String>{
  'histoire': 'Histoire',
  'geo': 'Géo',
  'sciences': 'Sciences',
  'arts': 'Arts',
  'sport': 'Sport',
  'actu': 'Actu',
  'divers': 'Divers',
};

class Question {
  const Question({
    required this.id,
    required this.category,
    required this.question,
    required this.answers,
    required this.correctIndex,
    required this.explanation,
    required this.difficulty,
    this.answerOrder,
  });

  final String id;
  final String category;
  final String question;
  final List<String> answers;
  final int correctIndex;
  final String explanation;

  /// 1 = facile, 2 = moyen, 3 = difficile.
  final int difficulty;

  /// Index d'origine (ordre de assets/questions.json) de chaque réponse
  /// affichée ; `null` = ordre d'origine. Envoyé au serveur, qui corrige
  /// dans cet ordre (`submit_quiz`).
  final List<int>? answerOrder;

  /// Index d'origine de la réponse affichée en position [displayed].
  int originalIndex(int displayed) => answerOrder?[displayed] ?? displayed;

  factory Question.fromJson(Map<String, dynamic> json) => Question(
        id: json['id'] as String,
        category: json['category'] as String,
        question: json['question'] as String,
        answers: List<String>.from(json['answers'] as List),
        correctIndex: json['correctIndex'] as int,
        explanation: json['explanation'] as String,
        difficulty: json['difficulty'] as int,
      );

  /// Copie avec les réponses mélangées (la bonne réponse suit).
  Question shuffled(Random random) {
    final order = List<int>.generate(answers.length, (i) => i)..shuffle(random);
    return Question(
      id: id,
      category: category,
      question: question,
      answers: [for (final i in order) answers[i]],
      correctIndex: order.indexOf(correctIndex),
      explanation: explanation,
      difficulty: difficulty,
      answerOrder: [for (final i in order) originalIndex(i)],
    );
  }
}
