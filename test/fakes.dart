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
