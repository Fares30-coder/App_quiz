import 'dart:math';

import '../models/question.dart';

/// Défi du jour LOCAL (repli hors ligne / mode 100 % local) : même quiz pour
/// tous, déterminé uniquement par la date. En mode Supabase, le défi du jour
/// est choisi par le serveur (`start_quiz`, table `daily_challenges`).
const dailyChallengeLength = 10;

/// Graine du jour : aaaammjj.
int daySeed(DateTime day) => day.year * 10000 + day.month * 100 + day.day;

/// Générateur pseudo-aléatoire (xorshift 32 bits) au résultat identique
/// sur tous les appareils, contrairement à `Random(seed)` dont l'algorithme
/// n'est pas garanti stable entre versions de Dart.
class SeededRandom implements Random {
  SeededRandom(int seed) {
    _state = (seed * 2654435761) & _mask;
    if (_state == 0) _state = 0x9E3779B9;
    for (var i = 0; i < 8; i++) {
      _next32();
    }
  }

  static const _mask = 0xFFFFFFFF;
  late int _state;

  int _next32() {
    var x = _state;
    x ^= (x << 13) & _mask;
    x ^= x >> 17;
    x ^= (x << 5) & _mask;
    return _state = x & _mask;
  }

  @override
  int nextInt(int max) {
    if (max <= 0) throw RangeError.range(max, 1, null, 'max');
    return _next32() % max;
  }

  @override
  double nextDouble() => _next32() / 4294967296.0;

  @override
  bool nextBool() => _next32() & 1 == 1;
}

/// Sélectionne les questions du défi de [day] (ordre des questions et
/// des réponses compris). Indépendant de l'ordre de [all].
List<Question> pickDailyChallenge(
  List<Question> all,
  DateTime day, {
  int count = dailyChallengeLength,
}) {
  final random = SeededRandom(daySeed(day));
  final pool = [...all]
    ..sort((a, b) => a.id.compareTo(b.id))
    ..shuffle(random);
  return [for (final q in pool.take(count)) q.shuffled(random)];
}
