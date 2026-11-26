import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/player_progress.dart';

/// Instance chargée dans `main()` puis injectée (override) dans le ProviderScope.
final sharedPreferencesProvider = Provider<SharedPreferences>(
  (ref) => throw UnimplementedError('sharedPreferencesProvider non initialisé'),
);

/// Stockage de la progression sur l'appareil.
///
/// La version locale sert de cache : l'app reste jouable hors ligne. La
/// progression du serveur (table `profiles`) est lue par
/// `SupabaseProgressSource` puis fusionnée par `ProgressSync`
/// (`lib/engagement/progress_sync.dart`).
abstract interface class ProgressRepository {
  PlayerProgress load();
  Future<void> save(PlayerProgress progress);
}

/// Progression locale (shared_preferences).
class LocalProgressRepository implements ProgressRepository {
  LocalProgressRepository(this._prefs);

  static const _key = 'progress_v1';
  final SharedPreferences _prefs;

  @override
  PlayerProgress load() {
    final raw = _prefs.getString(_key);
    if (raw == null) return const PlayerProgress();
    try {
      return PlayerProgress.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } on FormatException {
      return const PlayerProgress();
    }
  }

  @override
  Future<void> save(PlayerProgress progress) =>
      _prefs.setString(_key, jsonEncode(progress.toJson()));
}

final progressRepositoryProvider = Provider<ProgressRepository>(
  (ref) => LocalProgressRepository(ref.watch(sharedPreferencesProvider)),
);
