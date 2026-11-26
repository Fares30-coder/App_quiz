import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../backend/auth_service.dart';
import '../backend/supabase_progress_source.dart';
import '../backend/supabase_provider.dart';
import '../data/pending_quiz_repository.dart';
import '../models/player_progress.dart';
import '../models/quiz_submission.dart';
import '../models/server_profile.dart';
import '../models/streak.dart';
import 'progress_controller.dart';

/// Règle de fusion (voir aussi `supabase/README.md`) :
/// - tant que `last_quiz_at` du serveur est `null` (aucun quiz soumis via
///   `submit_quiz()`), la progression locale est conservée telle quelle ;
/// - dès qu'il est renseigné, le serveur fait foi pour XP, série, gels et
///   compteur de quiz du jour (il les a recalculés lui-même) ;
/// - l'objectif du jour reste un choix local, jamais remplacé par le serveur
///   (il lui est envoyé via `set_daily_goal`).
/// Les jours affichés de la semaine (joués / gelés) restent ceux de l'appareil.
PlayerProgress mergeServerProgress(PlayerProgress local, ServerProfile server) {
  if (server.lastQuizAt == null) return local;
  return local.copyWith(
    totalXp: server.xp,
    streak: Streak(
      count: server.streak,
      lastPlayed: server.lastPlayedDay,
      freezes: server.freezes,
      playedDays: local.streak.playedDays,
      frozenDays: local.streak.frozenDays,
    ),
    quizzesDay: server.quizDay,
    quizzesCount: server.quizDay == null ? 0 : server.quizCount,
  );
}

/// Synchronisation de la progression avec `profiles`, toujours en
/// arrière-plan et sans jamais lever d'erreur : au lancement (dès qu'une
/// session existe) et au retour au premier plan, au plus une fois par
/// [minInterval]. Sans session ou hors ligne : aucun effet, mode local.
///
/// Les quiz terminés passent par une file locale ([PendingQuizRepository]) :
/// envoyés aussitôt à `submit_quiz`, sinon au sync suivant. Tant que la file
/// n'est pas vide, la progression locale (en avance) n'est pas remplacée.
class ProgressSync {
  ProgressSync(
    this._ref,
    this._source,
    this._queue, {
    this.minInterval = const Duration(minutes: 1),
  });

  final Ref _ref;
  final SupabaseProgressSource _source;
  final PendingQuizRepository _queue;
  final Duration minInterval;

  Future<void>? _pending;
  Future<void>? _flushing;
  DateTime? _lastAttempt;

  /// `last_quiz_at` du dernier profil appliqué : une lecture plus ancienne
  /// (partie avant un envoi de quiz) ne l'écrase pas.
  DateTime? _appliedQuizAt;

  /// Envoie les quiz en attente, lit le profil serveur, le fusionne, puis
  /// envoie l'objectif du jour s'il diffère (ce qui réessaie aussi un envoi
  /// précédent échoué). [force] ignore [minInterval] (nouvelle session).
  Future<void> sync({bool force = false}) =>
      _pending ??= _sync(force).whenComplete(() => _pending = null);

  Future<void> _sync(bool force) async {
    final userId = _ref.read(authUserIdProvider);
    if (userId == null) return;
    final last = _lastAttempt;
    if (!force &&
        last != null &&
        DateTime.now().difference(last) < minInterval) {
      return;
    }
    _lastAttempt = DateTime.now();
    try {
      await _flush();
    } catch (e) {
      _log('quiz en attente non envoyés, réessai au prochain sync', e);
    }
    try {
      final server = await _source.fetch(userId);
      if (server == null) return;
      final local = _ref.read(progressControllerProvider);
      if (_queue.isEmpty) _apply(server);
      if (local.onboardingDone && local.dailyGoal != server.dailyGoal) {
        await _source.setDailyGoal(local.dailyGoal);
      }
    } catch (e) {
      _log('synchronisation impossible, mode local', e);
    }
  }

