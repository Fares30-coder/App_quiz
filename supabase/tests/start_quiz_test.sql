-- Tests pgTAP du service des quiz : start_quiz(), answer_question(), défi du
-- jour (daily_challenges) et submit_quiz(quiz_id) de bout en bout.
-- Lancer en local : `supabase start` puis `supabase test db`.
--
-- Dans une transaction, now() ne bouge pas : le temps « écoulé » côté
-- serveur vaut 0, d'où des réponses à 500 ms (tolérance 1 s) et un départ
-- reculé par le propriétaire avant les soumissions.
begin;
create extension if not exists pgtap with schema extensions;

select plan(92);

-- Données de test (propriétaire) -------------------------------------------

-- Base vide (seed compris) : tout est annulé à la fin.
delete from public.quiz_session_questions;
delete from public.quiz_sessions;
delete from public.daily_challenges;
delete from public.questions;

-- Aide de test : position de la réponse « bonne » dans la question `i`
-- (à partir de 0) d'un quiz renvoyé par start_quiz().
create schema tests;
create function tests.good(quiz jsonb, i integer)
returns integer
language sql
immutable
set search_path = ''
as $$
  select (o.n - 1)::integer
  from jsonb_array_elements_text(quiz -> 'questions' -> i -> 'answers')
       with ordinality as o (a, n)
  where o.a = 'bonne';
$$;
grant usage on schema tests to authenticated;
grant execute on function tests.good(jsonb, integer) to authenticated;

-- P1, P2 : joueurs ; P3 : limite de débit ; P4 : profil absent ;
-- P5 : soumission tardive ; P6, P7 : quiz abandonnés.
insert into auth.users (id, aud, role)
values
  ('00000000-0000-0000-0000-0000000001a1', 'authenticated', 'authenticated'),
  ('00000000-0000-0000-0000-0000000001b1', 'authenticated', 'authenticated'),
  ('00000000-0000-0000-0000-0000000001c1', 'authenticated', 'authenticated'),
  ('00000000-0000-0000-0000-0000000001d1', 'authenticated', 'authenticated'),
  ('00000000-0000-0000-0000-0000000001e1', 'authenticated', 'authenticated'),
  ('00000000-0000-0000-0000-0000000001f1', 'authenticated', 'authenticated'),
  ('00000000-0000-0000-0000-0000000002a1', 'authenticated', 'authenticated');
delete from public.profiles where id = '00000000-0000-0000-0000-0000000001d1';

-- P3 a déjà commencé 30 quiz dans l'heure.
insert into public.quiz_sessions (user_id, mode, started_at, expires_at)
select '00000000-0000-0000-0000-0000000001c1', 'mix',
       now() - interval '30 minutes', now()
from generate_series(1, 30);

-- P6 : 10 quiz commencés aujourd'hui, jamais soumis. P7 : 9 abandonnés et
-- 1 soumis.
insert into public.quiz_sessions (user_id, mode, started_at, expires_at, submitted_at)
select '00000000-0000-0000-0000-0000000001f1'::uuid, 'mix', now(), now(), null::timestamptz
from generate_series(1, 10)
union all
select '00000000-0000-0000-0000-0000000002a1', 'mix', now(), now(),
       case when i = 1 then now() end
from generate_series(1, 10) i;

-- Droits ---------------------------------------------------------------------

select is(
  (select array_agg(relname::text) from pg_class c
   join pg_namespace n on n.oid = c.relnamespace
   where n.nspname = 'public' and c.relkind = 'r' and not c.relrowsecurity),
  null,
  'aucune table du schéma public sans RLS'
);

select ok(
  not has_function_privilege('anon', 'public.start_quiz(text, text)', 'execute')
  and not has_function_privilege('public', 'public.start_quiz(text, text)', 'execute'),
  'anon et public ne peuvent pas appeler start_quiz'
);

select ok(
  has_function_privilege('authenticated', 'public.start_quiz(text, text)', 'execute'),
  'authenticated peut appeler start_quiz'
);

