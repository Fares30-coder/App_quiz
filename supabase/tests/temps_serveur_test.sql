-- Tests pgTAP du temps de réponse mesuré par le serveur : questions servies
-- une à une (start_quiz, next_question), temps officiel, temps écoulé forcé,
-- bonus rapidité jugé sur le temps serveur, reprise du défi du jour.
-- Lancer en local : `supabase start` puis `supabase test db`.
--
-- Dans une transaction, now() ne bouge pas : le temps serveur d'une
-- question se simule en reculant son `served_at` (propriétaire).
begin;
create extension if not exists pgtap with schema extensions;

select plan(37);

-- Données de test (propriétaire) -------------------------------------------

delete from public.quiz_session_questions;
delete from public.quiz_sessions;
delete from public.daily_challenges;
delete from public.questions;

-- 10 questions, bonne réponse « bonne ».
insert into public.questions
  (id, category, difficulty, question, answers, correct_index, explanation)
select 'tt-' || lpad(i::text, 2, '0'), 'divers', 1, 'Question ' || i,
       array['bonne', 'b', 'c', 'd'], 0, 'Explication ' || i
from generate_series(1, 10) i;

-- Position de « bonne » dans une question servie.
create schema tests;
create function tests.good(question jsonb)
returns integer
language sql
immutable
set search_path = ''
as $$
  select (o.n - 1)::integer
  from jsonb_array_elements_text(question -> 'answers') with ordinality as o (a, n)
  where o.a = 'bonne';
$$;
grant usage on schema tests to authenticated;
grant execute on function tests.good(jsonb) to authenticated;

-- Recule l'heure d'envoi de la question `p_position` (temps serveur simulé).
create function tests.served_ago(p_quiz jsonb, p_position integer, p_ago interval)
returns void
language sql
set search_path = ''
as $$
  update public.quiz_session_questions
     set served_at = now() - p_ago
   where quiz_id = (p_quiz ->> 'quiz_id')::uuid and position = p_position;
$$;

-- T1 : quiz complet ; T2 : reprise du défi du jour ; T3 : autre joueur.
insert into auth.users (id, aud, role)
values
  ('00000000-0000-0000-0000-0000000003a1', 'authenticated', 'authenticated'),
  ('00000000-0000-0000-0000-0000000003b1', 'authenticated', 'authenticated'),
  ('00000000-0000-0000-0000-0000000003c1', 'authenticated', 'authenticated');

-- Droits ---------------------------------------------------------------------

select ok(
  not has_function_privilege('anon', 'public.next_question(uuid)', 'execute')
  and not has_function_privilege('public', 'public.next_question(uuid)', 'execute'),
  'anon et public ne peuvent pas appeler next_question'
);

select ok(
  has_function_privilege('authenticated', 'public.next_question(uuid)', 'execute'),
  'authenticated peut appeler next_question'
);

select is(
  (select prosecdef and proconfig @> array['search_path=""']
   from pg_proc where oid = 'public.next_question(uuid)'::regprocedure),
  true,
  'next_question : security definer + search_path vide'
);

select ok(
  not has_function_privilege('authenticated',
    'public.served_question_json(uuid, integer)', 'execute')
  and not has_function_privilege('anon',
    'public.served_question_json(uuid, integer)', 'execute'),
  'served_question_json : fonction interne'
);

-- Une seule question au départ -------------------------------------------------

set local role authenticated;
set local "request.jwt.claims" to '{"sub":"00000000-0000-0000-0000-0000000003a1","role":"authenticated"}';

do $$ begin
  perform set_config('t.s', public.start_quiz('mix')::text, true);
end $$;

select is(
  jsonb_array_length(current_setting('t.s')::jsonb -> 'questions'),
  1,
  'start_quiz : une seule question renvoyée'
);

select is(
  (current_setting('t.s')::jsonb ->> 'total')::int * 100
    + (current_setting('t.s')::jsonb ->> 'position')::int,
  1001,
  'start_quiz : total 10, question en cours 1'
);

reset role;

select is(
  (select array_agg(position order by position)
   from public.quiz_session_questions
   where quiz_id = (current_setting('t.s')::jsonb ->> 'quiz_id')::uuid
     and served_at is not null),
  '{1}'::smallint[],
  'seule la question 1 a une heure d''envoi'
);

set local role authenticated;

select throws_ok(
  format($$select public.next_question(%L)$$, current_setting('t.s')::jsonb ->> 'quiz_id'),
  '22023', null,
  'next_question refusé avant la réponse à la question 1'
);