  /// Quiz terminé (mode Supabase) : mis en file puis envoyé en arrière-plan.
  /// La réponse du serveur remplace la progression locale (règle de fusion).
  /// Sans session ou hors ligne : réessai au prochain [sync].
  Future<void> submitQuiz(QuizSubmission submission) async {
    await _queue.add(submission);
    if (_ref.read(authUserIdProvider) == null) return;
    try {
      await _flush();
    } catch (e) {
      _log('quiz non envoyé, réessai au prochain sync', e);
    }
  }

  /// Un seul envoi de la file à la fois (quiz terminé pendant un sync).
  Future<void> _flush() =>
      _flushing ??= _flushQueue().whenComplete(() => _flushing = null);

  /// Envoie la file dans l'ordre joué. Un quiz refusé définitivement est
  /// abandonné ; une erreur passagère arrête l'envoi (file conservée).
  Future<void> _flushQueue() async {
    ServerProfile? last;
    for (var queue = _queue.load(); queue.isNotEmpty; queue = _queue.load()) {
      final next = queue.first;
      try {
        last = (await _source.submitQuiz(next)).profile;
      } catch (e) {
        if (!isRejectedQuiz(e)) rethrow;
        _log('quiz refusé par le serveur, abandonné', e);
      }
      await _queue.remove(next.id);
    }
    if (last != null) _apply(last);
  }

  /// Applique le profil serveur selon [mergeServerProgress].
  void _apply(ServerProfile server) {
    final at = server.lastQuizAt;
    final applied = _appliedQuizAt;
    if (at != null && applied != null && at.isBefore(applied)) return;
    if (at != null) _appliedQuizAt = at;
    final local = _ref.read(progressControllerProvider);
    final merged = mergeServerProgress(local, server);
    if (!identical(merged, local)) {
      _ref.read(progressControllerProvider.notifier).replaceFromServer(merged);
    }
  }

  /// Envoie l'objectif du jour qui vient de changer. En cas d'échec, il sera
  /// renvoyé au prochain [sync] (comparaison avec le serveur).
  Future<void> pushDailyGoal(int goal) async {
    if (_ref.read(authUserIdProvider) == null) return;
    try {
      await _source.setDailyGoal(goal);
    } catch (e) {
      _log('envoi de l\'objectif impossible, réessai au prochain sync', e);
    }
  }
}

/// Jamais de données de session : type et code d'erreur seulement.
void _log(String message, Object error) {
  if (!kDebugMode) return;
  final detail = [
    error.runtimeType,
    if (error is PostgrestException) error.code,
  ].whereType<Object>().join(' ');
  debugPrint('Sync : $message ($detail)');
}

/// Synchronisation, `null` en mode 100 % local (aucun appel).
/// Lu par `RootGate` : se lance à l'ouverture de session et au premier plan.
final progressSyncProvider = Provider<ProgressSync?>((ref) {
  final client = ref.watch(supabaseClientProvider);
  if (client == null) return null;
  final sync = ProgressSync(
    ref,
    SupabaseProgressSource(client),
    ref.watch(pendingQuizRepositoryProvider),
  );

  // Lancement : dès que la connexion (anonyme ou restaurée) aboutit.
  ref.listen<String?>(
    authUserIdProvider,
    (previous, next) {
      if (next != null && next != previous) unawaited(sync.sync(force: true));
    },
    fireImmediately: true,
  );
  // Objectif du jour modifié (premier lancement ou profil).
  ref.listen<int>(
    progressControllerProvider.select((p) => p.dailyGoal),
    (previous, next) {
      if (previous != null && previous != next) {
        unawaited(sync.pushDailyGoal(next));
      }
    },
  );
  final lifecycle =
      AppLifecycleListener(onResume: () => unawaited(sync.sync()));
  ref.onDispose(lifecycle.dispose);
  return sync;
});
