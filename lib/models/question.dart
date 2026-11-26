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
  });

  /// [correctIndex] d'une question servie par le serveur tant que le joueur
  /// n'a pas répondu (la correction arrive avec `answer_question`).
  static const unknownAnswer = -1;

  final String id;
  final String category;
  final String question;

  /// Réponses dans l'ordre affiché.
  final List<String> answers;

  /// Index de la bonne réponse dans [answers], ou [unknownAnswer].
  final int correctIndex;

  /// Vide tant que la correction n'est pas connue.
  final String explanation;

  /// 1 = facile, 2 = moyen, 3 = difficile.
  final int difficulty;

  /// Bonne réponse connue (question locale, ou corrigée par le serveur).
  bool get isRevealed => correctIndex >= 0;

  /// Question locale (assets/questions.json).
  factory Question.fromJson(Map<String, dynamic> json) => Question(
        id: json['id'] as String,
        category: json['category'] as String,
        question: json['question'] as String,
        answers: List<String>.from(json['answers'] as List),
        correctIndex: json['correctIndex'] as int,
        explanation: json['explanation'] as String,
        difficulty: json['difficulty'] as int,
      );

  /// Question servie par `start_quiz` : sans bonne réponse ni explication,
  /// réponses déjà mélangées par le serveur (à ne pas remélanger : le choix
  /// envoyé est la position affichée).
  factory Question.fromServerJson(Map<String, dynamic> json) => Question(
        id: json['id'] as String,
        category: json['category'] as String,
        question: json['question'] as String,
        answers: List<String>.from(json['answers'] as List),
        correctIndex: unknownAnswer,
        explanation: '',
        difficulty: (json['difficulty'] as num).toInt(),
      );

  /// Copie avec la correction reçue du serveur.
  Question withCorrection(int correctIndex, String explanation) => Question(
        id: id,
        category: category,
        question: question,
        answers: answers,
        correctIndex: correctIndex,
        explanation: explanation,
        difficulty: difficulty,
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
    );
  }
}
