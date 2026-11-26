import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../backend/auth_service.dart';
import '../data/leaderboard_repository.dart';
import '../engagement/progress_controller.dart';
import '../engagement/progress_sync.dart';
import '../models/weekly_leaderboard.dart';

/// Classement hebdo global, lu sur le serveur.
///
/// Valeur `null` en mode 100 % local ou sans session (aucun appel) : l'écran
/// affiche alors un message, jamais un faux classement. Rechargé à
/// l'ouverture de session, après chaque quiz validé par le serveur, par
/// tirage ([refresh]) et à l'ouverture de l'onglet s'il date ([refreshIfStale]).
/// En cas d'erreur (hors ligne), le dernier classement chargé reste
/// disponible dans `AsyncError.value`.
class LeaderboardController extends AsyncNotifier<WeeklyLeaderboard?> {
  /// Au-delà, l'ouverture de l'onglet recharge le classement.
  static const maxAge = Duration(minutes: 1);

  DateTime? _fetchedAt;

  @override
  Future<WeeklyLeaderboard?> build() async {
    final repo = ref.watch(leaderboardRepositoryProvider);
    final userId = ref.watch(authUserIdProvider);
    ref.watch(validatedQuizzesProvider);
    if (repo == null || userId == null) return null;
    final board = await repo.fetchWeekly();
    _fetchedAt = ref.read(clockProvider)();
    return board;
  }

  /// Recharge et attend le résultat. Ne lève jamais d'erreur (elle reste
  /// dans l'état).
  Future<void> refresh() async {
    ref.invalidateSelf();
    try {
      await future;
    } catch (_) {}
  }

  /// Recharge si le dernier chargement réussi date de plus de [maxAge] ou
  /// a échoué.
  void refreshIfStale() {
    if (state.isLoading) return;
    final at = _fetchedAt;
    final now = ref.read(clockProvider)();
    if (state.hasError || at == null || now.difference(at) >= maxAge) {
      ref.invalidateSelf();
    }
  }
}

final leaderboardProvider =
    AsyncNotifierProvider<LeaderboardController, WeeklyLeaderboard?>(
  LeaderboardController.new,
);
