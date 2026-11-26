import 'dart:io';

import 'package:flutter/painting.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'share_content.dart';
import 'share_image.dart';

/// Partage d'une image de résultat. Remplaçable via [shareServiceProvider]
/// (faux service dans les tests).
abstract class ShareService {
  /// Génère l'image de [content] et ouvre la feuille de partage du système.
  /// [origin] : zone du bouton (ancre de la popover sur iPad).
  Future<void> share(ShareContent content, {Rect? origin});
}

/// Implémentation réelle : rendu hors écran -> PNG temporaire -> share_plus.
class SystemShareService implements ShareService {
  const SystemShareService();

  @override
  Future<void> share(ShareContent content, {Rect? origin}) async {
    final png = await renderShareImage(content);
    final dir = Directory('${(await getTemporaryDirectory()).path}/partage');
    await dir.create(recursive: true);
    final file = File('${dir.path}/${content.fileName}');
    await file.writeAsBytes(png, flush: true);
    await SharePlus.instance.share(ShareParams(
      files: [XFile(file.path, mimeType: 'image/png')],
      text: content.message,
      sharePositionOrigin: origin,
    ));
  }
}

final shareServiceProvider =
    Provider<ShareService>((ref) => const SystemShareService());
