import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/question_repository.dart';
import '../engagement/progress_controller.dart';
import '../engagement/progress_sync.dart';
import '../engagement/xp.dart';
import '../models/question.dart';
import '../models/quiz_submission.dart';
import '../sound/sound_service.dart';

const questionSeconds = 30;

enum QuizMode { dailyChallenge, category, mix }

class QuizState {
  const QuizState({
    this.mode = QuizMode.mix,
    this.category,
    this.questions = const [],
    this.index = 0,
    this.selected,
    this.timedOut = false,
    this.secondsLeft = questionSeconds,
    this.answers = const [],
    this.choices = const [],
    this.outcome,
  });

  final QuizMode mode;

  /// Catégorie jouée (mode [QuizMode.category]).
  final String? category;
  final List<Question> questions;
  final int index;

  /// Réponse choisie pour la question en cours (null = pas encore répondu).
  final int? selected;
  final bool timedOut;
  final int secondsLeft;

  /// Réponses déjà données, dans l'ordre.
  final List<AnswerResult> answers;

  /// Réponses choisies, index dans l'ordre d'origine (`null` = temps écoulé),
  /// pour la validation serveur.
  final List<int?> choices;

  /// Renseigné quand le quiz est terminé.
  final QuizOutcome? outcome;

  Question get current => questions[index];
  bool get answered => selected != null || timedOut;
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
    return answered || left <= 0 ? 0 : left;
  }

  QuizState copyWith({
    int? index,
    int? Function()? selected,
    bool? timedOut,
    int? secondsLeft,
    List<AnswerResult>? answers,
    List<int?>? choices,
    QuizOutcome? outcome,
  }) =>
      QuizState(
        mode: mode,
        category: category,
        questions: questions,
        index: index ?? this.index,
        selected: selected == null ? this.selected : selected(),
        timedOut: timedOut ?? this.timedOut,
        secondsLeft: secondsLeft ?? this.secondsLeft,
        answers: answers ?? this.answers,
        choices: choices ?? this.choices,
        outcome: outcome ?? this.outcome,
      );
}

class QuizController extends Notifier<QuizState> {
  Timer? _timer;
  final _stopwatch = Stopwatch();

  SoundEffects get _sounds => ref.read(soundEffectsProvider);

  @override
  QuizState build() {
    ref.onDispose(() => _timer?.cancel());
    return const QuizState();
  }

  void start(List<Question> questions,
      {required QuizMode mode, String? category}) {
    state = QuizState(questions: questions, mode: mode, category: category);
    _startQuestion();
  }

  /// Enregistre la réponse [choice]. Renvoie true si elle est juste.
  bool answer(int choice) {
    if (state.answered || state.isFinished) return false;
    _stop();
    final correct = choice == state.current.correctIndex;
    state = state.copyWith(
      selected: () => choice,
      answers: [
        ...state.answers,
        AnswerResult(correct: correct, elapsed: _stopwatch.elapsed),
      ],
      choices: [...state.choices, state.current.originalIndex(choice)],
    );
    _sounds.play(correct ? Sfx.correct : Sfx.wrong);
    return correct;
  }

  void _timeOut() {
    if (state.answered) return;
    _stop();
    state = state.copyWith(
      timedOut: true,
      secondsLeft: 0,
      answers: [
        ...state.answers,
        const AnswerResult(
          correct: false,
          elapsed: Duration(seconds: questionSeconds),
        ),
      ],
      choices: [...state.choices, null],
    );
    _sounds.play(Sfx.wrong);
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

  /// Validation serveur en arrière-plan (mode Supabase seulement, jamais
  /// bloquant) : le calcul local ci-dessus reste celui affiché. Seuls les
  /// quiz complets de [quizLength] questions sont acceptés par le serveur.
  void _submit() {
    final sync = ref.read(progressSyncProvider);
    if (sync == null || state.questions.length != quizLength) return;
    unawaited(sync.submitQuiz(QuizSubmission(
      id: randomUuid(),
      questionIds: [for (final q in state.questions) q.id],
      choices: state.choices,
      timesMs: [for (final a in state.answers) submittedMs(a.elapsed)],
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
