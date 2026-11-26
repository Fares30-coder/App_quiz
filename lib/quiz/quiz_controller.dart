import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/question_repository.dart';
import '../engagement/progress_controller.dart';
import '../engagement/progress_sync.dart';
import '../engagement/xp.dart';
import '../models/question.dart';
import '../models/quiz_session.dart';
import '../models/quiz_submission.dart';
import '../sound/sound_service.dart';

export '../models/quiz_session.dart' show QuizMode;

const questionSeconds = 30;

class QuizState {
  const QuizState({
    this.mode = QuizMode.mix,
    this.category,
    this.quizId,
    this.userId,
    this.questions = const [],
    this.index = 0,
    this.selected,
    this.timedOut = false,
    this.answerFailed = false,
    this.secondsLeft = questionSeconds,
    this.answers = const [],
    this.outcome,
  });

  final QuizMode mode;

  /// Catégorie jouée (mode [QuizMode.category]).
  final String? category;

  /// Session `start_quiz` (quiz servi, compte au classement) ; `null` pour
  /// un quiz local.
  final String? quizId;

  /// Compte qui a commencé le quiz servi.
  final String? userId;

  /// Questions dans l'ordre joué ; une question servie reçoit sa bonne
  /// réponse et son explication une fois répondue.
  final List<Question> questions;
  final int index;

  /// Réponse choisie pour la question en cours (null = pas encore répondu).
  final int? selected;
  final bool timedOut;

  /// Correction impossible à obtenir du serveur (réseau) : la réponse est
  /// gardée, à renvoyer avec [QuizController.retryAnswer].
  final bool answerFailed;
  final int secondsLeft;

  /// Réponses déjà corrigées, dans l'ordre.
  final List<AnswerResult> answers;

  /// Renseigné quand le quiz est terminé.
  final QuizOutcome? outcome;

  Question get current => questions[index];
  bool get isServed => quizId != null;

  /// Réponse donnée (ou temps écoulé) pour la question en cours.
  bool get locked => selected != null || timedOut;

  /// Correction connue pour la question en cours.
  bool get answered => answers.length > index;

  /// Réponse donnée, correction en attente du serveur.
  bool get waiting => locked && !answered;
  bool get isLast => index == questions.length - 1;
  bool get isFinished => outcome != null;
  int get score => answers.where((a) => a.correct).length;

  /// Bonnes réponses d'affilée (après la dernière réponse donnée).
  int get combo {
    var c = 0;
    for (final a in answers) {
      c = nextCombo(c, a.correct);
    }
    return c;
  }

  /// XP de la réponse en cours (feuille de feedback).
  AnswerXp get lastAnswerXp {
    if (!answered || answers.isEmpty) return const AnswerXp();
    final last = answers.last;
    return answerXp(correct: last.correct, elapsed: last.elapsed, combo: combo);
  }

  /// Secondes restantes de bonus rapidité (0 si plus de bonus).
  int get speedBonusSecondsLeft {
    final left = secondsLeft - (questionSeconds - speedBonusLimit.inSeconds);
    return locked || left <= 0 ? 0 : left;
  }

  QuizState copyWith({
    List<Question>? questions,
    int? index,
    int? Function()? selected,
    bool? timedOut,
    bool? answerFailed,
    int? secondsLeft,
    List<AnswerResult>? answers,
    QuizOutcome? outcome,
  }) =>
      QuizState(
        mode: mode,
        category: category,
        quizId: quizId,
        userId: userId,
        questions: questions ?? this.questions,
        index: index ?? this.index,
        selected: selected == null ? this.selected : selected(),
        timedOut: timedOut ?? this.timedOut,
        answerFailed: answerFailed ?? this.answerFailed,
        secondsLeft: secondsLeft ?? this.secondsLeft,
        answers: answers ?? this.answers,
        outcome: outcome ?? this.outcome,
      );
}

class QuizController extends Notifier<QuizState> {
  Timer? _timer;
  final _stopwatch = Stopwatch();

  /// Temps de la réponse en attente de correction (réessai).
  Duration _pendingElapsed = Duration.zero;

  SoundEffects get _sounds => ref.read(soundEffectsProvider);

  @override
  QuizState build() {
    ref.onDispose(() => _timer?.cancel());
    return const QuizState();
  }

  /// Démarre un quiz : servi ([quizId] de `start_quiz`, corrigé par le
  /// serveur) ou local (corrigé avec les réponses de l'app).
  ///
  /// [answered] : défi du jour repris, réponses déjà enregistrées par le
  /// serveur (premières questions, déjà corrigées dans [questions]). Elles
  /// comptent telles quelles ; le quiz reprend à la première question sans
  /// réponse (ou reste sur la dernière, corrigée, si tout est répondu).
  void start(
    List<Question> questions, {
    required QuizMode mode,
    String? category,
    String? quizId,
    String? userId,
    List<ServedAnswer> answered = const [],
  }) {
    final done = answered.length.clamp(0, questions.length);
    final results = [
      for (final a in answered.take(done))
        AnswerResult(
          correct: a.correct,
          elapsed: Duration(milliseconds: a.timeMs),
        ),
    ];
    final allAnswered = done > 0 && done == questions.length;
    state = QuizState(
      questions: questions,
      mode: mode,
      category: category,
      quizId: quizId,
      userId: userId,
      answers: results,
      index: allAnswered ? done - 1 : done,
      selected: allAnswered ? answered[done - 1].choice : null,
      timedOut: allAnswered && answered[done - 1].choice == null,
      secondsLeft: allAnswered ? 0 : questionSeconds,
    );
    if (!allAnswered) _startQuestion();
  }

