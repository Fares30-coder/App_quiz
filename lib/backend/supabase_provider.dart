import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'backend_config.dart';

/// Client Supabase, ou `null` en mode 100 % local.
/// Remplacé dans `main()` après [initBackend].
final supabaseClientProvider = Provider<SupabaseClient?>((ref) => null);

/// Vrai si le back-end est utilisable (client initialisé).
final backendAvailableProvider = Provider<bool>(
  (ref) => ref.watch(supabaseClientProvider) != null,
);

/// Initialise Supabase si [config] est renseignée.
///
/// Aucun appel réseau bloquant : seule la session locale est lue (la
/// restauration éventuelle se fait en arrière-plan). Retourne `null` sans
/// config ou en cas d'erreur : l'app démarre alors en mode local.
Future<SupabaseClient?> initBackend(BackendConfig config) async {
  if (!config.isConfigured) return null;
  try {
    final supabase = await Supabase.initialize(
      url: config.url.trim(),
      publishableKey: config.publishableKey.trim(),
    );
    return supabase.client;
  } catch (e) {
    if (kDebugMode) debugPrint('Supabase indisponible, mode local : $e');
    return null;
  }
}