select ok(
  not has_function_privilege('anon',
    'public.answer_question(uuid, text, integer, integer)', 'execute')
  and not has_function_privilege('public',
    'public.answer_question(uuid, text, integer, integer)', 'execute'),
  'anon et public ne peuvent pas appeler answer_question'
);

select ok(
  has_function_privilege('authenticated',
    'public.answer_question(uuid, text, integer, integer)', 'execute'),
  'authenticated peut appeler answer_question'
);

select is(
  (select bool_and(prosecdef and proconfig @> array['search_path=""'])
   from pg_proc
   where oid in ('public.start_quiz(text, text)'::regprocedure,
                 'public.answer_question(uuid, text, integer, integer)'::regprocedure,
                 'public.submit_quiz(uuid)'::regprocedure)),
  true,
  'start_quiz, answer_question, submit_quiz : security definer + search_path vide'
);

select ok(
  not has_function_privilege('authenticated', 'public.ensure_daily_challenge(date)', 'execute')
  and not has_function_privilege('anon', 'public.ensure_daily_challenge(date)', 'execute')
  and not has_function_privilege('public', 'public.ensure_daily_challenge(date)', 'execute'),
  'ensure_daily_challenge : fonction interne (ni public, ni anon, ni authenticated)'
);

select ok(
  not has_function_privilege('authenticated', 'public.purge_quiz_sessions()', 'execute')
  and not has_function_privilege('anon', 'public.purge_quiz_sessions()', 'execute')
  and not has_function_privilege('public', 'public.purge_quiz_sessions()', 'execute'),
  'purge_quiz_sessions : fonction interne'
);

select ok(
  not has_function_privilege('anon', 'public.submit_quiz(uuid)', 'execute')
  and not has_function_privilege('public', 'public.submit_quiz(uuid)', 'execute'),
  'anon et public ne peuvent pas appeler submit_quiz(uuid)'
);

-- Liste blanche des fonctions du schéma public appelables sans compte :
-- vide pour l'instant (tout passe par une session, anonyme comprise).
select is(
  (select array_agg(p.oid::regprocedure::text order by p.oid::regprocedure::text)
   from pg_proc p
   where p.pronamespace = 'public'::regnamespace
     and (has_function_privilege('anon', p.oid, 'execute')
          or has_function_privilege('public', p.oid, 'execute'))
     and p.oid::regprocedure::text <> all (array[]::text[])),
  null,
  'aucune fonction du schéma public exécutable par anon ou public hors liste blanche'
);

select is(
  (select schedule from cron.job where jobname = 'purge-quiz-sessions'),
  '30 3 * * *',
  'purge quotidienne programmée (pg_cron)'
);

select is(
  (select count(*)::int from pg_proc
   where proname = 'submit_quiz' and pronamespace = 'public'::regnamespace),
  1,
  'ancienne signature de submit_quiz supprimée'
);

select ok(
  not has_table_privilege(r, t, 'select,insert,update,delete,truncate'),
  format('%s : aucun privilège sur %s', r, t)
)
from unnest(array['anon', 'authenticated']) r,
     unnest(array['public.daily_challenges', 'public.quiz_sessions',
                  'public.quiz_session_questions', 'public.questions']) t;

-- Pas assez de questions -----------------------------------------------------

set local role authenticated;
set local "request.jwt.claims" to '{"sub":"00000000-0000-0000-0000-0000000001a1","role":"authenticated"}';

select throws_ok(
  $$select public.start_quiz('daily')$$,
  'P0002', null,
  'base vide : défi du jour impossible (P0002)'
);

reset role;

select is(
  (select count(*)::int from public.daily_challenges),
  0,
  'base vide : aucun défi enregistré'
);

-- 12 questions « divers » (bonne réponse « bonne ») et 3 « histoire ».
insert into public.questions
  (id, category, difficulty, question, answers, correct_index, explanation)
