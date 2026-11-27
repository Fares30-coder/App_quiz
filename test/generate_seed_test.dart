import 'package:flutter_test/flutter_test.dart';

import '../tool/generate_seed.dart';

Map<String, dynamic> _question({Object? source}) => {
      'id': 'div-1',
      'category': 'divers',
      'difficulty': 1,
      'question': 'Question ?',
      'answers': ['a', 'b', 'c', 'd'],
      'correctIndex': 0,
      'explanation': 'Explication',
      if (source != null) 'source': source,
    };

void main() {
  group('validateSource', () {
    test('absente : null', () {
      expect(validateSource('div-1', null), isNull);
    });

    test('libellés valides acceptés', () {
      for (final s in ['Larousse', 'L\'Équipe', 'Insee', 'x' * 60, 'é' * 60]) {
        expect(validateSource('div-1', s), s);
      }
    });

    test('sources invalides refusées avec id et valeur', () {
      final invalid = <Object>[
        42,
        ['Larousse'],
        '',
        ' Larousse',
        'Larousse ',
        'x' * 61,
        'https://fr.wikipedia.org',
        'Larousse\nInsee',
        'Lar\tousse',
        'Larousse\x7F',
        'Lar\x00ousse',
      ];
      for (final s in invalid) {
        expect(
          () => validateSource('geo-7', s),
          throwsA(isA<FormatException>()
              .having((e) => e.message, 'message', contains('geo-7'))),
          reason: 'source : $s',
        );
      }
    });

    test('message avec la valeur fautive', () {
      expect(
        () => validateSource('geo-7', 'voir https://x.fr'),
        throwsA(isA<FormatException>().having(
            (e) => e.message, 'message', contains('"voir https://x.fr"'))),
      );
    });
  });

  group('seedSql', () {
    test('échoue sur une source invalide', () {
      expect(() => seedSql([_question(source: 'http://x.fr')]),
          throwsFormatException);
    });

    test('accepte une source valide ou absente', () {
      final sql = seedSql([
        _question(source: 'Larousse'),
        {..._question(), 'id': 'div-2'},
      ]);
      expect(sql, contains("'Explication', 'Larousse')"));
      expect(sql, contains("'Explication', null)"));
    });
  });
}
