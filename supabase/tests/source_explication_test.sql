-- Tests pgTAP de la source de l'explication (*_source_explication.sql) :
-- jamais envoyée avant la réponse (start_quiz, next_question, reprise du
-- défi), renvoyée avec la correction (réponse, temps écoulé, reprise),
-- contrainte de longueur, aucun accès client à la colonne.
-- Lancer en local : `supabase start` puis `supabase test db`.
begin;
create extension if not exists pgtap with schema extensions;

select plan(21);

-- Données de test (propriétaire) -------------------------------------------

delete from public.question_reports;
delete from public.quiz_session_questions;
delete from public.quiz_sessions;
delete from public.daily_challenges;
delete from public.questions;

-- 10 questions actives, chacune avec une source repérable (« SRC-NN »).
insert into public.questions
  (id, category, difficulty, question, answers, correct_index, explanation,
   source)
select 'qs-' || lpad(i::text, 2, '0'), 'divers', 1, 'Question ' || i,
       array['bonne', 'b', 'c', 'd'], 0, 'Explication ' || i,
       'SRC-' || lpad(i::text, 2, '0')
from generate_series(1, 10) i;

insert into auth.users (id, aud, role)
values ('00000000-0000-0000-0000-0000000005a1', 'authenticated', 'authenticated');

-- Source attendue pour la question `p` du quiz `t.d` (propriétaire).
create function pg_temp.expected_source(p integer) returns text
language sql as $$
  select q.source
    from public.quiz_session_questions sq
    join public.questions q on q.id = sq.question_id
   where sq.quiz_id = (current_setting('t.d')::jsonb ->> 'quiz_id')::uuid
     and sq.position = p;
$$;

-- Schéma et droits -----------------------------------------------------------------

select has_column('public', 'questions', 'source', 'questions.source existe');
select col_is_null('public', 'questions', 'source', 'questions.source nullable');

select ok(
  not has_column_privilege('anon', 'public.questions', 'source', 'select')
  and not has_column_privilege('authenticated', 'public.questions', 'source',
                               'select'),
  'questions.source illisible par anon et authenticated'
);

select throws_ok(
  $$update public.questions set source = '' where id = 'qs-01'$$,
  '23514', null,
  'source vide refusée'
);

select throws_ok(
  $$update public.questions set source = repeat('x', 61) where id = 'qs-01'$$,
  '23514', null,
  'source de plus de 60 caractères refusée'
);

select lives_ok(
  $$update public.questions set source = repeat('x', 60) where id = 'qs-01';
    update public.questions set source = null where id = 'qs-01';
    update public.questions set source = 'SRC-01' where id = 'qs-01'$$,
  'source de 60 caractères ou nulle acceptée'
);

-- Avant la réponse : aucune source ------------------------------------------------

set local role authenticated;
set local "request.jwt.claims" to '{"sub":"00000000-0000-0000-0000-0000000005a1","role":"authenticated"}';

do $$ begin
  perform set_config('t.d', public.start_quiz('daily')::text, true);
end $$;

select ok(
  position('SRC-' in current_setting('t.d')) = 0
  and position('"source"' in current_setting('t.d')) = 0,
  'start_quiz : aucune source avant la réponse'
);

do $$ begin
  perform set_config('t.a1', public.answer_question(
    (current_setting('t.d')::jsonb ->> 'quiz_id')::uuid, 1, 0, 500)::text, true);
  perform set_config('t.n', public.next_question(
    (current_setting('t.d')::jsonb ->> 'quiz_id')::uuid)::text, true);
  -- Réessai (réponse perdue) : même question, toujours sans source.
  perform set_config('t.n2', public.next_question(
    (current_setting('t.d')::jsonb ->> 'quiz_id')::uuid)::text, true);
end $$;

select ok(
  (current_setting('t.n')::jsonb -> 'question' ->> 'position') = '2'
  and position('SRC-' in current_setting('t.n')) = 0
  and position('"source"' in current_setting('t.n')) = 0,
  'next_question : aucune source avant la réponse'
);

select ok(
  position('SRC-' in current_setting('t.n2')) = 0,
  'next_question rappelée : toujours aucune source'
);

-- Reprise du défi avant la réponse à la question 2.
do $$ begin
  perform set_config('t.r', public.start_quiz('daily')::text, true);
end $$;

