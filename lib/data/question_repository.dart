import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../backend/auth_service.dart';
import '../backend/supabase_provider.dart';
import '../backend/supabase_quiz_source.dart';
import '../engagement/daily_challenge.dart';
import '../models/question.dart';
import '../models/question_report.dart';
import '../models/quiz_session.dart';

const quizLength = 10;

/// Questions d'un quiz.
///
/// Mode Supabase (client configuré et joueur connecté) : le serveur tire les
/// questions (`start_quiz`, défi du jour identique pour tous), les envoie
/// une à une (`next_question`, temps de réponse mesuré par le serveur) et
/// corrige chaque réponse (`answer_question`) ; seuls ces quiz comptent au
/// classement. Sinon (mode 100 % local, hors ligne, serveur indisponible ou
/// pas assez de questions) : lot hors ligne (assets/questions.json, jamais
/// servi par le serveur), quiz hors classement.
///
/// Défi du jour : le serveur reprend la session déjà commencée aujourd'hui
/// ([QuizStart.answered]) ; s'il est déjà soumis, [startQuiz] lève
/// [DailyChallengeAlreadyPlayed] (pas de repli local).
class QuestionRepository {
  /// [questions] : liste déjà chargée (tests).
  QuestionRepository({
    AssetBundle? bundle,
    List<Question>? questions,
    SupabaseQuizSource? remote,
    String? Function()? userId,
    this.timeout = const Duration(seconds: 6),
    this.retryDelay = const Duration(minutes: 1),
    DateTime Function()? now,
  })  : _bundle = bundle ?? rootBundle,
        _cache = questions,
        _remote = remote,
        _userId = userId,
        _now = now ?? DateTime.now;

  final AssetBundle _bundle;
  List<Question>? _cache;
  final SupabaseQuizSource? _remote;
  final String? Function()? _userId;

  /// Délai maximal d'attente du serveur avant le repli local (départ) ou
  /// l'erreur (réponse).
  final Duration timeout;

  /// Après un échec de `start_quiz` (délai dépassé, réseau, limite), le
  /// serveur n'est plus sollicité pendant ce délai : chaque appel peut
  /// créer une session, qui compte dans les limites du serveur.
  final Duration retryDelay;
  final DateTime Function() _now;
  DateTime? _retryAfter;

  Future<List<Question>> all() async {
    if (_cache != null) return _cache!;
    final raw = await _bundle.loadString('assets/questions.json');
    final list = jsonDecode(raw) as List;
    return _cache = [
      for (final e in list) Question.fromJson(e as Map<String, dynamic>),
    ];
  }

  /// Quiz à jouer : servi par le serveur si possible, sinon local.
  Future<QuizStart> startQuiz({
    required QuizMode mode,
    String? category,
    required DateTime today,
    Random? random,
  }) async {
    final remote = _remote;
    UnrankedReason? unranked;
    if (remote != null) {
      final uid = _userId?.call();
      final retryAfter = _retryAfter;
      if (uid == null || (retryAfter != null && _now().isBefore(retryAfter))) {
        unranked = UnrankedReason.offline;
      } else {
        try {
          final served =
              await remote.start(mode, category: category).timeout(timeout);
          _retryAfter = null;
          return QuizStart(
            questions: served.questions,
            quizId: served.id,
            userId: uid,
            answered: served.answered,
            total: served.total,
            secondsLeft: served.secondsLeft,
          );
        } catch (e) {
          final played = mode == QuizMode.dailyChallenge
              ? challengeAlreadyPlayed(e)
              : null;
          if (played != null) throw played;
          _log('quiz local (hors classement)', e);
          if (isNotEnoughQuestions(e)) {
            unranked = UnrankedReason.notEnoughQuestions;
          } else {
            unranked = UnrankedReason.offline;
            _retryAfter = _now().add(retryDelay);
          }
        }
      }
    }
    final questions = switch (mode) {
      QuizMode.dailyChallenge => await dailyChallenge(today),
      QuizMode.mix => await pickQuiz(random: random),
      QuizMode.category => await pickQuiz(category: category, random: random),
    };
    return QuizStart(questions: questions, unranked: unranked);
  }

  /// Question suivante d'un quiz servi. Lève une erreur (réseau, refus) : le
  /// quiz attend alors un nouvel essai.
  Future<ServedQuestion> nextQuestion({required String quizId}) {
    final remote = _remote;
    if (remote == null) {
      throw StateError('quiz servi sans serveur configuré');
    }
    return remote.next(quizId).timeout(timeout);
  }

  /// Correction d'une réponse à un quiz servi. Lève une erreur (réseau,
  /// refus) : le quiz attend alors un nouvel essai.
  Future<AnswerCorrection> answer({
    required String quizId,
    required int position,
    required int? choice,
    required int timeMs,
  }) {
    final remote = _remote;
    if (remote == null) {
      throw StateError('quiz servi sans serveur configuré');
    }
    return remote
        .answer(
          quizId: quizId,
          position: position,
          choice: choice,
          timeMs: timeMs,
        )
        .timeout(timeout);
  }

  /// Signale une question déjà répondue d'un quiz servi (par sa position).
  /// Lève une erreur (réseau, refus, `PT429` au-delà de 20 par jour).
  Future<void> reportQuestion({
    required String quizId,
    required int position,
    required ReportReason reason,
  }) {
    final remote = _remote;
    if (remote == null) {
      throw StateError('quiz servi sans serveur configuré');
    }
    return remote
        .reportQuestion(quizId: quizId, position: position, reason: reason)
        .timeout(timeout);
  }

  /// Tire jusqu'à [count] questions locales au hasard, filtrées par
  /// [category] si fournie.
  Future<List<Question>> pickQuiz({
    String? category,
    int count = quizLength,
    Random? random,
  }) async {
    final r = random ?? Random();
    final pool = (await all())
        .where((q) => category == null || q.category == category)
        .toList()
      ..shuffle(r);
    return [for (final q in pool.take(count)) q.shuffled(r)];
  }

  /// Défi du jour local (repli hors ligne) : mêmes questions pour tous à une
  /// date donnée, mais distinct du défi choisi par le serveur.
  Future<List<Question>> dailyChallenge(DateTime day) async =>
      pickDailyChallenge(await all(), day);
}

/// Jamais de données de session : type et code d'erreur seulement.
void _log(String message, Object error) {
  if (!kDebugMode) return;
  final detail = [
    error.runtimeType,
    if (error is PostgrestException) error.code,
  ].whereType<Object>().join(' ');
  debugPrint('Questions : $message ($detail)');
}

final questionRepositoryProvider = Provider((ref) {
  final client = ref.watch(supabaseClientProvider);
  return QuestionRepository(
    remote: client == null ? null : SupabaseQuizSource(client),
    userId: () => ref.read(authUserIdProvider),
  );
});
