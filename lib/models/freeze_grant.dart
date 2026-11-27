import 'server_profile.dart';

/// Réponse de `grant_rewarded_freeze()` (gel après une pub récompensée).
class FreezeGrantResult {
  const FreezeGrantResult({
    required this.granted,
    required this.reason,
    required this.profile,
  });

  final bool granted;

  /// `daily_limit` (gel déjà obtenu aujourd'hui) ou `full` (2 en réserve)
  /// si [granted] est faux.
  final String? reason;

  /// Profil après l'appel (jours manqués appliqués, gel ajouté s'il l'est).
  final ServerProfile profile;

  factory FreezeGrantResult.fromJson(Map<String, dynamic> json) =>
      FreezeGrantResult(
        granted: json['granted'] as bool? ?? false,
        reason: json['reason'] as String?,
        profile:
            ServerProfile.fromJson(json['profile'] as Map<String, dynamic>),
      );
}
