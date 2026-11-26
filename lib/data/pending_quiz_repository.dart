import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/quiz_submission.dart';
import 'progress_repository.dart';

/// File d'attente locale des quiz pas encore validés par le serveur
/// (hors ligne, erreur passagère). Chaque quiz porte le compte qui l'a joué.
/// Vidée par `ProgressSync`, dans l'ordre joué ; effacée par
/// `AuthService.purgeLocalSession()`.
class PendingQuizRepository {
  PendingQuizRepository(this._prefs);

  /// v2 : quiz servis par `start_quiz` (identifiant seul). Les entrées v1
  /// (questions et réponses choisies par l'app) ne sont plus acceptées par
  /// le serveur : jamais relues, effacées par [clear].
  static const _key = 'pending_quizzes_v2';
  static const _legacyKey = 'pending_quizzes_v1';

  /// Au-delà, les plus anciens sont abandonnés (le serveur refuse de toute
  /// façon les quiz de plus de 6 h et plus de 20 quiz par heure).
  static const maxPending = 30;

  final SharedPreferences _prefs;

  List<QuizSubmission> load() {
    final raw = _prefs.getString(_key);
    if (raw == null) return const [];
    try {
      return [
        for (final e in jsonDecode(raw) as List)
          QuizSubmission.fromJson(e as Map<String, dynamic>),
      ];
    } on Object {
      return const [];
    }
  }

  bool get isEmpty => load().isEmpty;

  Future<void> add(QuizSubmission submission) {
    final list = [...load(), submission];
    return _save(list.length > maxPending
        ? list.sublist(list.length - maxPending)
        : list);
  }

  /// Retire les quiz qui vérifient [test] (autre compte, trop anciens).
  Future<void> removeWhere(bool Function(QuizSubmission) test) async {
    final list = load();
    final kept = [
      for (final s in list)
        if (!test(s)) s
    ];
    if (kept.length != list.length) await _save(kept);
  }

  /// Vide la file (purge locale de la session).
  Future<void> clear() async {
    await _prefs.remove(_key);
    await _prefs.remove(_legacyKey);
  }

  Future<void> remove(String id) => _save([
        for (final s in load())
          if (s.id != id) s
      ]);

  Future<void> _save(List<QuizSubmission> list) => list.isEmpty
      ? _prefs.remove(_key)
      : _prefs.setString(_key, jsonEncode([for (final s in list) s.toJson()]));
}

final pendingQuizRepositoryProvider = Provider(
  (ref) => PendingQuizRepository(ref.watch(sharedPreferencesProvider)),
);
