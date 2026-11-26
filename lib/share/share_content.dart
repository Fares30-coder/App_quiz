/// Contenu de l'image de partage 9:16 (TikTok / Stories) et du texte joint.
/// Logique pure : aucun accès à Flutter, testée dans `test/share_test.dart`.
/// Rien de personnel : ni pseudo, ni e-mail.
library;

import '../engagement/dates.dart';
import '../quiz/quiz_controller.dart';

/// Lien de téléchargement ajouté au texte partagé.
// TODO(publication): renseigner le lien (page web qui redirige vers l'App
// Store / Google Play) une fois l'app publiée. Null = pas de lien.
const String? shareStoreLink = null;

/// Espace insécable avant « ? » (typographie française).
const _nbsp = ' ';

enum ShareKind { score, streak }

class ShareContent {
  const ShareContent({
    required this.kind,
    required this.overline,
    required this.headline,
    required this.challenge,
    required this.cta,
    required this.message,
    required this.fileName,
    this.score = 0,
    this.total = 0,
    this.answers = const [],
    this.streakDays = 0,
    this.streakLabel,
  });

  final ShareKind kind;

  /// Surtitre en capitales : « DÉFI DU JOUR · 25 NOV. ».
  final String overline;

  /// Phrase principale, sur deux lignes (`\n`).
  final String headline;

  /// Accroche : « Tu fais mieux ? ».
  final String challenge;

  /// Texte du bouton dessiné en bas de l'image.
  final String cta;

  /// Texte d'accompagnement envoyé avec l'image.
  final String message;

  /// Nom du fichier PNG temporaire.
  final String fileName;

  final int score;
  final int total;

  /// Juste / faux pour chaque question, dans l'ordre.
  final List<bool> answers;

  final int streakDays;

  /// Pilule de série (« 6 jours de série »), null si pas de série.
  final String? streakLabel;
}

String _days(int n) => n > 1 ? 'jours' : 'jour';

String streakLabelFor(int days) => '$days ${_days(days)} de série';

/// Complément de « J'ai eu 8/10 … ».
String _scopeFor(QuizMode mode, String? category) => switch (mode) {
      QuizMode.dailyChallenge => 'au défi du jour',
      QuizMode.mix => 'en culture G',
      QuizMode.category => switch (category) {
          'histoire' => 'en histoire',
          'geo' => 'en géo',
          'sciences' => 'en sciences',
          'arts' => 'en arts',
          'sport' => 'en sport',
          'actu' => 'sur l\'actu',
          _ => 'en culture G',
        },
    };

String _overlineTitle(QuizMode mode, String? category) => switch (mode) {
      QuizMode.dailyChallenge => 'Défi du jour',
      QuizMode.mix => 'Mélange',
      QuizMode.category => switch (category) {
          'histoire' => 'Histoire',
          'geo' => 'Géo',
          'sciences' => 'Sciences',
          'arts' => 'Arts',
          'sport' => 'Sport',
          'actu' => 'Actu',
          'divers' => 'Divers',
          _ => 'Quiz',
        },
    };

/// Jour du défi n° 1.
// TODO(publication): à ajuster au jour de publication de l'app (D3 : n° 1 =
// jour de publication).
final DateTime challengeStartDay = DateTime(2026, 12, 1);

/// Numéro du défi du jour [day] (jour calendaire local) : 1 le jour de
/// départ, puis +1 par jour. Null avant le départ.
int? challengeNumber(DateTime day) {
  final n = daysBetween(challengeStartDay, day) + 1;
  return n >= 1 ? n : null;
}

/// Grille sans spoiler : « Quizzéo · Défi n° 42 · 8/10 », une case par
/// réponse (🟩 juste, 🟥 fausse ou temps écoulé), puis « 🔥 6 » si série.
/// Aucun texte de question ni de réponse.
String shareGrid({
  required QuizMode mode,
  required int score,
  required int total,
  required List<bool> answers,
  required int streakDays,
  required DateTime day,
}) {
  final number = mode == QuizMode.dailyChallenge ? challengeNumber(day) : null;
  return [
    [
      'Quizzéo',
      if (number != null) 'Défi n° $number',
      '$score/$total',
    ].join(' · '),
    answers.map((a) => a ? '🟩' : '🟥').join(),
    if (streakDays > 0) '🔥 $streakDays',
  ].join('\n');
}

String _withLink(String text) =>
    shareStoreLink == null ? text : '$text\n$shareStoreLink';

/// Image du score (écran Résultats).
ShareContent scoreShareContent({
  required QuizMode mode,
  String? category,
  required int score,
  required int total,
  required List<bool> answers,
  required int streakDays,
  required DateTime day,
}) {
  final scope = _scopeFor(mode, category);
  final challenge = total > 0 && score == total
      ? 'Qui fait aussi bien$_nbsp?'
      : score * 2 < total
          ? 'Tu as combien$_nbsp?'
          : 'Tu fais mieux$_nbsp?';
  final daily = mode == QuizMode.dailyChallenge;
  final grid = shareGrid(
    mode: mode,
    score: score,
    total: total,
    answers: answers,
    streakDays: streakDays,
    day: day,
  );
  return ShareContent(
    kind: ShareKind.score,
    overline: '${_overlineTitle(mode, category)} · ${formatDayMonth(day)}'
        .toUpperCase(),
    headline: 'J\'ai eu $score/$total\n$scope',
    challenge: challenge,
    cta: daily ? 'Joue le défi sur Quizzéo' : 'Joue sur Quizzéo',
    message: _withLink(
      '$grid\n\nJ\'ai eu $score/$total $scope sur Quizzéo. $challenge',
    ),
    fileName: 'quizzeo-score-$score-sur-$total.png',
    score: score,
    total: total,
    answers: answers,
    streakDays: streakDays,
    streakLabel: streakDays > 0 ? streakLabelFor(streakDays) : null,
  );
}

/// Image de la série (écran « Série validée »).
ShareContent streakShareContent({
  required int streakDays,
  required DateTime day,
}) {
  const challenge = 'Tu tiens combien$_nbsp?';
  return ShareContent(
    kind: ShareKind.streak,
    overline: 'Ma série · ${formatDayMonth(day)}'.toUpperCase(),
    headline: streakDays > 1
        ? 'Série validée\npour aujourd\'hui'
        : 'Ma série commence\naujourd\'hui',
    challenge: challenge,
    cta: 'Lance ta série sur Quizzéo',
    message: _withLink('${streakLabelFor(streakDays)} sur Quizzéo. $challenge'),
    fileName: 'quizzeo-serie-$streakDays.png',
    streakDays: streakDays,
  );
}
