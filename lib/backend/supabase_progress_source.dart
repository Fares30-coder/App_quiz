import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/server_profile.dart';

/// Accès Supabase à la progression : lecture de `profiles` et objectif du
/// jour via la RPC `set_daily_goal`. Aucune écriture directe sur la table
/// (refusée de toute façon par les GRANT et RLS).
class SupabaseProgressSource {
  SupabaseProgressSource(this._client);

  final SupabaseClient _client;

  /// Profil de [userId], ou `null` si la ligne n'existe pas (encore).
  /// Lève une erreur en cas de problème réseau ou serveur.
  Future<ServerProfile?> fetch(String userId) async {
    final row = await _client
        .from('profiles')
        .select(ServerProfile.columns)
        .eq('id', userId)
        .maybeSingle();
    return row == null ? null : ServerProfile.fromJson(row);
  }

  /// Seule écriture autorisée au client. Lève une erreur en cas d'échec.
  Future<void> setDailyGoal(int goal) =>
      _client.rpc<void>('set_daily_goal', params: {'goal': goal});
}