-- Q1 : réponse juste, immédiate.
select is(
  public.answer_question(
    (current_setting('t.s')::jsonb ->> 'quiz_id')::uuid,
    current_setting('t.s')::jsonb -> 'questions' -> 0 ->> 'id',
    tests.good(current_setting('t.s')::jsonb -> 'questions' -> 0), 500) ->> 'correct',
  'true',
  'Q1 : réponse juste enregistrée'
);

-- next_question : question 2, idempotente ------------------------------------

do $$ begin
  perform set_config('t.n2', public.next_question(
    (current_setting('t.s')::jsonb ->> 'quiz_id')::uuid)::text, true);
end $$;

select is(
  current_setting('t.n2')::jsonb - 'quiz_id' - 'question',
  '{"total": 10, "position": 2}'::jsonb,
  'next_question : question 2 sur 10'
);

select ok(
  not (current_setting('t.n2')::jsonb -> 'question' ? 'correct_index')
  and (current_setting('t.n2')::jsonb -> 'question' -> 'answer') = 'null'::jsonb
  and position('Explication' in current_setting('t.n2')) = 0,
  'next_question : ni bonne réponse ni explication'
);

-- Heure d'envoi reculée de 40 s, puis nouvel appel : rien ne change.
reset role;
select tests.served_ago(current_setting('t.s')::jsonb, 2, interval '40 seconds');
set local role authenticated;

select is(
  public.next_question((current_setting('t.s')::jsonb ->> 'quiz_id')::uuid),
  current_setting('t.n2')::jsonb,
  'next_question rappelé : même question'
);

reset role;
select is(
  (select served_at from public.quiz_session_questions
   where quiz_id = (current_setting('t.s')::jsonb ->> 'quiz_id')::uuid and position = 2),
  now() - interval '40 seconds',
  'next_question rappelé : heure d''envoi inchangée'
);
set local role authenticated;

-- Q2 : bonne réponse envoyée 40 s après l'envoi (time_ms déclaré 500) :
-- temps écoulé forcé.
do $$ begin
  perform set_config('t.a2', public.answer_question(
    (current_setting('t.s')::jsonb ->> 'quiz_id')::uuid,
    current_setting('t.n2')::jsonb -> 'question' ->> 'id',
    tests.good(current_setting('t.n2')::jsonb -> 'question'), 500)::text, true);
end $$;

select is(
  current_setting('t.a2')::jsonb - 'quiz_id' - 'question_id' - 'explanation' - 'correct_choice',
  '{"position": 2, "choice": null, "correct": false, "timed_out": true, "time_ms": 30000}'::jsonb,
  'plus de 33 s côté serveur : temps écoulé, réponse fausse malgré time_ms = 500'
);

select is(
  public.answer_question(
    (current_setting('t.s')::jsonb ->> 'quiz_id')::uuid,
    current_setting('t.n2')::jsonb -> 'question' ->> 'id',
    tests.good(current_setting('t.n2')::jsonb -> 'question'), 500),
  current_setting('t.a2')::jsonb,
  'réessai : temps écoulé conservé'
);

-- Q3 : envoyée il y a 32 s (sous 30 s + 3 s de tolérance) : réponse valable,
-- mais lente côté serveur malgré time_ms = 1 000.
do $$ begin
  perform set_config('t.n3', public.next_question(
    (current_setting('t.s')::jsonb ->> 'quiz_id')::uuid)::text, true);
end $$;
reset role;
select tests.served_ago(current_setting('t.s')::jsonb, 3, interval '32 seconds');
set local role authenticated;

select is(
  public.answer_question(
    (current_setting('t.s')::jsonb ->> 'quiz_id')::uuid,
    current_setting('t.n3')::jsonb -> 'question' ->> 'id',
    tests.good(current_setting('t.n3')::jsonb -> 'question'), 1000)
    - 'quiz_id' - 'question_id' - 'explanation' - 'correct_choice' - 'choice',
  '{"position": 3, "correct": true, "timed_out": false, "time_ms": 1000}'::jsonb,
  '32 s côté serveur (tolérance 3 s) : réponse valable'
);

reset role;
select is(
  (select elapsed_ms from public.quiz_session_questions
   where quiz_id = (current_setting('t.s')::jsonb ->> 'quiz_id')::uuid and position = 3),
  32000,
  'temps serveur enregistré (elapsed_ms)'
);
set local role authenticated;

-- Q4 : envoyée il y a 11,5 s, time_ms 9 000 : bonus (tolérance réseau 2 s).
do $$ begin
  perform set_config('t.n4', public.next_question(
    (current_setting('t.s')::jsonb ->> 'quiz_id')::uuid)::text, true);
