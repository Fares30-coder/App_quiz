// Génère supabase/seed.sql à partir de assets/questions.json.
//
// Usage (depuis la racine du dépôt) : dart run tool/generate_seed.dart
//
// Le fichier produit insère ou met à jour les questions (upsert sur `id`) ;
// `updated_at` ne change que si la question a réellement changé. Aucune
// question n'est supprimée. Aucun secret : contenu public de l'app.
import 'dart:convert';
import 'dart:io';

const questionsPath = 'assets/questions.json';
const seedPath = 'supabase/seed.sql';

void main() {
  final questions = jsonDecode(File(questionsPath).readAsStringSync()) as List;
  File(seedPath).writeAsStringSync(
    seedSql([for (final q in questions) q as Map<String, dynamic>]),
  );
  stdout.writeln('${questions.length} questions écrites dans $seedPath');
}

/// Contenu de `supabase/seed.sql` pour [questions] (format de assets/questions.json).
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
      ].join(', ')})',
  ];
  return '''
-- Fichier généré par tool/generate_seed.dart depuis $questionsPath.
-- Ne pas modifier à la main : relancer `dart run tool/generate_seed.dart`.
-- Appliqué par `supabase db reset` (local) ou `supabase db push --include-seed`.

insert into public.questions
  (id, category, difficulty, question, answers, correct_index, explanation)
values
${rows.join(',\n')}
on conflict (id) do update
set category = excluded.category,
    difficulty = excluded.difficulty,
    question = excluded.question,
    answers = excluded.answers,
    correct_index = excluded.correct_index,
    explanation = excluded.explanation,
    updated_at = now()
where (questions.category, questions.difficulty, questions.question,
       questions.answers, questions.correct_index, questions.explanation)
  is distinct from
      (excluded.category, excluded.difficulty, excluded.question,
       excluded.answers, excluded.correct_index, excluded.explanation);
''';
}

/// Littéral SQL : apostrophes doublées.
String _text(String value) => "'${value.replaceAll("'", "''")}'";
