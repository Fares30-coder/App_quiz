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
    int? total,
    this.index = 0,
    this.selected,
    this.timedOut = false,
    this.answerFailed = false,
    this.loadingNext = false,
    this.nextFailed = false,
    this.secondsLeft = questionSeconds,
    this.answers = const [],
    this.outcome,
  }) : _total = total;

  final QuizMode mode;

  /// Catégorie jouée (mode [QuizMode.category]).
  final String? category;

  /// Session `start_quiz` (quiz servi, compte au classement) ; `null` pour
  /// un quiz local.
  final String? quizId;

  /// Compte qui a commencé le quiz servi.
  final String? userId;

  /// Questions dans l'ordre joué ; une question servie reçoit sa bonne
  /// réponse et son explication une fois répondue. Quiz servi : seulement
  /// les questions déjà reçues (une à une, `next_question`).
  final List<Question> questions;

  /// Nombre de questions du quiz (y compris celles pas encore reçues).
  int get total => _total ?? questions.length;
  final int? _total;
  final int index;

  /// Réponse choisie pour la question en cours (null = pas encore répondu).
  final int? selected;
  final bool timedOut;

  /// Correction impossible à obtenir du serveur (réseau) : la réponse est
  /// gardée, à renvoyer avec [QuizController.retryAnswer].
  final bool answerFailed;

  /// Quiz servi : question suivante demandée au serveur.
  final bool loadingNext;

  /// Question suivante impossible à obtenir (réseau) : à redemander avec
  /// [QuizController.retryNext].
  final bool nextFailed;
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
  bool get isLast => index == total - 1;
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
    bool? loadingNext,
    bool? nextFailed,
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
        total: _total,
        index: index ?? this.index,
        selected: selected == null ? this.selected : selected(),
        timedOut: timedOut ?? this.timedOut,
        answerFailed: answerFailed ?? this.answerFailed,
        loadingNext: loadingNext ?? this.loadingNext,
        nextFailed: nextFailed ?? this.nextFailed,
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
  /// [total] : nombre de questions du quiz servi ([questions] ne contient
  /// que les questions déjà reçues) ; par défaut `questions.length`. Le
  /// chrono de 30 s démarre à la réception de chaque question.
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
    int? total,
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
      total: total,
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
      // Temps écoulé selon le serveur (question reçue il y a plus de 30 s,
      // tolérance comprise) : la réponse ne compte pas.
      final timedOut = correction.timedOut;
      if (timedOut) {
        state = state.copyWith(selected: () => null, timedOut: true);
      }
      return _reveal(
        timedOut ? null : choice,
        timedOut ? const Duration(seconds: questionSeconds) : elapsed,
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
  ///
  /// Quiz servi : la question suivante est demandée au serveur
  /// (`next_question`) ; le quiz reste sur la question corrigée pendant le
  /// chargement ([QuizState.loadingNext]) ou après un échec
  /// ([QuizState.nextFailed]) et renvoie true (le quiz continue).
  bool next() {
    if (!state.answered || state.isFinished) return false;
    if (state.isLast) {
      _finish();
      return false;
    }
    if (state.loadingNext) return true;
    final quizId = state.quizId;
    if (quizId != null && state.index + 1 >= state.questions.length) {
      unawaited(_loadNext(quizId));
      return true;
    }
    _goToNext(state.questions);
    return true;
  }

  /// Redemande la question suivante après un échec réseau.
  Future<void> retryNext() async {
    final quizId = state.quizId;
    if (quizId == null || !state.nextFailed || state.loadingNext) return;
    await _loadNext(quizId);
  }

  Future<void> _loadNext(String quizId) async {
    final index = state.index;
    bool stillCurrent() =>
        state.quizId == quizId &&
        state.index == index &&
        state.loadingNext &&
        !state.isFinished;
    state = state.copyWith(loadingNext: true, nextFailed: false);
    try {
      final served = await ref
          .read(questionRepositoryProvider)
          .nextQuestion(quizId: quizId);
      if (!stillCurrent()) return;
      // Position 1 à 10 : la question suivante est la position index + 2.
      if (served.position != index + 2) {
        throw StateError('question inattendue');
      }
      _goToNext([...state.questions, served.question]);
    } catch (_) {
      if (stillCurrent()) {
        state = state.copyWith(loadingNext: false, nextFailed: true);
      }
    }
  }

  /// Affiche la question suivante (déjà dans [questions]) et lance son chrono.
  void _goToNext(List<Question> questions) {
    state = state.copyWith(
      questions: questions,
      index: state.index + 1,
      selected: () => null,
      timedOut: false,
      loadingNext: false,
      nextFailed: false,
      secondsLeft: questionSeconds,
    );
    _startQuestion();
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
          total: state.total,
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