select 'zz-' || lpad(i::text, 2, '0'), 'divers', 1, 'Question ' || i,
       array['bonne', 'b', 'c', 'd'], 0, 'Explication ' || i
from generate_series(1, 12) i
union all
select 'his-' || i, 'histoire', 1, 'Histoire ' || i,
       array['bonne', 'b', 'c', 'd'], 0, 'Explication histoire ' || i
from generate_series(1, 3) i;

-- Défi d'hier : zz-01 à zz-10 (évitées aujourd'hui si possible).
insert into public.daily_challenges (day, question_ids)
values ((now() at time zone 'Europe/Paris')::date - 1,
        '{zz-01,zz-02,zz-03,zz-04,zz-05,zz-06,zz-07,zz-08,zz-09,zz-10}');

-- Défi du jour : P1 puis P2 -----------------------------------------------------

set local role authenticated;
set local "request.jwt.claims" to '{"sub":"00000000-0000-0000-0000-0000000001a1","role":"authenticated"}';

do $$ begin
  perform set_config('t.p1', public.start_quiz('daily')::text, true);
end $$;

select is(
  jsonb_array_length(current_setting('t.p1')::jsonb -> 'questions'),
  10,
  'défi du jour : 10 questions'
);

select is(
  current_setting('t.p1')::jsonb - 'quiz_id' - 'questions' - 'expires_at',
  jsonb_build_object('mode', 'daily', 'category', null, 'resumed', false,
                     'day', (now() at time zone 'Europe/Paris')::date),
  'défi du jour : mode et jour Europe/Paris'
);

select ok(
  (current_setting('t.p1')::jsonb ->> 'expires_at')::timestamptz
    >= (((now() at time zone 'Europe/Paris')::date + 1)::timestamp
        at time zone 'Europe/Paris'),
  'défi du jour : reprenable jusqu''à minuit (Europe/Paris)'
);

select ok(
  (select bool_and((q -> 'answer') = 'null'::jsonb)
   from jsonb_array_elements(current_setting('t.p1')::jsonb -> 'questions') q),
  'nouveau quiz : aucune réponse enregistrée'
);

select ok(
  (select bool_and(not (q ? 'correct_index') and not (q ? 'explanation')
                   and not (q ? 'correct') and not (q ? 'answer_order'))
   from jsonb_array_elements(current_setting('t.p1')::jsonb -> 'questions') q)
  and position('Explication' in current_setting('t.p1')) = 0,
  'aucune bonne réponse ni explication renvoyée'
);

select is(
  (select array_agg(q ->> 'id' order by q ->> 'id')
   from jsonb_array_elements(current_setting('t.p1')::jsonb -> 'questions') q
   where q ->> 'id' in ('zz-11', 'zz-12', 'his-1', 'his-2', 'his-3')),
  array['his-1', 'his-2', 'his-3', 'zz-11', 'zz-12'],
  'défi du jour : questions absentes des 7 derniers jours en priorité'
);

select ok(
  (select bool_and(jsonb_array_length(q -> 'answers') = 4 and q -> 'answers' ? 'bonne')
   from jsonb_array_elements(current_setting('t.p1')::jsonb -> 'questions') q),
  '4 réponses par question, bonne réponse comprise (position inconnue)'
);

set local "request.jwt.claims" to '{"sub":"00000000-0000-0000-0000-0000000001b1","role":"authenticated"}';

do $$ begin
  perform set_config('t.p2', public.start_quiz('daily')::text, true);
end $$;

select is(
  (select array_agg(q ->> 'id' order by n)
   from jsonb_array_elements(current_setting('t.p2')::jsonb -> 'questions')
        with ordinality as t (q, n)),
  (select array_agg(q ->> 'id' order by n)
   from jsonb_array_elements(current_setting('t.p1')::jsonb -> 'questions')
        with ordinality as t (q, n)),
  'défi du jour identique pour deux joueurs (même ordre)'
);

