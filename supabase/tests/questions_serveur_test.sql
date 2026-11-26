-- Tests pgTAP des questions du serveur retirées de l'app : questions
-- actives seulement (start_quiz, ensure_daily_challenge), identifiants
-- jamais envoyés, réponse par position.
-- Lancer en local : `supabase start` puis `supabase test db`.
begin;
create extension if not exists pgtap with schema extensions;

select plan(14);

-- Données de test (propriétaire) -------------------------------------------

delete from public.quiz_session_questions;
delete from public.quiz_sessions;
delete from public.daily_challenges;
delete from public.questions;

-- 10 questions actives et 5 inactives (lot hors ligne de l'app), « divers ».
insert into public.questions
  (id, category, difficulty, question, answers, correct_index, explanation, active)
select 'qa-' || lpad(i::text, 2, '0'), 'divers', 1, 'Active ' || i,
       array['bonne', 'b', 'c', 'd'], 0, 'Explication ' || i, true
from generate_series(1, 10) i
union all
select 'qi-' || lpad(i::text, 2, '0'), 'divers', 1, 'Inactive ' || i,
       array['bonne', 'b', 'c', 'd'], 0, 'Explication ' || i, false
from generate_series(1, 5) i;

insert into auth.users (id, aud, role)
values ('00000000-0000-0000-0000-0000000004a1', 'authenticated', 'authenticated');

-- Schéma -----------------------------------------------------------------------

select col_not_null('public', 'questions', 'active', 'questions.active non nulle');
select col_default_is('public', 'questions', 'active', 'true',
  'questions.active vraie par défaut');

select ok(
  to_regprocedure('public.answer_question(uuid, text, integer, integer)') is null,
  'ancienne answer_question(quiz_id, question_id, …) supprimée'
);

select ok(
  has_function_privilege('authenticated',
    'public.answer_question(uuid, integer, integer, integer)', 'execute')
  and not has_function_privilege('anon',
    'public.answer_question(uuid, integer, integer, integer)', 'execute')
  and not has_function_privilege('public',
    'public.answer_question(uuid, integer, integer, integer)', 'execute'),
  'answer_question(quiz_id, position, …) : authenticated seulement'
);

-- Tirage : questions actives seulement ----------------------------------------------

set local role authenticated;
set local "request.jwt.claims" to '{"sub":"00000000-0000-0000-0000-0000000004a1","role":"authenticated"}';

select lives_ok(
  $q$do $d$ begin
    for i in 1 .. 4 loop
      perform public.start_quiz('category', 'divers');
      perform public.start_quiz('mix');
    end loop;
    perform set_config('t.d', public.start_quiz('daily')::text, true);
  end $d$$q$,
  'quiz catégorie, mix et défi commencés'
);

reset role;

select is(
  (select count(*)::int from public.quiz_session_questions sq
     join public.questions q on q.id = sq.question_id
    where not q.active),
  0,
  'aucune question inactive tirée (catégorie, mix, défi)'
);

select is(
  (select count(distinct sq.quiz_id)::int from public.quiz_session_questions sq),
  9,
  '9 quiz de 10 questions actives'
);

-- Identifiants jamais envoyés ---------------------------------------------------------

select ok(
  not (current_setting('t.d')::jsonb -> 'questions' -> 0 ? 'id')
  and position('qa-' in current_setting('t.d')) = 0,
  'start_quiz : aucun identifiant de question renvoyé'
);

set local role authenticated;

do $$ begin
  perform public.answer_question(
    (current_setting('t.d')::jsonb ->> 'quiz_id')::uuid, 1, 0, 500);
  perform set_config('t.n', public.next_question(
    (current_setting('t.d')::jsonb ->> 'quiz_id')::uuid)::text, true);
end $$;

select ok(
  position('qa-' in current_setting('t.n')) = 0
  and (current_setting('t.n')::jsonb -> 'question' ->> 'position') = '2',
  'next_question : aucun identifiant, position seulement'
);

select throws_ok(
  format($$select public.answer_question(%L, 3, 0, 500)$$,
         current_setting('t.d')::jsonb ->> 'quiz_id'),
  '22023', 'question non servie',
  'position pas encore servie : « question non servie »'
);

-- Moins de 10 questions actives dans la catégorie : P0002 -----------------------------

reset role;
update public.questions set active = false where id = 'qa-10';
set local role authenticated;

select throws_ok(
  $$select public.start_quiz('category', 'divers')$$,
  'P0002', null,
  '9 questions actives (5 inactives en plus) : pas assez de questions'
);

-- Défi déjà créé avec une question devenue inactive : remplacée -----------------------

reset role;
update public.questions set active = true where id = 'qa-10';
insert into public.daily_challenges (day, question_ids)
values ((now() at time zone 'Europe/Paris')::date + 1,
        array['qa-01', 'qa-02', 'qa-03', 'qi-01', 'qa-04', 'qa-05', 'qa-06',
              'qa-07', 'qa-08', 'qa-09']);

select is(
  public.ensure_daily_challenge((now() at time zone 'Europe/Paris')::date + 1),
  array['qa-01', 'qa-02', 'qa-03', 'qa-04', 'qa-05', 'qa-06', 'qa-07',
        'qa-08', 'qa-09', 'qa-10'],
  'défi : question inactive remplacée par une active, en fin de liste'
);

select is(
  (select question_ids from public.daily_challenges
    where day = (now() at time zone 'Europe/Paris')::date + 1),
  array['qa-01', 'qa-02', 'qa-03', 'qa-04', 'qa-05', 'qa-06', 'qa-07',
        'qa-08', 'qa-09', 'qa-10'],
  'défi réparé enregistré'
);

-- Nouveau défi : questions actives seulement.
select ok(
  (select bool_and(q.active)
     from unnest(public.ensure_daily_challenge(
            (now() at time zone 'Europe/Paris')::date + 2)) t (id)
     join public.questions q on q.id = t.id),
  'nouveau défi : 10 questions actives'
);

select * from finish();
rollback;
