/// Barème XP et niveaux (règles validées, voir CLAUDE.md § Engagement).
library;

const xpCorrect = 10;
const xpSpeed = 5;
const xpCombo = 5;
const xpCompleted = 20;
const xpPerfect = 30;

/// Bonus rapidité : réponse donnée en moins de 10 s.
const speedBonusLimit = Duration(seconds: 10);

/// Bonus combo à partir de la 3e bonne réponse d'affilée.
const comboBonusFrom = 3;

/// Résultat d'une réponse, tel que vu par le barème.
class AnswerResult {
  const AnswerResult({required this.correct, required this.elapsed});

  final bool correct;

  /// Temps mis pour répondre (30 s si le temps est écoulé).
  final Duration elapsed;
}

/// XP gagnés sur une seule réponse.
class AnswerXp {
  const AnswerXp({this.base = 0, this.speed = 0, this.combo = 0});

  final int base;
  final int speed;
  final int combo;

  int get total => base + speed + combo;
}

/// Combo après une réponse : +1 si bonne, retour à 0 sinon.
int nextCombo(int combo, bool correct) => correct ? combo + 1 : 0;

/// XP d'une réponse. [combo] = nombre de bonnes réponses d'affilée, celle-ci comprise.
AnswerXp answerXp({
  required bool correct,
  required Duration elapsed,
  required int combo,
}) {
  if (!correct) return const AnswerXp();
  return AnswerXp(
    base: xpCorrect,
    speed: elapsed < speedBonusLimit ? xpSpeed : 0,
    combo: combo >= comboBonusFrom ? xpCombo : 0,
  );
}

/// Détail des XP d'un quiz terminé.
class QuizXp {
  const QuizXp({
    required this.correctCount,
    required this.speedCount,
    required this.comboCount,
    required this.maxCombo,
    required this.perfect,
  });

  final int correctCount;
  final int speedCount;

  /// Nombre de bonnes réponses ayant donné le bonus combo.
  final int comboCount;
  final int maxCombo;
  final bool perfect;

  int get correctXp => correctCount * xpCorrect;
  int get speedXp => speedCount * xpSpeed;
  int get comboXp => comboCount * xpCombo;
  int get completedXp => xpCompleted;
  int get perfectXp => perfect ? xpPerfect : 0;
  int get total => correctXp + speedXp + comboXp + completedXp + perfectXp;
}

/// XP d'un quiz terminé (le bonus « quiz terminé » est toujours compté).
QuizXp quizXp(List<AnswerResult> answers) {
  var combo = 0;
  var maxCombo = 0;
  var correct = 0;
  var speed = 0;
  var comboBonus = 0;
  for (final a in answers) {
    combo = nextCombo(combo, a.correct);
    if (combo > maxCombo) maxCombo = combo;
    final xp = answerXp(correct: a.correct, elapsed: a.elapsed, combo: combo);
    if (a.correct) correct++;
    if (xp.speed > 0) speed++;
    if (xp.combo > 0) comboBonus++;
  }
  return QuizXp(
    correctCount: correct,
    speedCount: speed,
    comboCount: comboBonus,
    maxCombo: maxCombo,
    perfect: answers.isNotEmpty && correct == answers.length,
  );
}

/// XP pour passer du niveau [level] au suivant : 100 + 50 × (n − 1).
int xpToNextLevel(int level) => 100 + 50 * (level - 1);

/// Position dans les niveaux pour un total d'XP.
class LevelProgress {
  const LevelProgress({
    required this.level,
    required this.xpInLevel,
    required this.xpForNext,
  });

  final int level;

  /// XP acquis dans le niveau en cours.
  final int xpInLevel;

  /// XP nécessaires pour passer au niveau suivant.
  final int xpForNext;

  int get xpRemaining => xpForNext - xpInLevel;
  double get fraction => xpInLevel / xpForNext;
}

LevelProgress levelFor(int totalXp) {
  var level = 1;
  var rest = totalXp < 0 ? 0 : totalXp;
  while (rest >= xpToNextLevel(level)) {
    rest -= xpToNextLevel(level);
    level++;
  }
  return LevelProgress(
    level: level,
    xpInLevel: rest,
    xpForNext: xpToNextLevel(level),
  );
}