select isnt(
  current_setting('t.p2')::jsonb ->> 'quiz_id',
  current_setting('t.p1')::jsonb ->> 'quiz_id',
  'un quiz_id par joueur'
);

reset role;

select is(
  (select count(*)::int from public.daily_challenges
   where day = (now() at time zone 'Europe/Paris')::date),
  1,
  'un seul défi enregistré pour aujourd''hui'
);

select is(
  public.ensure_daily_challenge((now() at time zone 'Europe/Paris')::date),
  public.ensure_daily_challenge((now() at time zone 'Europe/Paris')::date),
  'ensure_daily_challenge idempotent'
);

-- 10 questions mélangées indépendamment : le même ordre partout aurait une
-- probabilité de (1/24)^9.
select ok(
  (select count(distinct sq.answer_order) > 1
   from public.quiz_session_questions sq
   where sq.quiz_id = (current_setting('t.p1')::jsonb ->> 'quiz_id')::uuid),
  'réponses mélangées question par question'
);

select is(
  (select count(distinct qs.user_id)::int from public.quiz_sessions qs
   where qs.mode = 'daily'),
  2,
  'sessions enregistrées (uid, mode)'
);

-- Paramètres invalides, autres modes -------------------------------------------

set local role authenticated;
set local "request.jwt.claims" to '{"sub":"00000000-0000-0000-0000-0000000001a1","role":"authenticated"}';

select throws_ok($$select public.start_quiz('foo')$$, '22023', null, 'mode inconnu refusé');
select throws_ok($$select public.start_quiz(null)$$, '22023', null, 'mode manquant refusé');
select throws_ok($$select public.start_quiz('category')$$, '22023', null,
  'mode catégorie sans catégorie refusé');
select throws_ok($$select public.start_quiz('category', 'cuisine')$$, '22023', null,
  'catégorie inconnue refusée');
select throws_ok($$select public.start_quiz('mix', 'divers')$$, '22023', null,
  'mode mix avec catégorie refusé');
select throws_ok($$select public.start_quiz('category', 'histoire')$$, 'P0002', null,
  'catégorie de 3 questions : pas assez de questions (P0002)');

select is(
  (select array_agg(distinct q ->> 'category')
   from jsonb_array_elements(public.start_quiz('category', 'divers') -> 'questions') q),
  array['divers'],
  'mode catégorie : questions de la catégorie'
);

select is(
  (select count(distinct q ->> 'id')::int
   from jsonb_array_elements(public.start_quiz('mix') -> 'questions') q),
  10,
  'mode mix : 10 questions distinctes'
);

-- answer_question ---------------------------------------------------------------

select throws_ok(
  format($$select public.answer_question(%L, %L, 0, 500)$$,
         current_setting('t.p1')::jsonb ->> 'quiz_id',
         current_setting('t.p1')::jsonb -> 'questions' -> 1 ->> 'id'),
  '22023', null,
  'question hors ordre refusée'
);

select throws_ok(
  format($$select public.answer_question(%L, 'zz-inconnue', 0, 500)$$,
         current_setting('t.p1')::jsonb ->> 'quiz_id'),
  '22023', null,
  'question absente du quiz refusée'
);

select throws_ok(
  format($$select public.answer_question(%L, %L, 0, 499)$$,
         current_setting('t.p1')::jsonb ->> 'quiz_id',
         current_setting('t.p1')::jsonb -> 'questions' -> 0 ->> 'id'),
  '22023', null,
  'réponse en moins de 0,5 s refusée'
);

select throws_ok(
  format($$select public.answer_question(%L, %L, 0, 30001)$$,
         current_setting('t.p1')::jsonb ->> 'quiz_id',
         current_setting('t.p1')::jsonb -> 'questions' -> 0 ->> 'id'),
  '22023', null,
  'réponse au-delà de 30 s refusée'
);

