import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../engagement/progress_controller.dart';

/// Effets sonores (charte § 7 bis, « Retours sensoriels »).
enum Sfx {
  /// Bonne réponse : court « ding » (≈ 300 ms).
  correct('sounds/correct.wav'),

  /// Mauvaise réponse ou temps écoulé : son neutre et discret.
  wrong('sounds/wrong.wav'),

  /// Série validée : « flamme » (≈ 500 ms).
  streak('sounds/streak.wav'),

  /// 10/10 ou montée de niveau : « fanfare » courte (≈ 1 s).
  fanfare('sounds/fanfare.wav');

  const Sfx(this.asset);

  /// Chemin relatif à `assets/` (convention d'audioplayers).
  final String asset;
}

/// Lecture des sons. Remplaçable via [soundServiceProvider] (tests).
abstract class SoundService {
  /// Précharge les sons pour éviter la latence au premier déclenchement.
  Future<void> preload();

  void play(Sfx sfx);

  void dispose();
}

/// Aucun son : valeur par défaut (tests), remplacée dans `main()`.
class SilentSoundService implements SoundService {
  const SilentSoundService();

  @override
  Future<void> preload() async {}

  @override
  void play(Sfx sfx) {}

  @override
  void dispose() {}
}

/// Implémentation réelle avec audioplayers : un lecteur préchargé par son.
class AudioplayersSoundService implements SoundService {
  final _players = <Sfx, AudioPlayer>{};
  Future<void>? _loading;

  /// iOS : session *ambient* (respecte le bouton silencieux, ne coupe pas la
  /// musique). Android : usage « sonification » (flux système, muet en mode
  /// silencieux / vibreur sur la plupart des appareils), sans prise du focus
  /// audio pour ne pas interrompre la musique.
  static final _context = AudioContext(
    iOS: AudioContextIOS(category: AVAudioSessionCategory.ambient),
    android: const AudioContextAndroid(
      contentType: AndroidContentType.sonification,
      usageType: AndroidUsageType.assistanceSonification,
      audioFocus: AndroidAudioFocus.none,
    ),
  );

  @override
  Future<void> preload() => _loading ??= _load();

  Future<void> _load() async {
    try {
      await AudioPlayer.global.setAudioContext(_context);
      for (final sfx in Sfx.values) {
        final player = AudioPlayer(playerId: 'sfx_${sfx.name}');
        await player.setAudioContext(_context);
        await player.setPlayerMode(PlayerMode.lowLatency);
        await player.setReleaseMode(ReleaseMode.stop);
        await player.setSource(AssetSource(sfx.asset));
        _players[sfx] = player;
      }
    } catch (e) {
      // Les sons sont un bonus : une erreur ne doit jamais gêner le jeu.
      debugPrint('Sons indisponibles : $e');
    }
  }

  @override
  void play(Sfx sfx) {
    final player = _players[sfx];
    if (player == null) return;
    unawaited(() async {
      try {
        await player.stop();
        await player.resume();
      } catch (e) {
        debugPrint('Lecture du son ${sfx.name} impossible : $e');
      }
    }());
  }

  @override
  void dispose() {
    for (final player in _players.values) {
      player.dispose();
    }
    _players.clear();
  }
}

/// Service de lecture. Muet par défaut ; `main()` injecte
/// [AudioplayersSoundService] (aucun test ne joue de vrai son).
final soundServiceProvider =
    Provider<SoundService>((ref) => const SilentSoundService());

/// Joue un son seulement si le réglage « Sons » du profil est activé.
class SoundEffects {
  SoundEffects(this._ref);

  final Ref _ref;

  void play(Sfx sfx) {
    if (!_ref.read(progressControllerProvider).soundEnabled) return;
    _ref.read(soundServiceProvider).play(sfx);
  }
}

final soundEffectsProvider = Provider(SoundEffects.new);