  /// Enregistre la réponse [choice] (position affichée). Renvoie true si
  /// elle est juste. Quiz local : corrigé tout de suite ; quiz servi :
  /// corrigé par le serveur (false si la correction n'a pas pu être obtenue,
  /// voir [QuizState.answerFailed]).
  Future<bool> answer(int choice) {
    if (state.questions.isEmpty || state.locked || state.isFinished) {
      return Future.value(false);
    }
    _stop();
    state = state.copyWith(selected: () => choice);
    return _correct(choice, _stopwatch.elapsed);
  }

  void _timeOut() {
    if (state.locked) return;
    _stop();
    state = state.copyWith(timedOut: true, secondsLeft: 0);
    unawaited(_correct(null, const Duration(seconds: questionSeconds)));
  }

  /// Renvoie au serveur la réponse dont la correction a échoué.
  Future<bool> retryAnswer() {
    if (!state.waiting || !state.answerFailed) return Future.value(false);
    return _correct(state.timedOut ? null : state.selected, _pendingElapsed);
  }

  /// [choice] null = temps écoulé.
  Future<bool> _correct(int? choice, Duration elapsed) {
    final quizId = state.quizId;
    if (quizId == null) {
      return Future.value(_reveal(choice, elapsed, state.current));
    }
    _pendingElapsed = elapsed;
    return _correctOnServer(quizId, choice, elapsed);
  }

  Future<bool> _correctOnServer(
      String quizId, int? choice, Duration elapsed) async {
    final index = state.index;
    bool stillCurrent() =>
        state.quizId == quizId && state.index == index && state.waiting;
    state = state.copyWith(answerFailed: false);
    try {
      final correction = await ref.read(questionRepositoryProvider).answer(
            quizId: quizId,
            questionId: state.current.id,
            choice: choice,
            timeMs: submittedMs(elapsed),
          );
      if (!stillCurrent()) return false;
      return _reveal(
        choice,
        elapsed,
        state.current
            .withCorrection(correction.correctChoice, correction.explanation),
      );
    } catch (_) {
      if (stillCurrent()) state = state.copyWith(answerFailed: true);
      return false;
    }
  }

  /// Applique la correction de la question en cours ([question] révélée).
  bool _reveal(int? choice, Duration elapsed, Question question) {
    final correct = choice != null && choice == question.correctIndex;
    state = state.copyWith(
      questions: [...state.questions]..[state.index] = question,
      answerFailed: false,
      answers: [
        ...state.answers,
        AnswerResult(correct: correct, elapsed: elapsed),
      ],
    );
    _sounds.play(correct ? Sfx.correct : Sfx.wrong);
    return correct;
  }

  /// Passe à la question suivante. Sur la dernière, termine le quiz
  /// (XP, série, objectif) et renvoie false.
  bool next() {
    if (!state.answered || state.isFinished) return false;
    if (state.isLast) {
      _finish();
      return false;
    }
    state = state.copyWith(
      index: state.index + 1,
      selected: () => null,
      timedOut: false,
      secondsLeft: questionSeconds,
    );
    _startQuestion();
    return true;
  }

  /// Abandon : rien n'est compté (ni XP, ni série).
  void quit() {
    _stop();
    state = const QuizState();
  }

  void _finish() {
    _stop();
    final outcome = ref.read(progressControllerProvider.notifier).completeQuiz(
          quizXp(state.answers),
          isDailyChallenge: state.mode == QuizMode.dailyChallenge,
          score: state.score,
          total: state.questions.length,
        );
    state = state.copyWith(outcome: outcome);
    _submit();
    // Fanfare à 10/10 ou en cas de montée de niveau (même moment que
    // l'haptique de l'écran Résultats, qui s'ouvre aussitôt).
    if (outcome.xp.perfect || outcome.leveledUp) _sounds.play(Sfx.fanfare);
  }

  /// Validation serveur en arrière-plan (quiz servi seulement, jamais
  /// bloquant) : le calcul local ci-dessus reste celui affiché. Un quiz
  /// local (hors ligne, pas assez de questions) ne compte pas au classement.
  void _submit() {
    final sync = ref.read(progressSyncProvider);
    final quizId = state.quizId;
    final userId = state.userId;
    if (sync == null || quizId == null || userId == null) return;
    unawaited(sync.submitQuiz(QuizSubmission(
      id: quizId,
      userId: userId,
      playedAt: ref.read(clockProvider)(),
    )));
  }

  void _startQuestion() {
    _stop();
    _stopwatch
      ..reset()
      ..start();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      final left = state.secondsLeft - 1;
      if (left <= 0) {
        _timeOut();
      } else {
        state = state.copyWith(secondsLeft: left);
      }
    });
  }

  void _stop() {
    _timer?.cancel();
    _timer = null;
    _stopwatch.stop();
  }
}

final quizControllerProvider =
    NotifierProvider<QuizController, QuizState>(QuizController.new);