select throws_ok(
  format($$select public.answer_question(%L, %L, 0, null)$$,
         current_setting('t.p1')::jsonb ->> 'quiz_id',
         current_setting('t.p1')::jsonb -> 'questions' -> 0 ->> 'id'),
  '22023', null,
  'temps manquant refusé'
);

select throws_ok(
  format($$select public.answer_question(%L, %L, 4, 500)$$,
         current_setting('t.p1')::jsonb ->> 'quiz_id',
         current_setting('t.p1')::jsonb -> 'questions' -> 0 ->> 'id'),
  '22023', null,
  'réponse hors de 0 à 3 refusée'
);

select throws_ok(
  format($$select public.answer_question(%L, %L, 0, 5000)$$,
         current_setting('t.p1')::jsonb ->> 'quiz_id',
         current_setting('t.p1')::jsonb -> 'questions' -> 0 ->> 'id'),
  '22023', null,
  'temps déclaré supérieur au temps écoulé côté serveur refusé'
);

select throws_ok(
  format($$select public.answer_question(%L, %L, 0, 500)$$,
         gen_random_uuid(),
         current_setting('t.p1')::jsonb -> 'questions' -> 0 ->> 'id'),
  '22023', null,
  'quiz inconnu refusé'
);

-- P1 répond juste à toutes les questions de son défi (position de « bonne »
-- lue dans les réponses servies), sauf la 2e (temps écoulé).
do $$ begin
  perform set_config('t.a1', public.answer_question(
    (current_setting('t.p1')::jsonb ->> 'quiz_id')::uuid,
    current_setting('t.p1')::jsonb -> 'questions' -> 0 ->> 'id',
    tests.good(current_setting('t.p1')::jsonb, 0), 500)::text, true);
end $$;

select is(
  current_setting('t.a1')::jsonb - 'quiz_id' - 'question_id' - 'explanation' - 'choice',
  jsonb_build_object('position', 1, 'correct', true,
                     'correct_choice', tests.good(current_setting('t.p1')::jsonb, 0)),
  'réponse juste : correction renvoyée'
);

select ok(
  current_setting('t.a1')::jsonb ->> 'explanation' like 'Explication%',
  'explication renvoyée après la réponse'
);

select is(
  public.answer_question(
    (current_setting('t.p1')::jsonb ->> 'quiz_id')::uuid,
    current_setting('t.p1')::jsonb -> 'questions' -> 0 ->> 'id',
    (tests.good(current_setting('t.p1')::jsonb, 0) + 1) % 4, 900),
  current_setting('t.a1')::jsonb,
  'réessai avec un autre choix : réponse d''origine renvoyée, inchangée'
);

select is(
  public.answer_question(
    (current_setting('t.p1')::jsonb ->> 'quiz_id')::uuid,
    current_setting('t.p1')::jsonb -> 'questions' -> 1 ->> 'id',
    null, 1000) - 'quiz_id' - 'question_id' - 'explanation' - 'correct_choice',
  '{"position": 2, "choice": null, "correct": false}'::jsonb,
  'temps écoulé (choix null) : réponse fausse'
);

-- Reprise du défi du jour : même session, réponses déjà enregistrées.
do $$ begin
  perform set_config('t.r1', public.start_quiz('daily')::text, true);
end $$;

select is(
  current_setting('t.r1')::jsonb ->> 'quiz_id',
  current_setting('t.p1')::jsonb ->> 'quiz_id',
  'défi démarré deux fois : même session reprise'
);

select ok(
  (current_setting('t.r1')::jsonb ->> 'resumed')::boolean,
  'reprise signalée (resumed)'
);

select is(
  (select jsonb_agg(q - 'answer') from jsonb_array_elements(current_setting('t.r1')::jsonb -> 'questions') q),
  (select jsonb_agg(q - 'answer') from jsonb_array_elements(current_setting('t.p1')::jsonb -> 'questions') q),
  'reprise : mêmes questions, même ordre des réponses'
);

