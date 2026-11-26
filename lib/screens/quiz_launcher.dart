import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../data/question_repository.dart';
import '../engagement/dates.dart';
import '../engagement/progress_controller.dart';
import '../models/quiz_session.dart';
import '../quiz/quiz_controller.dart';
import '../widgets/brand.dart';
import 'quiz_screen.dart';

/// Quiz en cours de chargement (appel serveur) : un seul lancement à la
/// fois, un double toucher est ignoré.
final quizLaunchingProvider = StateProvider<bool>((ref) => false);

/// Charge les questions (serveur si possible, sinon locales) puis ouvre
/// l'écran Question.
/// [category] : identifiant de catégorie, [mixCategory] ou null pour le défi du jour.
// TODO(etape-3): interstitiel plafonné ici, AVANT le quiz suivant (jamais pendant).
Future<void> launchQuiz(
  BuildContext context,
  WidgetRef ref, {
  String? category,
  bool replace = false,
}) async {
  final launching = ref.read(quizLaunchingProvider.notifier);
  if (launching.state) return;
  launching.state = true;
  try {
    final mode = category == null
        ? QuizMode.dailyChallenge
        : category == mixCategory
            ? QuizMode.mix
            : QuizMode.category;
    final start = await ref.read(questionRepositoryProvider).startQuiz(
          mode: mode,
          category: mode == QuizMode.category ? category : null,
          today: dayOf(ref.read(clockProvider)()),
        );
    if (!context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    if (start.questions.isEmpty) {
      messenger.showSnackBar(
        const SnackBar(
            content: Text('Pas encore de questions dans cette catégorie.')),
      );
      return;
    }
    final notice = switch (start.unranked) {
      UnrankedReason.offline =>
        'Hors connexion : ce quiz ne comptera pas au classement.',
      UnrankedReason.notEnoughQuestions =>
        'Pas encore assez de questions ici : ce quiz ne comptera pas au classement.',
      null => null,
    };
    if (notice != null) {
      messenger.showSnackBar(SnackBar(content: Text(notice)));
    }
    ref.read(quizControllerProvider.notifier).start(
          start.questions,
          mode: mode,
          category: mode == QuizMode.category ? category : null,
          quizId: start.quizId,
          userId: start.userId,
        );
    final route = MaterialPageRoute<void>(builder: (_) => const QuizScreen());
    if (replace) {
      Navigator.of(context).pushReplacement(route);
    } else {
      Navigator.of(context).push(route);
    }
  } finally {
    launching.state = false;
  }
}
