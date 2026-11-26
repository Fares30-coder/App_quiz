import 'package:flutter/services.dart';

/// Charge les vraies polices (sinon la police de test, plus large, fausse les mesures).
Future<void> loadFonts() async {
  const fonts = {
    'BricolageGrotesque': ['700', '800'],
    'AtkinsonHyperlegible': ['400', '700'],
  };
  for (final entry in fonts.entries) {
    final loader = FontLoader(entry.key);
    for (final w in entry.value) {
      loader.addFont(rootBundle.load('assets/fonts/${entry.key}-$w.ttf'));
    }
    await loader.load();
  }
}