select is(
  (current_setting('t.r1')::jsonb -> 'questions' -> 0 -> 'answer') - 'explanation',
  jsonb_build_object('choice', tests.good(current_setting('t.p1')::jsonb, 0),
                     'correct', true,
                     'correct_choice', tests.good(current_setting('t.p1')::jsonb, 0),
                     'time_ms', 500),
  'reprise : 1re réponse avec sa correction'
);

select is(
  (current_setting('t.r1')::jsonb -> 'questions' -> 1 -> 'answer')
    - 'explanation' - 'correct_choice',
  '{"choice": null, "correct": false, "time_ms": 1000}'::jsonb,
  'reprise : 2e réponse (temps écoulé)'
);

select ok(
  (current_setting('t.r1')::jsonb -> 'questions' -> 1 -> 'answer' ->> 'explanation')
    like 'Explication%'
  and (current_setting('t.r1')::jsonb -> 'questions' -> 2 -> 'answer') = 'null'::jsonb,
  'reprise : explication des questions répondues seulement'
);

reset role;

select is(
  (select count(*)::int from public.quiz_sessions
   where user_id = '00000000-0000-0000-0000-0000000001a1' and mode = 'daily'),
  1,
  'reprise : aucune nouvelle session'
);

select throws_ok(
  $$insert into public.quiz_sessions (user_id, mode, challenge_day, expires_at)
    values ('00000000-0000-0000-0000-0000000001a1', 'daily',
            (now() at time zone 'Europe/Paris')::date, now())$$,
  '23505', null,
  'index unique : un seul défi par joueur et par jour'
);

set local role authenticated;

-- Un autre joueur ne peut ni répondre ni soumettre ce quiz.
set local "request.jwt.claims" to '{"sub":"00000000-0000-0000-0000-0000000001b1","role":"authenticated"}';

select throws_ok(
  format($$select public.answer_question(%L, %L, 0, 500)$$,
         current_setting('t.p1')::jsonb ->> 'quiz_id',
         current_setting('t.p1')::jsonb -> 'questions' -> 2 ->> 'id'),
  '22023', null,
  'réponse au quiz d''un autre joueur refusée'
);

set local "request.jwt.claims" to '{"sub":"00000000-0000-0000-0000-0000000001a1","role":"authenticated"}';

select throws_ok(
  format($$select public.submit_quiz(%L)$$, current_setting('t.p1')::jsonb ->> 'quiz_id'),
  '22023', null,
  'quiz incomplet (2 réponses sur 10) refusé'
);

select lives_ok(
  $q$do $d$ begin
    for i in 2 .. 9 loop
      perform public.answer_question(
        (current_setting('t.p1')::jsonb ->> 'quiz_id')::uuid,
        current_setting('t.p1')::jsonb -> 'questions' -> i ->> 'id',
        tests.good(current_setting('t.p1')::jsonb, i), 500);
    end loop;
  end $d$$q$,
  'questions 3 à 10 répondues dans l''ordre'
);

-- Soumission -------------------------------------------------------------------

-- Durée serveur nulle (même transaction) : 5 500 ms déclarés.
select throws_ok(
  format($$select public.submit_quiz(%L)$$, current_setting('t.p1')::jsonb ->> 'quiz_id'),
  '22023', null,
  'durée totale supérieure à la durée serveur refusée'
);

reset role;
update public.quiz_sessions
   set started_at = started_at - interval '1 minute'
 where id = (current_setting('t.p1')::jsonb ->> 'quiz_id')::uuid;
set local role authenticated;

