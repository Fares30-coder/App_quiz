import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../backend/supabase_provider.dart';
import '../models/weekly_leaderboard.dart';

/// Lecture du classement hebdo (RPC `weekly_leaderboard`, lecture seule).
class LeaderboardRepository {
  LeaderboardRepository(this._client);

  final SupabaseClient _client;

  /// Nombre de joueurs affichés (le rang du joueur arrive même hors du top).
  static const topSize = 50;

  /// Classement de la semaine en cours. Lève une erreur en cas de problème
  /// réseau ou serveur.
  Future<WeeklyLeaderboard> fetchWeekly() async {
    final json = await _client.rpc<Map<String, dynamic>>(
      'weekly_leaderboard',
      params: {'max_entries': topSize},
    );
    return WeeklyLeaderboard.fromJson(json);
  }
}

/// `null` en mode 100 % local (aucun classement en ligne).
final leaderboardRepositoryProvider = Provider<LeaderboardRepository?>((ref) {
  final client = ref.watch(supabaseClientProvider);
  return client == null ? null : LeaderboardRepository(client);
});
