/// Motif d'un signalement de question (RPC `report_question`, 4 motifs
/// fixes, pas de texte libre).
enum ReportReason {
  wrongAnswer('fausse', 'Réponse fausse'),
  ambiguous('ambigue', 'Question ambiguë'),
  typo('faute', 'Faute ou coquille'),
  other('autre', 'Autre');

  const ReportReason(this.param, this.label);

  /// Valeur du paramètre `p_reason`.
  final String param;

  /// Libellé affiché.
  final String label;
}