-- 9 bonnes réponses, la 2e manquée : 9×10 + 9×5 (rapidité) + combo
-- (3e à 10e d'affilée : bonus de la 5e à la 10e, 6×5) + 20 = 185.
select is(
  public.submit_quiz((current_setting('t.p1')::jsonb ->> 'quiz_id')::uuid)
    - 'profile' - 'quiz_id',
  '{"duplicate": false, "score": 9, "total": 10, "xp_gained": 185, "xp_capped": false}'::jsonb,
  'soumission : score et XP recalculés depuis les réponses enregistrées'
);

select is(
  (public.submit_quiz((current_setting('t.p1')::jsonb ->> 'quiz_id')::uuid) ->> 'duplicate')::boolean,
  true,
  'double soumission : résultat déjà enregistré, rien recompté'
);

select is(
  (select row(xp, streak, quiz_count)::text from public.profiles
   where id = '00000000-0000-0000-0000-0000000001a1'),
  '(185,1,1)',
  'profil mis à jour une seule fois'
);

select throws_ok(
  format($$select public.answer_question(%L, %L, 0, 500)$$,
         current_setting('t.p1')::jsonb ->> 'quiz_id',
         current_setting('t.p1')::jsonb -> 'questions' -> 9 ->> 'id'),
  '22023', null,
  'réponse (même un réessai) après soumission refusée'
);

select throws_ok($$select public.start_quiz('daily')$$, '23505', null,
  'défi du jour déjà soumis : refusé (23505)');

do $$
declare
  v_detail text;
begin
  perform public.start_quiz('daily');
exception when unique_violation then
  get stacked diagnostics v_detail = pg_exception_detail;
  perform set_config('t.dup', v_detail, true);
end $$;

select is(
  current_setting('t.dup')::jsonb,
  '{"score": 9, "total": 10}'::jsonb,
  'défi déjà joué : score renvoyé dans le détail de l''erreur'
);

select throws_ok(
  format($$select public.answer_question(%L, %L, 0, 500)$$,
         current_setting('t.p2')::jsonb ->> 'quiz_id',
         current_setting('t.p2')::jsonb -> 'questions' -> 0 ->> 'id'),
  '22023', null,
  'P1 ne répond pas au quiz de P2'
);

-- Expiration ------------------------------------------------------------------------

set local "request.jwt.claims" to '{"sub":"00000000-0000-0000-0000-0000000001b1","role":"authenticated"}';
reset role;
update public.quiz_sessions
   set started_at = now() - interval '31 minutes',
       expires_at = now() - interval '1 minute'
 where id = (current_setting('t.p2')::jsonb ->> 'quiz_id')::uuid;
set local role authenticated;

select throws_ok(
  format($$select public.answer_question(%L, %L, 0, 500)$$,
         current_setting('t.p2')::jsonb ->> 'quiz_id',
         current_setting('t.p2')::jsonb -> 'questions' -> 0 ->> 'id'),
  '22023', null,
  'quiz expiré : réponse refusée'
);

-- Soumission plus de 6 h après la dernière réponse ---------------------------------

set local "request.jwt.claims" to '{"sub":"00000000-0000-0000-0000-0000000001e1","role":"authenticated"}';

do $$ begin
  perform set_config('t.p5', public.start_quiz('mix')::text, true);
  for i in 0 .. 9 loop
    perform public.answer_question(
      (current_setting('t.p5')::jsonb ->> 'quiz_id')::uuid,
      current_setting('t.p5')::jsonb -> 'questions' -> i ->> 'id', 0, 500);
  end loop;
end $$;

reset role;
update public.quiz_sessions
   set started_at = now() - interval '8 hours'
 where id = (current_setting('t.p5')::jsonb ->> 'quiz_id')::uuid;
update public.quiz_session_questions
   set answered_at = now() - interval '7 hours'
 where quiz_id = (current_setting('t.p5')::jsonb ->> 'quiz_id')::uuid;
set local role authenticated;

select throws_ok(
  format($$select public.submit_quiz(%L)$$, current_setting('t.p5')::jsonb ->> 'quiz_id'),
  '22023', null,
  'soumission plus de 6 h après la dernière réponse refusée'
);

-- Quiz abandonnés ---------------------------------------------------------------

set local "request.jwt.claims" to '{"sub":"00000000-0000-0000-0000-0000000001f1","role":"authenticated"}';

select throws_ok($$select public.start_quiz('mix')$$, 'PT429', null,
  '10 quiz abandonnés aujourd''hui : 11e refusé (PT429)');

set local "request.jwt.claims" to '{"sub":"00000000-0000-0000-0000-0000000002a1","role":"authenticated"}';

select lives_ok($$select public.start_quiz('mix')$$,
  '9 abandonnés et 1 soumis : quiz accepté');

select throws_ok($$select public.start_quiz('mix')$$, 'PT429', null,
  'puis 10 non soumis : refusé (PT429)');

-- Limite de débit, profil absent, sans uid, anon ----------------------------------

set local "request.jwt.claims" to '{"sub":"00000000-0000-0000-0000-0000000001c1","role":"authenticated"}';

select throws_ok($$select public.start_quiz('mix')$$, 'PT429', null,
  '31e quiz commencé dans l''heure refusé (PT429)');

set local "request.jwt.claims" to '{"sub":"00000000-0000-0000-0000-0000000001d1","role":"authenticated"}';

select throws_ok($$select public.start_quiz('mix')$$, 'P0002', null,
  'profil absent : P0002');

set local "request.jwt.claims" to '{"role":"authenticated"}';

select throws_ok($$select public.start_quiz('mix')$$, '42501', null,
  'start_quiz sans uid refusé');
select throws_ok(
  $$select public.answer_question(gen_random_uuid(), 'zz-01', 0, 500)$$,
  '42501', null,
  'answer_question sans uid refusé'
);

reset role;
set local role anon;
set local "request.jwt.claims" to '{"role":"anon"}';

select throws_ok($$select public.start_quiz('daily')$$, '42501', null,
  'anon ne peut pas appeler start_quiz');
select throws_ok(
  $$select public.answer_question(gen_random_uuid(), 'zz-01', 0, 500)$$,
  '42501', null,
  'anon ne peut pas appeler answer_question'
);
select throws_ok($$select * from public.daily_challenges$$, '42501', null,
  'anon ne lit pas daily_challenges');
select throws_ok($$select public.submit_quiz(gen_random_uuid())$$, '42501', null,
  'anon ne peut pas appeler submit_quiz');

reset role;
set local role authenticated;
set local "request.jwt.claims" to '{"sub":"00000000-0000-0000-0000-0000000001a1","role":"authenticated"}';

select throws_ok($$select question_ids from public.daily_challenges$$, '42501', null,
  'authenticated ne lit pas daily_challenges');
select throws_ok($$select answer_order from public.quiz_session_questions$$, '42501', null,
  'authenticated ne lit pas l''ordre des réponses servies');

reset role;

-- Défi dont une question a disparu : remplacée, les autres gardées -------------

insert into public.daily_challenges (day, question_ids)
values ((now() at time zone 'Europe/Paris')::date + 5,
        '{zz-01,zz-gone,zz-02,zz-03,zz-04,zz-05,zz-06,zz-07,zz-08,zz-09}');

select ok(
  (select cardinality(ids) = 10
          and ids[1:9] = '{zz-01,zz-02,zz-03,zz-04,zz-05,zz-06,zz-07,zz-08,zz-09}'
          and (select count(*) from public.questions q where q.id = any (ids)) = 10
   from public.ensure_daily_challenge((now() at time zone 'Europe/Paris')::date + 5) ids),
  'question disparue remplacée, ordre des autres conservé'
);

-- Purge globale -------------------------------------------------------------------

insert into public.quiz_sessions (user_id, mode, started_at, expires_at)
values ('00000000-0000-0000-0000-0000000001b1', 'mix',
        now() - interval '3 days', now() - interval '3 days');

select is(public.purge_quiz_sessions(), 1, 'purge : 1 session de plus de 2 jours');

select is(
  (select count(*)::int from public.quiz_sessions
   where started_at < now() - interval '2 days'),
  0,
  'purge : plus aucune session de plus de 2 jours, les récentes gardées'
);

select * from finish();
rollback;
