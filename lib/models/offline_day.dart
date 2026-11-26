import 'quiz_submission.dart';
import 'server_profile.dart';

/// Journée validée par un quiz local (hors ligne, lot `assets/`) en mode
/// Supabase, à faire valider par le serveur (RPC `validate_offline_day`) au
/// sync suivant : la série est gardée, sans XP ni classement.
class OfflineDay {
  const OfflineDay({required this.userId, required this.playedAt});

  /// Compte connecté à la fin du quiz : jamais envoyé sous un autre compte.
  final String userId;

  /// Fin du quiz (heure de l'appareil). Le serveur en déduit le jour
  /// (Europe/Paris) et refuse un horodatage futur ou de plus de 6 h.
  final DateTime playedAt;

  /// Trop ancien pour le serveur (refus certain) : à abandonner.
  bool isExpiredAt(DateTime now) =>
      now.difference(playedAt) > QuizSubmission.maxDelay;

  /// Paramètres de la RPC `validate_offline_day`.
  Map<String, dynamic> toRpcParams() =>
      {'played_at': playedAt.toUtc().toIso8601String()};

  /// Stockage local (file d'attente).
  Map<String, dynamic> toJson() => {
        'userId': userId,
        'playedAt': playedAt.toUtc().toIso8601String(),
      };

  factory OfflineDay.fromJson(Map<String, dynamic> json) => OfflineDay(
        userId: json['userId'] as String? ?? '',
        playedAt: DateTime.parse(json['playedAt'] as String),
      );

  @override
  bool operator ==(Object other) =>
      other is OfflineDay &&
      other.userId == userId &&
      other.playedAt.isAtSameMomentAs(playedAt);

  @override
  int get hashCode => Object.hash(userId, playedAt.toUtc());
}

/// Réponse de `validate_offline_day` : jour validé ou refus propre (déjà
/// validé, plafond de jours hors ligne), avec le profil serveur.
class OfflineDayResult {
  const OfflineDayResult({
    required this.validated,
    required this.reason,
    required this.profile,
  });

  final bool validated;

  /// `already_validated` ou `limit` si [validated] est faux.
  final String? reason;
  final ServerProfile profile;

  factory OfflineDayResult.fromJson(Map<String, dynamic> json) =>
      OfflineDayResult(
        validated: json['validated'] as bool? ?? false,
        reason: json['reason'] as String?,
        profile:
            ServerProfile.fromJson(json['profile'] as Map<String, dynamic>),
      );
}