select ok(
  (current_setting('t.r')::jsonb ->> 'resumed')::boolean
  and jsonb_array_length(current_setting('t.r')::jsonb -> 'questions') = 2
  and position('SRC-' in (current_setting('t.r')::jsonb -> 'questions' -> 1)::text) = 0
  and position('"source"' in (current_setting('t.r')::jsonb -> 'questions' -> 1)::text) = 0,
  'reprise : question en cours sans source'
);

reset role;

-- Après la réponse : source dans la correction ---------------------------------------

select ok(
  pg_temp.expected_source(1) like 'SRC-%'
  and current_setting('t.a1')::jsonb ->> 'source' = pg_temp.expected_source(1),
  'answer_question : source de la question répondue'
);

select is(
  current_setting('t.r')::jsonb -> 'questions' -> 0 -> 'answer' ->> 'source',
  pg_temp.expected_source(1),
  'reprise : source dans la correction de la question déjà répondue'
);

select ok(
  not (current_setting('t.r')::jsonb -> 'questions' -> 0 ? 'source'),
  'reprise : source seulement dans l''objet answer'
);

-- Temps écoulé : question 2 servie il y a 40 s.
update public.quiz_session_questions
   set served_at = now() - interval '40 seconds'
 where quiz_id = (current_setting('t.d')::jsonb ->> 'quiz_id')::uuid
   and position = 2;

set local role authenticated;
set local "request.jwt.claims" to '{"sub":"00000000-0000-0000-0000-0000000005a1","role":"authenticated"}';

do $$ begin
  perform set_config('t.a2', public.answer_question(
    (current_setting('t.d')::jsonb ->> 'quiz_id')::uuid, 2, 0, 500)::text, true);
  -- Réessai de la réponse : même correction, même source.
  perform set_config('t.a2b', public.answer_question(
    (current_setting('t.d')::jsonb ->> 'quiz_id')::uuid, 2, 1, 500)::text, true);
  perform set_config('t.r2', public.start_quiz('daily')::text, true);
end $$;

reset role;

select ok(
  (current_setting('t.a2')::jsonb ->> 'timed_out')::boolean,
  'question 2 : temps écoulé'
);

select is(
  current_setting('t.a2')::jsonb ->> 'source',
  pg_temp.expected_source(2),
  'temps écoulé : source dans la correction'
);

select is(
  current_setting('t.a2b')::jsonb ->> 'source',
  pg_temp.expected_source(2),
  'réessai de answer_question : même source'
);

select is(
  array(select e -> 'answer' ->> 'source'
          from jsonb_array_elements(current_setting('t.r2')::jsonb -> 'questions') e
         where e -> 'answer' <> 'null'::jsonb),
  array[pg_temp.expected_source(1), pg_temp.expected_source(2)],
  'reprise : sources des 2 questions répondues'
);

select ok(
  jsonb_array_length(current_setting('t.r2')::jsonb -> 'questions') = 3
  and position('SRC-' in (current_setting('t.r2')::jsonb -> 'questions' -> 2)::text) = 0,
  'reprise : question 3 en cours sans source'
);

-- Question sans source : `source` nulle dans la correction ---------------------------

update public.questions set source = null;

set local role authenticated;
set local "request.jwt.claims" to '{"sub":"00000000-0000-0000-0000-0000000005a1","role":"authenticated"}';

do $$ begin
  perform set_config('t.m', public.start_quiz('mix')::text, true);
  perform set_config('t.ma', public.answer_question(
    (current_setting('t.m')::jsonb ->> 'quiz_id')::uuid, 1, 0, 500)::text, true);
  perform set_config('t.mn', public.next_question(
    (current_setting('t.m')::jsonb ->> 'quiz_id')::uuid)::text, true);
end $$;

reset role;

select ok(
  current_setting('t.ma')::jsonb ? 'source'
  and current_setting('t.ma')::jsonb -> 'source' = 'null'::jsonb,
  'question sans source : source nulle dans la correction'
);

select ok(
  position('"source"' in current_setting('t.m')) = 0
  and position('"source"' in current_setting('t.mn')) = 0,
  'question sans source : aucune clé source avant la réponse'
);

select ok(
  has_function_privilege('authenticated',
    'public.answer_question(uuid, integer, integer, integer)', 'execute')
  and not has_function_privilege('anon',
    'public.answer_question(uuid, integer, integer, integer)', 'execute')
  and not has_function_privilege('authenticated',
    'public.served_question_json(uuid, integer)', 'execute'),
  'droits inchangés : answer_question pour authenticated, served_question_json interne'
);

select * from finish();
rollback;
