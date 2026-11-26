/// Configuration Supabase lue à la compilation (`--dart-define-from-file`).
///
/// Sans valeurs (tests, build sans `config/dev.json`), l'app tourne en mode
/// 100 % local.
class BackendConfig {
  const BackendConfig({required this.url, required this.publishableKey});

  /// Valeurs passées par `--dart-define-from-file=config/dev.json`.
  const BackendConfig.fromEnvironment()
      : url = const String.fromEnvironment('SUPABASE_URL'),
        publishableKey = const String.fromEnvironment(
          'SUPABASE_PUBLISHABLE_KEY',
        );

  final String url;

  /// Clé publique `sb_publishable_...` (ou ancienne clé `anon`).
  /// Jamais de clé secrète (`sb_secret_...` / `service_role`) dans l'app.
  final String publishableKey;

  /// Vrai si l'URL et la clé sont présentes et plausibles.
  bool get isConfigured {
    final uri = Uri.tryParse(url.trim());
    final key = publishableKey.trim();
    return uri != null &&
        uri.scheme == 'https' &&
        uri.host.isNotEmpty &&
        key.isNotEmpty &&
        !key.startsWith('sb_secret_');
  }
}
