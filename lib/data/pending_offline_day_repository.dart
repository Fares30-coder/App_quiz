import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/offline_day.dart';
import 'progress_repository.dart';

/// File locale des journées validées par un quiz hors ligne, pas encore
/// envoyées au serveur (`validate_offline_day`). Même logique que
/// `PendingQuizRepository` : compte et horodatage par entrée, vidée par
/// `ProgressSync` dans l'ordre joué, effacée par
/// `AuthService.purgeLocalSession()`.
class PendingOfflineDayRepository {
  PendingOfflineDayRepository(this._prefs);

  static const _key = 'pending_offline_days_v1';

  /// Au plus une journée validée par jour, et le serveur refuse au-delà de
  /// 6 h : quelques entrées suffisent.
  static const maxPending = 5;

  final SharedPreferences _prefs;

  List<OfflineDay> load() {
    final raw = _prefs.getString(_key);
    if (raw == null) return const [];
    try {
      return [
        for (final e in jsonDecode(raw) as List)
          OfflineDay.fromJson(e as Map<String, dynamic>),
      ];
    } on Object {
      return const [];
    }
  }

  bool get isEmpty => load().isEmpty;

  Future<void> add(OfflineDay day) {
    final list = [...load(), day];
    return _save(list.length > maxPending
        ? list.sublist(list.length - maxPending)
        : list);
  }

  /// Retire les journées qui vérifient [test] (autre compte, trop anciennes).
  Future<void> removeWhere(bool Function(OfflineDay) test) async {
    final list = load();
    final kept = [
      for (final d in list)
        if (!test(d)) d
    ];
    if (kept.length != list.length) await _save(kept);
  }

  Future<void> remove(OfflineDay day) => removeWhere((d) => d == day);

  /// Vide la file (purge locale de la session).
  Future<void> clear() => _prefs.remove(_key);

  Future<void> _save(List<OfflineDay> list) => list.isEmpty
      ? _prefs.remove(_key)
      : _prefs.setString(_key, jsonEncode([for (final d in list) d.toJson()]));
}

final pendingOfflineDayRepositoryProvider = Provider(
  (ref) => PendingOfflineDayRepository(ref.watch(sharedPreferencesProvider)),
);
