import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:quizzeo/backend/auth_service.dart';
import 'package:quizzeo/backend/backend_config.dart';
import 'package:quizzeo/backend/secure_session_storage.dart';
import 'package:quizzeo/backend/supabase_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const _url = 'https://exemple.supabase.co';
const _key = 'sb-exemple-auth-token';

/// Jeton factice (pas de signature vérifiée côté client), expire en 2100.
final _jwt = [
  base64Url.encode(utf8.encode('{"alg":"HS256","typ":"JWT"}')),
  base64Url.encode(utf8.encode('{"exp":4102444800,"sub":"u"}')),
  'sig',
].join('.').replaceAll('=', '');

Map<String, dynamic> _session(String userId) => {
      'access_token': _jwt,
      'expires_in': 3600,
      'refresh_token': 'refresh',
      'token_type': 'bearer',
      'user': {
        'id': userId,
        'aud': 'authenticated',
        'app_metadata': <String, dynamic>{},
        'user_metadata': <String, dynamic>{},
        'created_at': '2026-11-26T00:00:00Z',
        'is_anonymous': true,
      },
    };

/// Faux serveur GoTrue : compte les appels, répond ou simule une panne.
class _FakeServer {
  final requests = <http.Request>[];
  bool offline = false;

  late final client = MockClient((request) async {
    requests.add(request);
    if (offline) throw const SocketException('hors ligne');
    if (request.url.path.endsWith('/signup')) {
      return http.Response(jsonEncode(_session('anonyme-1')), 200);
    }
    return http.Response('{}', 204);
  });

  int get signUps =>
      requests.where((r) => r.url.path.endsWith('/signup')).length;
}

/// Stockage sécurisé en panne (Keychain verrouillé, Keystore défaillant).
class _BrokenStorage extends FlutterSecureStorage {
  const _BrokenStorage();

  @override
  Future<String?> read({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) =>
      throw Exception('stockage sécurisé indisponible');
}

GoTrueClient _auth(_FakeServer server) => GoTrueClient(
      url: '$_url/auth/v1',
      headers: {'apikey': 'sb_publishable_test'},
      httpClient: server.client,
      autoRefreshToken: false,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AuthService', () {
    test('session existante : réutilisée, aucun sign-in', () async {
      final server = _FakeServer();
      final auth = _auth(server);
      await auth.setInitialSession(jsonEncode(_session('existant')));

      await AuthService(auth).ensureSignedIn();

      expect(server.signUps, 0);
      expect(auth.currentUser?.id, 'existant');
    });

    test('pas de session : connexion anonyme', () async {
      final server = _FakeServer();
      final auth = _auth(server);
      final service = AuthService(auth);

      await Future.wait([service.ensureSignedIn(), service.ensureSignedIn()]);

      expect(server.signUps, 1, reason: 'appels simultanés regroupés');
      expect(service.userId, 'anonyme-1');
      // Session obtenue : plus aucun appel ensuite.
      await service.ensureSignedIn();
      expect(server.signUps, 1);
    });

    test('hors ligne : pas de crash, mode local, nouvel essai plus tard',
        () async {
      final server = _FakeServer()..offline = true;
      final auth = _auth(server);
      final service = AuthService(auth, retryDelay: const Duration(hours: 1));

      await service.ensureSignedIn();
      expect(service.userId, isNull);
      expect(server.signUps, 1);

      // Retour au premier plan juste après : pas de nouvel appel (délai).
      await service.ensureSignedIn();
      expect(server.signUps, 1);
    });

    test('hors ligne puis réseau revenu : connexion au nouvel essai', () async {
      final server = _FakeServer()..offline = true;
      final service = AuthService(_auth(server), retryDelay: Duration.zero);

      await service.ensureSignedIn();
      expect(service.userId, isNull);

      server.offline = false;
      await service.ensureSignedIn();
      expect(service.userId, 'anonyme-1');
    });

    test('purge locale : déconnexion et stockage effacé, même hors ligne',
        () async {
      FlutterSecureStorage.setMockInitialValues({_key: 'session'});
      final storage = SecureSessionStorage(key: _key);
      final server = _FakeServer();
      final auth = _auth(server);
      await auth.setInitialSession(jsonEncode(_session('existant')));
      server.offline = true;

      await AuthService(auth, sessionStorage: storage).purgeLocalSession();

      expect(auth.currentSession, isNull);
      expect(await storage.hasAccessToken(), isFalse);
    });
  });

  group('SecureSessionStorage', () {
    test('clé identique à celle de supabase_flutter', () {
      expect(SecureSessionStorage.sessionKeyFor(_url), _key);
    });

    test('lit, écrit et efface la session', () async {
      FlutterSecureStorage.setMockInitialValues({});
      final storage = SecureSessionStorage(key: _key);
      expect(await storage.hasAccessToken(), isFalse);

      await storage.persistSession('session');
      expect(await storage.accessToken(), 'session');

      await storage.removePersistedSession();
      expect(await storage.hasAccessToken(), isFalse);
    });

    test('migration : session SharedPreferences déplacée puis effacée',
        () async {
      SharedPreferences.setMockInitialValues({_key: 'ancienne', 'xp': 120});
      FlutterSecureStorage.setMockInitialValues({});
      final storage = SecureSessionStorage(key: _key);

      await storage.initialize();

      expect(await storage.accessToken(), 'ancienne');
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.containsKey(_key), isFalse);
      expect(prefs.getInt('xp'), 120, reason: 'progression intacte');
    });

    test('lecture en erreur : l’erreur remonte, pas de session vide', () async {
      final storage =
          SecureSessionStorage(key: _key, storage: const _BrokenStorage());

      await expectLater(storage.accessToken(), throwsA(isA<Exception>()));
      await expectLater(storage.hasAccessToken(), throwsA(isA<Exception>()));
    });

    test('lecture en erreur : mode local (aucun client, donc aucun /signup)',
        () async {
      SharedPreferences.setMockInitialValues({});
      final client = await initBackend(
        const BackendConfig(url: _url, publishableKey: 'sb_publishable_test'),
        sessionStorage:
            SecureSessionStorage(key: _key, storage: const _BrokenStorage()),
      );

      expect(client, isNull);
    });

    test('migration : session sécurisée déjà présente conservée', () async {
      SharedPreferences.setMockInitialValues({_key: 'ancienne'});
      FlutterSecureStorage.setMockInitialValues({_key: 'actuelle'});
      final storage = SecureSessionStorage(key: _key);

      await storage.initialize();

      expect(await storage.accessToken(), 'actuelle');
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.containsKey(_key), isFalse);
    });
  });

  group('providers', () {
    test('mode local : aucun service, aucun utilisateur', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      expect(container.read(authServiceProvider), isNull);
      expect(await container.read(authUserProvider.future), isNull);
      expect(container.read(authUserIdProvider), isNull);
    });

    test('client configuré : connexion lancée, id exposé', () async {
      final server = _FakeServer();
      final client = SupabaseClient(
        _url,
        'sb_publishable_test',
        httpClient: server.client,
        authOptions: const AuthClientOptions(autoRefreshToken: false),
      );
      addTearDown(client.dispose);
      final container = ProviderContainer(
        overrides: [supabaseClientProvider.overrideWithValue(client)],
      );
      addTearDown(container.dispose);
      container.listen(authUserIdProvider, (_, __) {});

      final service = container.read(authServiceProvider)!;
      await service.ensureSignedIn();
      await pumpEventQueue();

      expect(server.signUps, 1);
      expect(container.read(authUserIdProvider), 'anonyme-1');
    });
  });
}