end $$;
reset role;
select tests.served_ago(current_setting('t.s')::jsonb, 4, interval '11.5 seconds');
set local role authenticated;

select is(
  public.answer_question(
    (current_setting('t.s')::jsonb ->> 'quiz_id')::uuid,
    current_setting('t.n4')::jsonb -> 'question' ->> 'id',
    tests.good(current_setting('t.n4')::jsonb -> 'question'), 9000) ->> 'time_ms',
  '9000',
  'temps déclaré sous le temps serveur : gardé'
);

-- Q5 : envoyée il y a 5 s, time_ms déclaré 8 000 : ramené à 5 000.
do $$ begin
  perform set_config('t.n5', public.next_question(
    (current_setting('t.s')::jsonb ->> 'quiz_id')::uuid)::text, true);
end $$;
reset role;
select tests.served_ago(current_setting('t.s')::jsonb, 5, interval '5 seconds');
set local role authenticated;

select is(
  public.answer_question(
    (current_setting('t.s')::jsonb ->> 'quiz_id')::uuid,
    current_setting('t.n5')::jsonb -> 'question' ->> 'id',
    tests.good(current_setting('t.n5')::jsonb -> 'question'), 8000) ->> 'time_ms',
  '5000',
  'temps déclaré au-dessus du temps serveur : ramené au temps serveur'
);

-- Q6 à Q10 : réponses justes immédiates.
select lives_ok(
  $q$do $d$
  declare
    v jsonb;
  begin
    for i in 6 .. 10 loop
      v := public.next_question((current_setting('t.s')::jsonb ->> 'quiz_id')::uuid);
      perform public.answer_question(
        (current_setting('t.s')::jsonb ->> 'quiz_id')::uuid,
        v -> 'question' ->> 'id', tests.good(v -> 'question'), 500);
    end loop;
  end $d$$q$,
  'questions 6 à 10 servies et répondues une à une'
);

select throws_ok(
  format($$select public.next_question(%L)$$, current_setting('t.s')::jsonb ->> 'quiz_id'),
  '22023', null,
  'next_question après la 10e réponse : quiz terminé'
);

-- Un autre joueur ne lit pas les questions de ce quiz.
set local "request.jwt.claims" to '{"sub":"00000000-0000-0000-0000-0000000003c1","role":"authenticated"}';

select throws_ok(
  format($$select public.next_question(%L)$$, current_setting('t.s')::jsonb ->> 'quiz_id'),
  '22023', null,
  'next_question sur le quiz d''un autre joueur refusé'
);

set local "request.jwt.claims" to '{"sub":"00000000-0000-0000-0000-0000000003a1","role":"authenticated"}';

-- Soumission : XP selon les temps serveur ------------------------------------

-- Durée totale : départ reculé (sinon 48 s déclarés pour une durée serveur
-- nulle).
reset role;
update public.quiz_sessions
   set started_at = now() - interval '2 minutes'
 where id = (current_setting('t.s')::jsonb ->> 'quiz_id')::uuid;
set local role authenticated;

-- 9 bonnes réponses (Q2 en temps écoulé) : 9×10 ; rapidité Q1, Q4 à Q10
-- (8×5, pas Q3 : 32 s côté serveur) ; combo de Q5 à Q10 (6×5) ; +20 = 180.
select is(
  public.submit_quiz((current_setting('t.s')::jsonb ->> 'quiz_id')::uuid)
    - 'profile' - 'quiz_id',
  '{"duplicate": false, "score": 9, "total": 10, "xp_gained": 180, "xp_capped": false}'::jsonb,
  'bonus rapidité refusé pour une réponse lente côté serveur, même avec time_ms faible'
);

select throws_ok(
  format($$select public.next_question(%L)$$, current_setting('t.s')::jsonb ->> 'quiz_id'),
  '22023', null,
  'next_question après soumission refusé'
);

-- Quiz expiré ------------------------------------------------------------------

do $$ begin
  perform set_config('t.e', public.start_quiz('mix')::text, true);
  perform public.answer_question(
    (current_setting('t.e')::jsonb ->> 'quiz_id')::uuid,
    current_setting('t.e')::jsonb -> 'questions' -> 0 ->> 'id', 0, 500);
end $$;

reset role;
update public.quiz_sessions
   set expires_at = now() - interval '1 second'
 where id = (current_setting('t.e')::jsonb ->> 'quiz_id')::uuid;
set local role authenticated;

