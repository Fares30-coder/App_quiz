import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:url_launcher/url_launcher.dart';

/// Pages légales hébergées (T25), exigées par Apple 5.1.1(i) et Google Play.
abstract final class LegalLinks {
  static final privacy =
      Uri.parse('https://legal.quizzeo.workers.dev/confidentialite/');
  static final dataDeletion =
      Uri.parse('https://legal.quizzeo.workers.dev/suppression/');
  static final legalNotice =
      Uri.parse('https://legal.quizzeo.workers.dev/mentions-legales/');
}

/// Ouvre une URL ; `false` si impossible. Remplaçable dans les tests.
typedef UrlOpener = Future<bool> Function(Uri url);

/// Navigateur intégré (SFSafariViewController / Custom Tabs).
final urlOpenerProvider = Provider<UrlOpener>(
  (ref) => (url) => launchUrl(url, mode: LaunchMode.inAppBrowserView),
);

/// Ouvre [url] ; en cas d'échec (pas de navigateur, exception), SnackBar.
Future<void> openLegalLink(BuildContext context, WidgetRef ref, Uri url) async {
  final messenger = ScaffoldMessenger.of(context);
  bool opened;
  try {
    opened = await ref.read(urlOpenerProvider)(url);
  } catch (_) {
    opened = false;
  }
  if (opened) return;
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      content: Text('Impossible d\'ouvrir la page. Adresse : '
          '${url.host}${url.path}'),
    ));
}
