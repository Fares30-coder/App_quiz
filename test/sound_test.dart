import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quizzeo/data/progress_repository.dart';
import 'package:quizzeo/engagement/progress_controller.dart';
import 'package:quizzeo/models/player_progress.dart';
import 'package:quizzeo/models/question.dart';
import 'package:quizzeo/quiz/quiz_controller.dart';
import 'package:quizzeo/sound/sound_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fakes.dart';

Question q(String id) => Question(
      id: id,
      category: 'geo',
      question: '?',
      answers: const ['a', 'b', 'c', 'd'],
      correctIndex: 0,
      explanation: '…',
      difficulty: 1,
    );

void main() {
  final now = DateTime(2026, 11, 25, 9);

  group('réglage « Sons »', () {
    test('activés par défaut', () {
      expect(const PlayerProgress().soundEnabled, isTrue);
      // Progression enregistrée avant l'ajout du réglage.
      expect(PlayerProgress.fromJson({'totalXp': 10}).soundEnabled, isTrue);
    });

    test('JSON aller-retour (désactivés conservés)', () {
      const p = PlayerProgress(soundEnabled: false);
      expect(PlayerProgress.fromJson(p.toJson()).soundEnabled, isFalse);
    });
  });

  group('sons du quiz (faux service)', () {
    late ProviderContainer container;
    late FakeSoundService sounds;

    Future<void> setUpContainer({Map<String, Object> prefs = const {}}) async {
      SharedPreferences.setMockInitialValues(prefs);
      final instance = await SharedPreferences.getInstance();
      sounds = FakeSoundService();
      container = ProviderContainer(overrides: [
        sharedPreferencesProvider.overrideWithValue(instance),
        clockProvider.overrideWithValue(() => now),
        soundServiceProvider.overrideWithValue(sounds),
      ]);
      addTearDown(container.dispose);
    }

    QuizController quiz() => container.read(quizControllerProvider.notifier);

    test('par défaut, aucun son réel (service muet)', () {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      expect(c.read(soundServiceProvider), isA<SilentSoundService>());
    });

    test('bonne réponse : ding ; mauvaise : son neutre', () async {
      await setUpContainer();
      quiz().start([q('1'), q('2'), q('3')], mode: QuizMode.mix);
      quiz().answer(0);
      expect(sounds.played, [Sfx.correct]);
      quiz().answer(0); // Déjà répondu : aucun son en plus.
      expect(sounds.played, [Sfx.correct]);
      quiz().next();
      quiz().answer(2);
      expect(sounds.played, [Sfx.correct, Sfx.wrong]);
    });

    test('10/10 : fanfare à la fin du quiz', () async {
      await setUpContainer();
      quiz().start([q('1'), q('2')], mode: QuizMode.mix);
      quiz().answer(0);
      quiz().next();
      quiz().answer(0);
      expect(sounds.played, isNot(contains(Sfx.fanfare)));
      quiz().next();
      expect(sounds.played, [Sfx.correct, Sfx.correct, Sfx.fanfare]);
    });

    test('ni sans-faute ni niveau : pas de fanfare', () async {
      await setUpContainer();
      quiz().start([q('1'), q('2')], mode: QuizMode.mix);
      quiz().answer(1);
      quiz().next();
      quiz().answer(1);
      quiz().next();
      expect(container.read(quizControllerProvider).isFinished, isTrue);
      expect(sounds.played, [Sfx.wrong, Sfx.wrong]);
    });

    test('montée de niveau : fanfare même sans sans-faute', () async {
      await setUpContainer(prefs: {'progress_v1': '{"totalXp":95}'});
      quiz().start([q('1'), q('2')], mode: QuizMode.mix);
      quiz().answer(1);
      quiz().next();
      quiz().answer(1);
      quiz().next();
      expect(sounds.played.last, Sfx.fanfare);
    });

    test('sons désactivés : aucun appel, réglage persisté', () async {
      await setUpContainer();
      container
          .read(progressControllerProvider.notifier)
          .setSoundEnabled(false);
      expect(container.read(progressRepositoryProvider).load().soundEnabled,
          isFalse);
      quiz().start([q('1')], mode: QuizMode.mix);
      quiz().answer(0);
      quiz().next();
      container.read(soundEffectsProvider).play(Sfx.streak);
      expect(sounds.played, isEmpty);

      container.read(progressControllerProvider.notifier).setSoundEnabled(true);
      container.read(soundEffectsProvider).play(Sfx.streak);
      expect(sounds.played, [Sfx.streak]);
    });

    testWidgets('temps écoulé : son neutre', (tester) async {
      await setUpContainer();
      quiz().start([q('1'), q('2')], mode: QuizMode.mix);
      await tester.pump(const Duration(seconds: questionSeconds));
      expect(container.read(quizControllerProvider).timedOut, isTrue);
      expect(sounds.played, [Sfx.wrong]);
      quiz().quit();
    });
  });
}
