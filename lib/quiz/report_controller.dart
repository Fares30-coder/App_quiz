import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../backend/supabase_quiz_source.dart';
import '../data/question_repository.dart';
import '../models/question_report.dart';
import 'quiz_controller.dart';

export '../models/question_report.dart' show ReportReason;

enum ReportStatus { sending, sent }

/// Résultat d'un signalement, pour le message affiché.
enum ReportResult {
  sent,

  /// Déjà signalée (ou en cours d'envoi) dans ce quiz : rien d'envoyé.
  ignored,

  /// Plus de 20 signalements aujourd'hui (`PT429`).
  tooMany,

  /// Réseau ou refus du serveur.
  failed,
}

/// Signalements du quiz servi en cours, par position (1 à 10).
class QuestionReports {
  const QuestionReports({this.quizId, this.statuses = const {}});

  final String? quizId;
  final Map<int, ReportStatus> statuses;

  ReportStatus? statusOf(String quizId, int position) =>
      quizId == this.quizId ? statuses[position] : null;
}

/// Signalement des questions (RPC `report_question`) : une fois par question
/// et par quiz, seulement pour un quiz servi par le serveur (l'app n'envoie
/// que la session et la position, jamais d'identifiant de question). Ne
/// touche jamais au quiz en cours : l'envoi se fait en arrière-plan.
class ReportController extends Notifier<QuestionReports> {
  @override
  QuestionReports build() => const QuestionReports();

  /// Signale la question [position] (1 à 10) du quiz [quizId].
  Future<ReportResult> report({
    required String quizId,
    required int position,
    required ReportReason reason,
  }) async {
    if (state.statusOf(quizId, position) != null) return ReportResult.ignored;
    _set(quizId, position, ReportStatus.sending, newQuiz: true);
    try {
      await ref
          .read(questionRepositoryProvider)
          .reportQuestion(quizId: quizId, position: position, reason: reason);
      _set(quizId, position, ReportStatus.sent);
      return ReportResult.sent;
    } catch (e) {
      // Échec : la question redevient signalable.
      _set(quizId, position, null);
      return isRateLimited(e) ? ReportResult.tooMany : ReportResult.failed;
    }
  }

  /// [newQuiz] : un autre quiz remplace les signalements gardés ; sinon un
  /// résultat arrivé après le début d'un autre quiz est ignoré.
  void _set(String quizId, int position, ReportStatus? status,
      {bool newQuiz = false}) {
    final same = state.quizId == quizId;
    if (!same && !newQuiz) return;
    final statuses = {if (same) ...state.statuses};
    if (status == null) {
      statuses.remove(position);
    } else {
      statuses[position] = status;
    }
    state = QuestionReports(quizId: quizId, statuses: statuses);
  }
}

final reportControllerProvider =
    NotifierProvider<ReportController, QuestionReports>(ReportController.new);

/// Lien « Signaler » : question en cours d'un quiz servi, déjà corrigée,
/// pas encore signalée. Jamais pour un quiz local (hors ligne).
bool canReport(QuizState quiz, QuestionReports reports) {
  final quizId = quiz.quizId;
  return quizId != null &&
      quiz.answered &&
      !quiz.isFinished &&
      reports.statusOf(quizId, quiz.index + 1) == null;
}
