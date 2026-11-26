import 'dart:math';

import 'server_profile.dart';

/// Quiz terminé à faire valider par le serveur (RPC `submit_quiz`).
///
/// Le serveur recalcule score, XP et série à partir de ces seules données ;
/// [id] rend la soumission idempotente (réessai après coupure réseau).
class QuizSubmission {
  const QuizSubmission({
    required this.id,
    required this.questionIds,
    required this.choices,
    required this.timesMs,
    required this.playedAt,
  });

  /// Temps de réponse acceptés par le serveur (millisecondes).
  static const minMs = 500;
  static const maxMs = 30000;

  final String id;
  final List<String> questionIds;

  /// Réponse choisie, index dans l'ordre d'origine ; `null` = temps écoulé.
  final List<int?> choices;
  final List<int> timesMs;

  /// Fin du quiz (heure de l'appareil, bornée par le serveur).
  final DateTime playedAt;

  /// Paramètres de la RPC `submit_quiz`.
  Map<String, dynamic> toRpcParams() => {
        'quiz_id': id,
        'question_ids': questionIds,
        'choices': choices,
        'times_ms': timesMs,
        'played_at': playedAt.toUtc().toIso8601String(),
      };

  /// Stockage local (file d'attente hors ligne).
  Map<String, dynamic> toJson() => {
        'id': id,
        'questionIds': questionIds,
        'choices': choices,
        'timesMs': timesMs,
        'playedAt': playedAt.toUtc().toIso8601String(),
      };

  factory QuizSubmission.fromJson(Map<String, dynamic> json) => QuizSubmission(
        id: json['id'] as String,
        questionIds: List<String>.from(json['questionIds'] as List),
        choices: [for (final c in json['choices'] as List) c as int?],
        timesMs: List<int>.from(json['timesMs'] as List),
        playedAt: DateTime.parse(json['playedAt'] as String),
      );
}

/// Temps envoyé au serveur pour une réponse : borné à [QuizSubmission.maxMs]
/// (le minuteur peut dépasser 30 s de quelques millisecondes).
int submittedMs(Duration elapsed) =>
    elapsed.inMilliseconds.clamp(0, QuizSubmission.maxMs);

/// Identifiant aléatoire au format UUID v4 (identifiant de quiz).
String randomUuid([Random? random]) {
  final r = random ?? Random.secure();
  final bytes = [for (var i = 0; i < 16; i++) r.nextInt(256)];
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  final hex = [for (final b in bytes) b.toRadixString(16).padLeft(2, '0')];
  return '${hex.sublist(0, 4).join()}-${hex.sublist(4, 6).join()}-'
      '${hex.sublist(6, 8).join()}-${hex.sublist(8, 10).join()}-'
      '${hex.sublist(10).join()}';
}

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
