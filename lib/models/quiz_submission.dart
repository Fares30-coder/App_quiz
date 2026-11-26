import 'server_profile.dart';

/// Quiz servi et entièrement répondu, à faire valider par le serveur
/// (RPC `submit_quiz(quiz_id)`).
///
/// Le serveur a déjà les questions servies et les réponses horodatées
/// (`start_quiz`, `answer_question`) : seul [id] est envoyé. La validation
/// est idempotente (réessai après coupure réseau).
class QuizSubmission {
  const QuizSubmission({
    required this.id,
    required this.userId,
    required this.playedAt,
  });

  /// Temps de réponse acceptés par le serveur (millisecondes).
  static const minMs = 500;
  static const maxMs = 30000;

  /// Retard maximal accepté par le serveur entre la dernière réponse et
  /// la validation.
  static const maxDelay = Duration(hours: 6);

  /// Identifiant de session renvoyé par `start_quiz`.
  final String id;

  /// Compte qui a joué le quiz : jamais envoyé sous un autre compte.
  final String userId;

  /// Fin du quiz (heure de l'appareil) : sert seulement à abandonner
  /// localement un quiz trop ancien ; le serveur prend l'heure de la
  /// dernière réponse enregistrée.
  final DateTime playedAt;

  /// Trop ancien pour le serveur (refus certain) : à abandonner.
  bool isExpiredAt(DateTime now) => now.difference(playedAt) > maxDelay;

  /// Paramètres de la RPC `submit_quiz`.
  Map<String, dynamic> toRpcParams() => {'quiz_id': id};

  /// Stockage local (file d'attente hors ligne).
  Map<String, dynamic> toJson() => {
        'id': id,
        'userId': userId,
        'playedAt': playedAt.toUtc().toIso8601String(),
      };

  factory QuizSubmission.fromJson(Map<String, dynamic> json) => QuizSubmission(
        id: json['id'] as String,
        userId: json['userId'] as String? ?? '',
        playedAt: DateTime.parse(json['playedAt'] as String),
      );
}

/// Temps envoyé au serveur pour une réponse, borné à l'intervalle accepté :
/// le minuteur peut dépasser 30 s de quelques millisecondes, et un toucher
/// très rapide (< 0,5 s) ne doit pas faire refuser la réponse.
int submittedMs(Duration elapsed) =>
    elapsed.inMilliseconds.clamp(QuizSubmission.minMs, QuizSubmission.maxMs);

/// Réponse de `submit_quiz` : détail du quiz et profil recalculé.
class SubmitQuizResult {
  const SubmitQuizResult({
    required this.score,
    required this.total,
    required this.xpGained,
    required this.xpCapped,
    required this.duplicate,
    required this.profile,
  });

  final int score;
  final int total;
  final int xpGained;

  /// XP réduite par le plafond du jour.
  final bool xpCapped;

  /// Quiz déjà validé auparavant (rien n'a été recompté).
  final bool duplicate;
  final ServerProfile profile;

  factory SubmitQuizResult.fromJson(Map<String, dynamic> json) =>
      SubmitQuizResult(
        score: (json['score'] as num).toInt(),
        total: (json['total'] as num).toInt(),
        xpGained: (json['xp_gained'] as num).toInt(),
        xpCapped: json['xp_capped'] as bool? ?? false,
        duplicate: json['duplicate'] as bool? ?? false,
        profile:
            ServerProfile.fromJson(json['profile'] as Map<String, dynamic>),
      );
}
