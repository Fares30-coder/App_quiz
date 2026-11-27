/// Plafond de fréquence de l'interstitiel (Dart pur, sans Flutter ni SDK).
///
/// Une session = un lancement de l'app (l'objet vit dans le contrôleur).
/// Seuils par défaut : [quizzesPerAd], [minInterval], [firstAdAfterQuizzes].
class InterstitialPacing {
  InterstitialPacing({
    DateTime Function()? clock,
    this.quizzesPerAd = defaultQuizzesPerAd,
    this.minInterval = defaultMinInterval,
    this.firstAdAfterQuizzes = defaultFirstAdAfterQuizzes,
  }) : _clock = clock ?? DateTime.now;

  /// Au plus 1 pub tous les N quiz terminés.
  static const defaultQuizzesPerAd = 2;

  /// Au plus 1 pub par intervalle.
  static const defaultMinInterval = Duration(minutes: 3);

  /// Rien avant ce nombre de quiz terminés dans la session (2 : jamais après
  /// le premier quiz).
  static const defaultFirstAdAfterQuizzes = 2;

  final DateTime Function() _clock;
  final int quizzesPerAd;
  final Duration minInterval;
  final int firstAdAfterQuizzes;

  int _quizzesInSession = 0;
  int _quizzesSinceAd = 0;
  DateTime? _lastShownAt;

  int get quizzesInSession => _quizzesInSession;
  int get quizzesSinceAd => _quizzesSinceAd;

  /// Un quiz vient d'être terminé (pas un abandon).
  void quizCompleted() {
    _quizzesInSession++;
    _quizzesSinceAd++;
  }

  /// Vrai si une pub peut être affichée maintenant.
  bool get canShow {
    if (_quizzesInSession < firstAdAfterQuizzes) return false;
    if (_quizzesSinceAd < quizzesPerAd) return false;
    final last = _lastShownAt;
    return last == null || _clock().difference(last) >= minInterval;
  }

  /// Une pub vient d'être affichée : compteur et délai repartent de zéro.
  void adShown() {
    _quizzesSinceAd = 0;
    _lastShownAt = _clock();
  }
}
