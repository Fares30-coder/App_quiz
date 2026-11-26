import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/player_progress.dart';

/// Instance chargée dans `main()` puis injectée (override) dans le ProviderScope.
final sharedPreferencesProvider = Provider<SharedPreferences>(
  (ref) => throw UnimplementedError('sharedPreferencesProvider non initialisé'),
);

/// Progression locale (shared_preferences). Sera synchronisée avec le back-end à l'étape 2.
class ProgressRepository {
  ProgressRepository(this._prefs);

  static const _key = 'progress_v1';
  final SharedPreferences _prefs;

  PlayerProgress load() {
    final raw = _prefs.getString(_key);
    if (raw == null) return const PlayerProgress();
    try {
      return PlayerProgress.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } on FormatException {
      return const PlayerProgress();
    }
  }

  Future<void> save(PlayerProgress progress) =>
      _prefs.setString(_key, jsonEncode(progress.toJson()));
}

final progressRepositoryProvider = Provider(
  (ref) => ProgressRepository(ref.watch(sharedPreferencesProvider)),
);
