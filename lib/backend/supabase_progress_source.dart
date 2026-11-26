import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/offline_day.dart';
import '../models/quiz_submission.dart';
import '../models/server_profile.dart';

/// Accès Supabase à la progression : lecture de `profiles`, objectif du
/// jour (`set_daily_goal`), quiz terminés (`submit_quiz`) et journées
/// validées hors ligne (`validate_offline_day`). Aucune écriture
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

  /// Fait valider la journée d'un quiz joué hors ligne (série, gels,
  /// compteur du jour ; ni XP ni classement) et renvoie le profil à jour.
  /// Lève une erreur en cas d'échec (voir [isRejectedQuiz]).
  Future<OfflineDayResult> validateOfflineDay(OfflineDay day) async {
    final json = await _client.rpc<Map<String, dynamic>>(
      'validate_offline_day',
      params: day.toRpcParams(),
    );
    return OfflineDayResult.fromJson(json);
  }
}

/// Codes SQLSTATE d'un refus définitif de `submit_quiz` : entrée invalide
/// (22023), valeur mal formée (22P02), hors limites (22003), identifiant de
/// quiz déjà pris (23505), profil absent (P0002).
const rejectedQuizCodes = {'22023', '22P02', '22003', '23505', 'P0002'};

/// Quiz refusé définitivement : inutile de le renvoyer (il bloquerait la
/// file). Les autres erreurs (réseau, trop de quiz dans l'heure `PT429`,
/// migration pas encore appliquée…) sont passagères.
bool isRejectedQuiz(Object error) =>
    error is PostgrestException && rejectedQuizCodes.contains(error.code);
