import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quizzeo/backend/backend_config.dart';
import 'package:quizzeo/backend/supabase_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  group('BackendConfig', () {
    test('sans --dart-define : non configuré (mode local)', () {
      const config = BackendConfig.fromEnvironment();
      expect(config.url, isEmpty);
      expect(config.publishableKey, isEmpty);
      expect(config.isConfigured, isFalse);
    });

    test('URL https + clé publishable : configuré', () {
      const config = BackendConfig(
        url: 'https://abc.supabase.co',
        publishableKey: 'sb_publishable_xyz',
      );
      expect(config.isConfigured, isTrue);
    });

    test('valeurs manquantes ou invalides : non configuré', () {
      const cases = [
        BackendConfig(url: '', publishableKey: 'sb_publishable_xyz'),
        BackendConfig(url: 'https://abc.supabase.co', publishableKey: ' '),
        BackendConfig(url: 'abc.supabase.co', publishableKey: 'k'),
        BackendConfig(url: 'http://abc.supabase.co', publishableKey: 'k'),
      ];
      for (final config in cases) {
        expect(config.isConfigured, isFalse, reason: config.url);
      }
    });

    test('clé secrète refusée', () {
      const config = BackendConfig(
        url: 'https://abc.supabase.co',
        publishableKey: 'sb_secret_xyz',
      );
      expect(config.isConfigured, isFalse);
    });
  });

  group('initBackend', () {
    test('sans config : null, sans initialiser Supabase', () async {
      final client = await initBackend(
        const BackendConfig(url: '', publishableKey: ''),
      );
      expect(client, isNull);
    });

    test('avec config : client créé sans appel réseau', () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      SharedPreferences.setMockInitialValues({});
      final client = await initBackend(
        const BackendConfig(
          url: 'https://exemple.supabase.co',
          publishableKey: 'sb_publishable_test',
        ),
      );
      expect(client, isA<SupabaseClient>());
      expect(client!.rest.url, 'https://exemple.supabase.co/rest/v1');
      await Supabase.instance.dispose();
    });
  });

  group('providers', () {
    test('par défaut : pas de client, back-end indisponible', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      expect(container.read(supabaseClientProvider), isNull);
      expect(container.read(backendAvailableProvider), isFalse);
    });

    test('client fourni : back-end disponible', () {
      final client = SupabaseClient('https://exemple.supabase.co', 'k');
      addTearDown(client.dispose);
      final container = ProviderContainer(
        overrides: [supabaseClientProvider.overrideWithValue(client)],
      );
      addTearDown(container.dispose);
      expect(container.read(backendAvailableProvider), isTrue);
    });
  });
}
