import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Session Supabase stockée dans le Keychain (iOS) / Keystore (Android),
/// et non dans SharedPreferences (règle sécurité n° 7, `supabase/README.md`).
///
/// Au premier lancement après mise à jour, une session déjà écrite dans
/// SharedPreferences par supabase_flutter est déplacée ici puis effacée.
class SecureSessionStorage extends LocalStorage {
  SecureSessionStorage({required this.key, FlutterSecureStorage? storage})
      : _storage = storage ?? defaultStorage;

  /// Même clé que celle de supabase_flutter (`sb-<ref>-auth-token`), pour
  /// retrouver une ancienne session lors de la migration.
  SecureSessionStorage.forUrl(String url, {FlutterSecureStorage? storage})
      : this(key: sessionKeyFor(url), storage: storage);

  /// `first_unlock` : lisible en arrière-plan après le premier déverrouillage
  /// (rafraîchissement du jeton), jamais synchronisé via iCloud.
  static const defaultStorage = FlutterSecureStorage(
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
  );

  static String sessionKeyFor(String url) =>
      'sb-${Uri.parse(url.trim()).host.split('.').first}-auth-token';

  final String key;
  final FlutterSecureStorage _storage;

  @override
  Future<void> initialize() async {
    try {
      await _migrateFromSharedPreferences();
    } catch (e) {
      // Migration ratée : une nouvelle session anonyme sera créée.
      _log('migration de la session impossible', e);
    }
  }

  Future<void> _migrateFromSharedPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    final legacy = prefs.getString(key);
    if (legacy == null) return;
    if (await _storage.read(key: key) == null) {
      await _storage.write(key: key, value: legacy);
    }
    await prefs.remove(key);
  }

  @override
  Future<bool> hasAccessToken() async => await accessToken() != null;

  @override
  Future<String?> accessToken() async {
    try {
      return await _storage.read(key: key);
    } catch (e) {
      _log('lecture de la session impossible', e);
      return null;
    }
  }

  @override
  Future<void> persistSession(String persistSessionString) =>
      _storage.write(key: key, value: persistSessionString);

  @override
  Future<void> removePersistedSession() => _storage.delete(key: key);
}

/// Jamais le contenu de la session : seulement le type d'erreur.
void _log(String message, Object error) {
  if (kDebugMode) debugPrint('Auth : $message (${error.runtimeType})');
}
