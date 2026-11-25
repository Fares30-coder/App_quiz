import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../data/question_repository.dart';
import '../engagement/dates.dart';
import '../engagement/progress_controller.dart';
import '../quiz/quiz_controller.dart';
import '../widgets/brand.dart';
import 'quiz_screen.dart';

/// Charge les questions puis ouvre l'écran Question.
/// [category] : identifiant de catégorie, [mixCategory] ou null pour le défi du jour.
// TODO(etape-3): interstitiel plafonné ici, AVANT le quiz suivant (jamais pendant).
Future<void> launchQuiz(
  BuildContext context,
  WidgetRef ref, {
  String? category,
  bool replace = false,
}) async {
  final repo = ref.read(questionRepositoryProvider);
  final today = dayOf(ref.read(clockProvider)());
  final mode = category == null
      ? QuizMode.dailyChallenge
      : category == mixCategory
          ? QuizMode.mix
          : QuizMode.category;
  final questions = switch (mode) {
    QuizMode.dailyChallenge => await repo.dailyChallenge(today),
    QuizMode.mix => await repo.pickQuiz(),
    QuizMode.category => await repo.pickQuiz(category: category),
  };
  if (!context.mounted) return;
  if (questions.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
          content: Text('Pas encore de questions dans cette catégorie.')),
    );
    return;
  }
  ref.read(quizControllerProvider.notifier).start(
        questions,
        mode: mode,
        category: mode == QuizMode.category ? category : null,
      );
  final route = MaterialPageRoute<void>(builder: (_) => const QuizScreen());
  if (replace) {
    Navigator.of(context).pushReplacement(route);
  } else {
    Navigator.of(context).push(route);
  }
}
