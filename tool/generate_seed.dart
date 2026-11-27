// Génère supabase/seed.sql à partir de supabase/questions/questions.json
// (questions servies par le serveur, jamais embarquées dans l'app).
//
// Usage (depuis la racine du dépôt) : dart run tool/generate_seed.dart
//
// Le fichier produit insère ou met à jour les questions (upsert sur `id`) ;
// `updated_at` ne change que si la question a réellement changé. Aucune
// question n'est supprimée : celles absentes du fichier (dont le lot hors
// ligne de assets/questions.json) sont désactivées (`active = false`), donc
// plus jamais servies. `source` (libellé court, sans URL) est optionnelle :
// `null` si absente ; une source invalide fait échouer la génération (voir
// [validateSource], mêmes règles que la contrainte SQL). Le fichier source contient les bonnes réponses : il
// ne doit jamais être déclaré dans pubspec.yaml ni copié dans assets/.
import 'dart:convert';
import 'dart:io';

const questionsPath = 'supabase/questions/questions.json';

/// Lot hors ligne embarqué dans l'app (jamais servi par le serveur).
const offlineQuestionsPath = 'assets/questions.json';
const seedPath = 'supabase/seed.sql';

void main() {
  final questions = jsonDecode(File(questionsPath).readAsStringSync()) as List;
  File(seedPath).writeAsStringSync(
    seedSql([for (final q in questions) q as Map<String, dynamic>]),
  );
  stdout.writeln('${questions.length} questions écrites dans $seedPath');
}

/// Contenu de `supabase/seed.sql` pour [questions] (format de
/// supabase/questions/questions.json).
String seedSql(List<Map<String, dynamic>> questions) {
  final rows = [
    for (final q in questions)
      '  (${[
        _text(q['id'] as String),
        _text(q['category'] as String),
        '${q['difficulty'] as int}',
        _text(q['question'] as String),
        'array[${[
          for (final a in q['answers'] as List) _text(a as String)
        ].join(', ')}]',
        '${q['correctIndex'] as int}',
        _text(q['explanation'] as String),
        _textOrNull(validateSource(q['id'] as String, q['source'])),
      ].join(', ')})',
  ];
  return '''
-- Fichier généré par tool/generate_seed.dart depuis $questionsPath.
-- Ne pas modifier à la main : relancer `dart run tool/generate_seed.dart`.
-- Appliqué par `supabase db reset` (local) ; en distant, après chaque
-- génération : `supabase db query --remote -f supabase/seed.sql`.

insert into public.questions
  (id, category, difficulty, question, answers, correct_index, explanation,
   source)
values
${rows.join(',\n')}
on conflict (id) do update
set category = excluded.category,
    difficulty = excluded.difficulty,
    question = excluded.question,
    answers = excluded.answers,
    correct_index = excluded.correct_index,
    explanation = excluded.explanation,
    source = excluded.source,
    active = true,
    updated_at = now()
where (questions.category, questions.difficulty, questions.question,
       questions.answers, questions.correct_index, questions.explanation,
       questions.source, questions.active)
  is distinct from
      (excluded.category, excluded.difficulty, excluded.question,
       excluded.answers, excluded.correct_index, excluded.explanation,
       excluded.source, true);

-- Questions absentes du fichier (lot hors ligne de l'app, questions
-- retirées) : désactivées, jamais supprimées (référencées par les sessions).
update public.questions
   set active = false, updated_at = now()
 where active
   and id <> all (array[${[
    for (final q in questions) _text(q['id'] as String)
  ].join(', ')}]);
''';
}

/// Longueur maximale de `source` (contrainte `questions_source_check`).
const maxSourceLength = 60;

/// Vérifie la `source` de la question [id] et la renvoie (`null` si
/// absente). Lève une [FormatException] (id + valeur) si ce n'est pas une
/// chaîne, si elle est vide, a un espace au bord, dépasse
/// [maxSourceLength] caractères, contient `://` ou un caractère de contrôle.
String? validateSource(String id, Object? source) {
  if (source == null) return null;
  String? problem;
  if (source is! String) {
    problem = 'doit être une chaîne';
  } else if (source.isEmpty) {
    problem = 'vide';
  } else if (source != source.trim()) {
    problem = 'espace au début ou à la fin';
  } else if (source.runes.length > maxSourceLength) {
    problem = 'plus de $maxSourceLength caractères';
  } else if (source.contains('://')) {
    problem = 'URL interdite';
  } else if (RegExp(r'[\x00-\x1F\x7F]').hasMatch(source)) {
    problem = 'caractère de contrôle';
  }
  if (problem != null) {
    throw FormatException('Source invalide pour la question $id ($problem) : '
        '${jsonEncode(source)}');
  }
  return source as String;
}

/// Littéral SQL : apostrophes doublées.
String _text(String value) => "'${value.replaceAll("'", "''")}'";

/// Littéral SQL, `null` si [value] est absente.
String _textOrNull(String? value) => value == null ? 'null' : _text(value);
