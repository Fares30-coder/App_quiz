import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/quiz_submission.dart';
import '../models/server_profile.dart';

/// Accès Supabase à la progression : lecture de `profiles`, objectif du
/// jour (`set_daily_goal`) et quiz terminés (`submit_quiz`). Aucune écriture
/// directe sur la table (refusée de toute façon par les GRANT et RLS).
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

  /// Objectif du jour. Lève une erreur en cas d'échec.
  Future<void> setDailyGoal(int goal) =>
      _client.rpc<void>('set_daily_goal', params: {'goal': goal});

  /// Fait valider un quiz terminé : le serveur recalcule score, XP et série
  /// et renvoie le profil mis à jour. Lève une erreur en cas d'échec
  /// (voir [isRejectedQuiz]).
  Future<SubmitQuizResult> submitQuiz(QuizSubmission submission) async {
    final json = await _client.rpc<Map<String, dynamic>>(
      'submit_quiz',
      params: submission.toRpcParams(),
    );
    return SubmitQuizResult.fromJson(json);
  }
}

/// Quiz refusé définitivement par `submit_quiz` (entrée invalide, code
/// 22023) : inutile de le renvoyer. Les autres erreurs (réseau, trop de
/// quiz dans l'heure, migration pas encore appliquée…) sont passagères.
bool isRejectedQuiz(Object error) =>
    error is PostgrestException && error.code == '22023';
