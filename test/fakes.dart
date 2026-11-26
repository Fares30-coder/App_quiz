import 'dart:ui';

import 'package:quizzeo/share/share_content.dart';
import 'package:quizzeo/share/share_service.dart';
import 'package:quizzeo/sound/sound_service.dart';

/// Faux service : enregistre les sons demandés, n'en joue aucun.
class FakeSoundService implements SoundService {
  final played = <Sfx>[];

  @override
  Future<void> preload() async {}

  @override
  void play(Sfx sfx) => played.add(sfx);

  @override
  void dispose() {}
}

/// Faux partage : enregistre le contenu, n'ouvre aucune feuille système.
class FakeShareService implements ShareService {
  final shared = <ShareContent>[];
  final origins = <Rect?>[];

  /// Erreur levée à chaque partage (null = succès).
  Object? error;

  @override
  Future<void> share(ShareContent content, {Rect? origin}) async {
    shared.add(content);
    origins.add(origin);
    if (error != null) throw error!;
  }
}