select throws_ok(
  format($$select public.next_question(%L)$$, current_setting('t.e')::jsonb ->> 'quiz_id'),
  '22023', null,
  'next_question sur un quiz expiré refusé'
);

select throws_ok(
  $$select public.next_question(null)$$,
  '22023', null,
  'next_question sans quiz refusé'
);

select throws_ok(
  format($$select public.next_question(%L)$$, gen_random_uuid()),
  '22023', null,
  'next_question sur un quiz inconnu refusé'
);

-- Reprise du défi du jour -----------------------------------------------------------

set local "request.jwt.claims" to '{"sub":"00000000-0000-0000-0000-0000000003b1","role":"authenticated"}';

do $$
declare
  v jsonb;
begin
  perform set_config('t.d', public.start_quiz('daily')::text, true);
  perform public.answer_question(
    (current_setting('t.d')::jsonb ->> 'quiz_id')::uuid,
    current_setting('t.d')::jsonb -> 'questions' -> 0 ->> 'id',
    tests.good(current_setting('t.d')::jsonb -> 'questions' -> 0), 500);
  v := public.next_question((current_setting('t.d')::jsonb ->> 'quiz_id')::uuid);
  perform set_config('t.d2', v::text, true);
end $$;

-- L'app est fermée sur la question 2 et rouverte 10 min plus tard.
reset role;
select tests.served_ago(current_setting('t.d')::jsonb, 2, interval '10 minutes');
set local role authenticated;

do $$ begin
  perform set_config('t.r', public.start_quiz('daily')::text, true);
end $$;

select is(
  current_setting('t.r')::jsonb ->> 'quiz_id',
  current_setting('t.d')::jsonb ->> 'quiz_id',
  'reprise : même session'
);

select is(
  jsonb_array_length(current_setting('t.r')::jsonb -> 'questions') * 100
    + (current_setting('t.r')::jsonb ->> 'position')::int,
  202,
  'reprise : question 1 répondue + question 2 en cours'
);

select is(
  (current_setting('t.r')::jsonb -> 'questions' -> 1) - 'answer',
  (current_setting('t.d2')::jsonb -> 'question') - 'answer',
  'reprise : question en cours renvoyée telle quelle'
);

select is(
  public.next_question((current_setting('t.d')::jsonb ->> 'quiz_id')::uuid) -> 'question',
  current_setting('t.d2')::jsonb -> 'question',
  'reprise : next_question renvoie aussi la question en cours'
);

reset role;
select is(
  (select served_at from public.quiz_session_questions
   where quiz_id = (current_setting('t.d')::jsonb ->> 'quiz_id')::uuid and position = 2),
  now() - interval '10 minutes',
  'reprise : heure d''envoi d''origine conservée'
);
set local role authenticated;

select is(
  public.answer_question(
    (current_setting('t.d')::jsonb ->> 'quiz_id')::uuid,
    current_setting('t.d2')::jsonb -> 'question' ->> 'id',
    tests.good(current_setting('t.d2')::jsonb -> 'question'), 500) ->> 'timed_out',
  'true',
  'reprise : question en cours depuis plus de 33 s comptée en temps écoulé'
);

-- Toutes les questions répondues puis reprise : plus de question en cours.
select lives_ok(
  $q$do $d$
  declare
    v jsonb;
  begin
    for i in 3 .. 10 loop
      v := public.next_question((current_setting('t.d')::jsonb ->> 'quiz_id')::uuid);
      perform public.answer_question(
        (current_setting('t.d')::jsonb ->> 'quiz_id')::uuid,
        v -> 'question' ->> 'id', 0, 500);
    end loop;
    perform set_config('t.r2', public.start_quiz('daily')::text, true);
  end $d$$q$,
  'défi répondu en entier puis repris'
);

select is(
  jsonb_array_length(current_setting('t.r2')::jsonb -> 'questions')::text
    || '/' || coalesce(current_setting('t.r2')::jsonb ->> 'position', 'null'),
  '10/null',
  'reprise d''un défi entièrement répondu : 10 corrections, aucune question en cours'
);

-- Sans uid, anon -------------------------------------------------------------------

set local "request.jwt.claims" to '{"role":"authenticated"}';

select throws_ok(
  $$select public.next_question(gen_random_uuid())$$,
  '42501', null,
  'next_question sans uid refusé'
);

reset role;
set local role anon;
set local "request.jwt.claims" to '{"role":"anon"}';

select throws_ok(
  $$select public.next_question(gen_random_uuid())$$,
  '42501', null,
  'anon ne peut pas appeler next_question'
);

reset role;

select * from finish();
rollback;
