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

  /// Délai minimum entre deux rafraîchissements par tirage (limite les
  /// appels répétés). Un quiz validé recharge toujours, sans délai.
  static const minRefreshInterval = Duration(seconds: 10);

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

  /// Tirage : recharge et attend le résultat, sauf si le dernier chargement
  /// réussi date de moins de [minRefreshInterval]. Ne lève jamais d'erreur
  /// (elle reste dans l'état).
  Future<void> refresh() async {
    if (!_isOlderThan(minRefreshInterval)) return;
    ref.invalidateSelf();
    try {
      await future;
    } catch (_) {}
  }

  /// Recharge si le dernier chargement réussi date de plus de [maxAge] ou
  /// a échoué.
  void refreshIfStale() {
    if (state.isLoading) return;
    if (_isOlderThan(maxAge)) ref.invalidateSelf();
  }

  /// Vrai si le dernier chargement a échoué, n'a pas eu lieu ou date de plus
  /// de [age].
  bool _isOlderThan(Duration age) {
    final at = _fetchedAt;
    return state.hasError ||
        at == null ||
        ref.read(clockProvider)().difference(at) >= age;
  }
}

final leaderboardProvider =
    AsyncNotifierProvider<LeaderboardController, WeeklyLeaderboard?>(
  LeaderboardController.new,
);
