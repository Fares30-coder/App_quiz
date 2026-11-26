-- Tests pgTAP de validate_offline_day() : jour validé par un quiz hors ligne
-- (série, gels, compteur du jour), sans XP ni classement.
-- Lancer en local : `supabase start` puis `supabase test db`.
--
-- Dans une transaction, now() ne bouge pas : les jours sont calculés par
-- rapport à now() (Europe/Paris), comme dans submit_quiz_test.sql.
begin;
create extension if not exists pgtap with schema extensions;

select plan(61);

create schema tests;
grant usage on schema tests to authenticated;

-- Jour calendaire Europe/Paris de `at`.
create function tests.paris_day(at timestamptz default now())
returns date
language sql
stable
set search_path = ''
as $$ select (at at time zone 'Europe/Paris')::date $$;
grant execute on function tests.paris_day(timestamptz) to authenticated;

-- Quiz servi au joueur connecté, 10 bonnes réponses en 2 s, dernière
-- réponse à `last_at` (comme tests.serve de submit_quiz_test.sql).
insert into public.questions
  (id, category, difficulty, question, answers, correct_index, explanation)
select 'so-' || lpad(i::text, 2, '0'), 'divers', 1, 'Question ' || i,
       array['a', 'b', 'c', 'd'], 0, 'Explication ' || i
from generate_series(1, 10) i;

create function tests.serve(last_at timestamptz)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id uuid := gen_random_uuid();
  v_start timestamptz := last_at - interval '21 seconds';
begin
  insert into public.quiz_sessions (id, user_id, mode, started_at, expires_at)
  values (v_id, (select auth.uid()), 'mix', v_start, v_start + interval '30 minutes');
  insert into public.quiz_session_questions
    (quiz_id, position, question_id, answer_order, choice, time_ms, answered_at,
     served_at, elapsed_ms)
  select v_id, n, 'so-' || lpad(n::text, 2, '0'), '{0,1,2,3}', 0, 2000,
         v_start + make_interval(secs => 1 + 2 * n),
         v_start + make_interval(secs => 1 + 2 * (n - 1)), 2000
    from generate_series(1, 10) n;
  return v_id;
end;
$$;
grant execute on function tests.serve(timestamptz) to authenticated;

-- A : cas nominal, idempotence, entrées invalides ; B : gels consommés ;
-- C : série perdue ; D : quiz de la veille possible (5 h avant) ;
-- E : plafond de 3 jours sur 7 ; F : jour ancien hors plafond ;
-- G : jour déjà validé par un quiz servi ; H : nouveau joueur.
-- I à M (fin du fichier) : heure fixée via private.validate_offline_day.
insert into auth.users (id, aud, role)
values
  ('00000000-0000-0000-0000-0000000010a1', 'authenticated', 'authenticated'),
  ('00000000-0000-0000-0000-0000000010b1', 'authenticated', 'authenticated'),
  ('00000000-0000-0000-0000-0000000010c1', 'authenticated', 'authenticated'),
  ('00000000-0000-0000-0000-0000000010d1', 'authenticated', 'authenticated'),
  ('00000000-0000-0000-0000-0000000010e1', 'authenticated', 'authenticated'),
  ('00000000-0000-0000-0000-0000000010f1', 'authenticated', 'authenticated'),
  ('00000000-0000-0000-0000-000000001011', 'authenticated', 'authenticated'),
  ('00000000-0000-0000-0000-000000001021', 'authenticated', 'authenticated');

update public.profiles
   set xp = 500, streak = 5, freezes = 1,
       last_played_day = tests.paris_day() - 1,
       quiz_day = tests.paris_day() - 1, quiz_count = 2,
       last_quiz_at = now() - interval '20 hours'
 where id = '00000000-0000-0000-0000-0000000010a1';
update public.profiles
   set xp = 300, streak = 10, freezes = 2,
       last_played_day = tests.paris_day() - 3,
       last_quiz_at = now() - interval '3 days'
 where id = '00000000-0000-0000-0000-0000000010b1';
update public.profiles
   set xp = 300, streak = 10, freezes = 2,
       last_played_day = tests.paris_day() - 4,
       last_quiz_at = now() - interval '4 days'
 where id = '00000000-0000-0000-0000-0000000010c1';
update public.profiles
   set streak = 4, freezes = 0,
       last_played_day = tests.paris_day(now() - interval '5 hours') - 1,
       last_quiz_at = now() - interval '1 day 5 hours'
 where id = '00000000-0000-0000-0000-0000000010d1';
update public.profiles
   set streak = 3, freezes = 0, last_played_day = tests.paris_day() - 1
 where id = '00000000-0000-0000-0000-0000000010e1';
insert into public.offline_days (user_id, day, played_at)
select '00000000-0000-0000-0000-0000000010e1', tests.paris_day() - d, now() - make_interval(days => d)
from generate_series(1, 3) d;
update public.profiles
   set streak = 3, freezes = 0, last_played_day = tests.paris_day() - 1
 where id = '00000000-0000-0000-0000-0000000010f1';
insert into public.offline_days (user_id, day, played_at)
select '00000000-0000-0000-0000-0000000010f1', tests.paris_day() - d, now() - make_interval(days => d)
from unnest(array[2, 3, 7]) d;
update public.profiles
   set xp = 120, streak = 8, freezes = 1,
       last_played_day = tests.paris_day(),
       quiz_day = tests.paris_day(), quiz_count = 2,
       last_quiz_at = now() - interval '1 minute'
 where id = '00000000-0000-0000-0000-000000001011';

-- Droits ---------------------------------------------------------------------

select ok(
  not has_function_privilege('anon', 'public.validate_offline_day(timestamptz)', 'execute')
  and not has_function_privilege('public', 'public.validate_offline_day(timestamptz)', 'execute'),
  'anon et public ne peuvent pas appeler validate_offline_day'
);

select ok(
  has_function_privilege('authenticated', 'public.validate_offline_day(timestamptz)', 'execute'),
  'authenticated peut appeler validate_offline_day'
);

select is(
  (select prosecdef and proconfig @> array['search_path=""']
   from pg_proc where oid = 'public.validate_offline_day(timestamptz)'::regprocedure),
  true,
  'validate_offline_day : security definer, search_path vide'
);

select ok(
  (select relrowsecurity from pg_class where oid = 'public.offline_days'::regclass),
  'offline_days : RLS activé'
);

select ok(
  not has_table_privilege('anon', 'public.offline_days', 'select,insert,update,delete,truncate')
  and not has_table_privilege('authenticated', 'public.offline_days', 'select,insert,update,delete,truncate'),
  'offline_days : aucun privilège client'
);

select is(
  (select count(*)::integer from pg_class c join pg_namespace n on n.oid = c.relnamespace
   where n.nspname = 'public' and c.relkind = 'r' and not c.relrowsecurity),
  0,
  'aucune table publique sans RLS'
);

-- anon -----------------------------------------------------------------------

set local role anon;
set local "request.jwt.claims" to '{"role":"anon"}';

select throws_ok(
  $$select public.validate_offline_day(now())$$,
  '42501', null,
  'anon : appel refusé'
);

reset role;

-- authenticated sans uid -------------------------------------------------------

set local role authenticated;
set local "request.jwt.claims" to '{"role":"authenticated"}';

select throws_ok(
  $$select public.validate_offline_day(now())$$,
  '42501', 'non authentifié',
  'sans uid : refusé'
);

-- A : cas nominal ----------------------------------------------------------------

set local "request.jwt.claims" to '{"sub":"00000000-0000-0000-0000-0000000010a1","role":"authenticated"}';

select throws_ok(
  $$select public.validate_offline_day(null)$$,
  '22023', null,
  'played_at manquant : refusé'
);

select throws_ok(
  $$select public.validate_offline_day(now() + interval '1 hour')$$,
  '22023', 'jour invalide : quiz dans le futur',
  'played_at dans le futur : refusé'
);

select throws_ok(
  $$select public.validate_offline_day(now() - interval '6 hours 1 minute')$$,
  '22023', 'jour invalide : quiz joué il y a plus de 6 h',
  'played_at de plus de 6 h : refusé'
);

select throws_ok(
  $$select public.validate_offline_day(now() - interval '3 days')$$,
  '22023', null,
  'quiz d''il y a 3 jours : refusé'
);

select is(
  (select streak from public.profiles where id = '00000000-0000-0000-0000-0000000010a1'),
  5,
  'entrées refusées : série inchangée'
);

select is(
  public.validate_offline_day(now()) - 'profile',
  jsonb_build_object('validated', true, 'reason', null, 'day', tests.paris_day()),
  'quiz hors ligne aujourd''hui : jour validé'
);

select is(
  (select jsonb_build_object('xp', xp, 'streak', streak, 'freezes', freezes,
                             'last_played_day', last_played_day,
                             'quiz_day', quiz_day, 'quiz_count', quiz_count)
   from public.profiles where id = '00000000-0000-0000-0000-0000000010a1'),
  jsonb_build_object('xp', 500, 'streak', 6, 'freezes', 1,
                     'last_played_day', tests.paris_day(),
                     'quiz_day', tests.paris_day(), 'quiz_count', 1),
  'série +1, compteur du jour à 1, XP et gels inchangés'
);

select is(
  (select last_quiz_at from public.profiles where id = '00000000-0000-0000-0000-0000000010a1'),
  now(),
  'last_quiz_at avancé à l''heure du quiz'
);

select is(
  (select count(*)::integer from public.quiz_results
   where user_id = '00000000-0000-0000-0000-0000000010a1'),
  0,
  'aucune ligne dans quiz_results (hors classement)'
);

select is(
  public.weekly_leaderboard() -> 'me' -> 'rank',
  'null'::jsonb,
  'classement : joueur non classé (aucune XP)'
);

select is(
  public.validate_offline_day(now() - interval '1 minute') - 'profile' - 'day',
  '{"validated": false, "reason": "already_validated"}'::jsonb,
  'second appel le même jour : refus propre (idempotent)'
);

select is(
  public.validate_offline_day(now() + interval '1 minute') - 'profile' - 'day',
  '{"validated": false, "reason": "already_validated"}'::jsonb,
  'horloge un peu en avance (< 5 min) : acceptée, jour déjà validé'
);

select is(
  (public.validate_offline_day(now()) -> 'profile') - 'last_quiz_at' - 'daily_goal',
  jsonb_build_object('xp', 500, 'streak', 6, 'freezes', 1,
                     'last_played_day', tests.paris_day(),
                     'quiz_day', tests.paris_day(), 'quiz_count', 1),
  'appel répété : profil renvoyé inchangé (pas de double comptage)'
);

select is(
  (public.validate_offline_day(now()) -> 'profile' ->> 'daily_goal')::integer,
  2,
  'profil renvoyé : objectif du jour compris'
);

reset role;

select is(
  (select count(*)::integer from public.offline_days
   where user_id = '00000000-0000-0000-0000-0000000010a1'),
  1,
  'un seul jour enregistré malgré les appels répétés'
);

-- B : jours manqués couverts par les gels --------------------------------------

set local role authenticated;
set local "request.jwt.claims" to '{"sub":"00000000-0000-0000-0000-0000000010b1","role":"authenticated"}';

select is(
  (public.validate_offline_day(now()) -> 'profile') - 'last_quiz_at' - 'daily_goal' - 'quiz_day' - 'quiz_count',
  jsonb_build_object('xp', 300, 'streak', 11, 'freezes', 0,
                     'last_played_day', tests.paris_day()),
  '2 jours manqués, 2 gels : gels consommés, série +1, aucun gel gagné'
);

-- C : série perdue --------------------------------------------------------------

set local "request.jwt.claims" to '{"sub":"00000000-0000-0000-0000-0000000010c1","role":"authenticated"}';

select is(
  (public.validate_offline_day(now()) -> 'profile') - 'last_quiz_at' - 'daily_goal' - 'quiz_day' - 'quiz_count',
  jsonb_build_object('xp', 300, 'streak', 1, 'freezes', 2,
                     'last_played_day', tests.paris_day()),
  '3 jours manqués, 2 gels : série repart à 1, gels conservés'
);

-- D : quiz 5 h avant (la veille si avant 5 h à Paris) -----------------------------

set local "request.jwt.claims" to '{"sub":"00000000-0000-0000-0000-0000000010d1","role":"authenticated"}';

select ok(
  tests.paris_day(now() - interval '5 hours') between tests.paris_day() - 1 and tests.paris_day(),
  'quiz de 5 h : aujourd''hui ou la veille'
);

select is(
  public.validate_offline_day(now() - interval '5 hours') - 'profile',
  jsonb_build_object('validated', true, 'reason', null,
                     'day', tests.paris_day(now() - interval '5 hours')),
  'jour validé = jour (Paris) du quiz, pas celui de l''appel'
);

select is(
  (select jsonb_build_object('streak', streak, 'last_played_day', last_played_day)
   from public.profiles where id = '00000000-0000-0000-0000-0000000010d1'),
  jsonb_build_object('streak', 5,
                     'last_played_day', tests.paris_day(now() - interval '5 hours')),
  'quiz de 5 h : série +1 pour son jour'
);

select is(
  public.validate_offline_day(now()) ->> 'validated',
  (tests.paris_day(now() - interval '5 hours') < tests.paris_day())::text,
  'puis aujourd''hui : validé seulement si le premier était la veille'
);

select is(
  (select streak from public.profiles where id = '00000000-0000-0000-0000-0000000010d1'),
  5 + (tests.paris_day() - tests.paris_day(now() - interval '5 hours')),
  'veille puis aujourd''hui : série suivie, sans saut'
);

-- E : plafond de 3 jours hors ligne sur 7 ------------------------------------------

set local "request.jwt.claims" to '{"sub":"00000000-0000-0000-0000-0000000010e1","role":"authenticated"}';

select is(
  public.validate_offline_day(now()) - 'profile' - 'day',
  '{"validated": false, "reason": "limit"}'::jsonb,
  '3 jours déjà validés hors ligne cette semaine : refus propre'
);

select is(
  (select jsonb_build_object('streak', streak, 'last_played_day', last_played_day)
   from public.profiles where id = '00000000-0000-0000-0000-0000000010e1'),
  jsonb_build_object('streak', 3, 'last_played_day', tests.paris_day() - 1),
  'plafond atteint : série inchangée'
);

-- F : jour validé il y a 7 jours hors de la fenêtre --------------------------------

set local "request.jwt.claims" to '{"sub":"00000000-0000-0000-0000-0000000010f1","role":"authenticated"}';

select is(
  public.validate_offline_day(now()) ->> 'validated',
  'true',
  '2 jours dans la fenêtre de 7 jours (le 3e plus ancien) : validé'
);

select is(
  public.validate_offline_day(now()) - 'profile' - 'day',
  '{"validated": false, "reason": "already_validated"}'::jsonb,
  'puis même jour : déjà validé (avant le plafond)'
);

-- G : jour déjà validé par un quiz servi -------------------------------------------

set local "request.jwt.claims" to '{"sub":"00000000-0000-0000-0000-000000001011","role":"authenticated"}';

select is(
  public.validate_offline_day(now() - interval '2 minutes') - 'profile' - 'day',
  '{"validated": false, "reason": "already_validated"}'::jsonb,
  'jour déjà validé par submit_quiz : refus propre'
);

select is(
  (public.validate_offline_day(now()) -> 'profile') - 'daily_goal' - 'last_quiz_at',
  jsonb_build_object('xp', 120, 'streak', 8, 'freezes', 1,
                     'last_played_day', tests.paris_day(),
                     'quiz_day', tests.paris_day(), 'quiz_count', 2),
  'quiz servi déjà compté : pas de double comptage'
);

select is(
  (select last_quiz_at from public.profiles where id = '00000000-0000-0000-0000-000000001011'),
  now() - interval '1 minute',
  'refus : last_quiz_at inchangé'
);

-- H : nouveau joueur --------------------------------------------------------------

set local "request.jwt.claims" to '{"sub":"00000000-0000-0000-0000-000000001021","role":"authenticated"}';

select is(
  (public.validate_offline_day(now()) -> 'profile') - 'daily_goal' - 'last_quiz_at',
  jsonb_build_object('xp', 0, 'streak', 1, 'freezes', 0,
                     'last_played_day', tests.paris_day(),
                     'quiz_day', tests.paris_day(), 'quiz_count', 1),
  'nouveau joueur : série à 1, aucune XP'
);

-- Accès direct et effets de bord ----------------------------------------------------

select throws_ok(
  $$select * from public.offline_days$$,
  '42501', null,
  'authenticated ne lit pas offline_days'
);

select throws_ok(
  $$insert into public.offline_days (user_id, day, played_at)
    values ('00000000-0000-0000-0000-000000001021', current_date + 1, now())$$,
  '42501', null,
  'INSERT direct dans offline_days refusé'
);

select throws_ok(
  $$update public.profiles set streak = 99 where id = '00000000-0000-0000-0000-000000001021'$$,
  '42501', null,
  'UPDATE direct de la série refusé'
);

reset role;

select is(
  (select count(*)::integer from public.quiz_results
   where user_id in ('00000000-0000-0000-0000-0000000010a1', '00000000-0000-0000-0000-0000000010b1',
                     '00000000-0000-0000-0000-0000000010c1', '00000000-0000-0000-0000-0000000010d1',
                     '00000000-0000-0000-0000-0000000010e1', '00000000-0000-0000-0000-0000000010f1',
                     '00000000-0000-0000-0000-000000001011', '00000000-0000-0000-0000-000000001021')),
  0,
  'aucun quiz_results créé par validate_offline_day'
);

select is(
  (select sum(xp)::integer from public.profiles
   where id in ('00000000-0000-0000-0000-0000000010a1', '00000000-0000-0000-0000-0000000010b1',
                '00000000-0000-0000-0000-0000000010c1', '00000000-0000-0000-0000-0000000010d1',
                '00000000-0000-0000-0000-0000000010e1', '00000000-0000-0000-0000-0000000010f1',
                '00000000-0000-0000-0000-000000001011', '00000000-0000-0000-0000-000000001021')),
  500 + 300 + 300 + 120,
  'aucune XP gagnée'
);

select is(
  (select count(*)::integer from public.offline_days
   where user_id = '00000000-0000-0000-0000-0000000010e1'),
  3,
  'plafond : aucun jour ajouté'
);

-- Purge des jours anciens (plus de 14 jours) au prochain jour validé.
insert into public.offline_days (user_id, day, played_at)
values ('00000000-0000-0000-0000-0000000010b1', tests.paris_day() - 30, now() - interval '30 days');
update public.profiles
   set last_played_day = tests.paris_day() - 1
 where id = '00000000-0000-0000-0000-0000000010b1';
delete from public.offline_days
 where user_id = '00000000-0000-0000-0000-0000000010b1' and day = tests.paris_day();

set local role authenticated;
set local "request.jwt.claims" to '{"sub":"00000000-0000-0000-0000-0000000010b1","role":"authenticated"}';
select is(
  public.validate_offline_day(now()) ->> 'validated',
  'true',
  'B : nouveau jour validé'
);
reset role;

select is(
  (select array_agg(day order by day) from public.offline_days
   where user_id = '00000000-0000-0000-0000-0000000010b1'),
  array[tests.paris_day()],
  'jours de plus de 14 jours purgés'
);

-- Interaction avec submit_quiz : un quiz servi le même jour compte en plus
-- (compteur, XP), sans revalider la série.
set local role authenticated;
set local "request.jwt.claims" to '{"sub":"00000000-0000-0000-0000-0000000010a1","role":"authenticated"}';

select is(
  (public.submit_quiz(tests.serve(now())) -> 'profile') - 'daily_goal' - 'last_quiz_at' - 'xp',
  jsonb_build_object('streak', 6, 'freezes', 1,
                     'last_played_day', tests.paris_day(),
                     'quiz_day', tests.paris_day(), 'quiz_count', 2),
  'quiz servi après le jour hors ligne : compteur 2, série non recomptée'
);

reset role;

-- Heure fixée ---------------------------------------------------------------------
--
-- private.validate_offline_day(uid, played_at, as_of) : même logique que la
-- RPC, as_of remplaçant now(). Aucun test ci-dessous ne dépend de l'heure
-- réelle. Référence : lundi 15 juin 2026, 5 h 30 à Paris (D = 2026-06-15).
-- I : veille (minuit − 1 min) ; J : plafond évalué pour la veille ;
-- K : bords de la fenêtre (J-6, J-5, J-4) ; L : jour hors ligne aussi validé
-- par un quiz servi, hors plafond ; M : last_quiz_at avancé (heure réelle).

reset role;

select is(
  (select coalesce(array_agg(p.oid::regprocedure::text order by p.oid::regprocedure::text), '{}')
     from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.prosecdef
      and has_function_privilege('anon', p.oid, 'execute')),
  '{}'::text[],
  'aucune fonction security definer de public exécutable par anon'
);

select ok(
  not has_function_privilege('anon', 'private.validate_offline_day(uuid, timestamptz, timestamptz)', 'execute')
  and not has_function_privilege('authenticated', 'private.validate_offline_day(uuid, timestamptz, timestamptz)', 'execute'),
  'private.validate_offline_day : non exécutable par anon ni authenticated'
);

select ok(
  not has_schema_privilege('anon', 'private', 'usage')
  and not has_schema_privilege('authenticated', 'private', 'usage'),
  'schéma private : aucun usage client'
);

insert into auth.users (id, aud, role)
values
  ('00000000-0000-0000-0000-000000001031', 'authenticated', 'authenticated'),
  ('00000000-0000-0000-0000-000000001041', 'authenticated', 'authenticated'),
  ('00000000-0000-0000-0000-000000001051', 'authenticated', 'authenticated'),
  ('00000000-0000-0000-0000-000000001061', 'authenticated', 'authenticated'),
  ('00000000-0000-0000-0000-000000001071', 'authenticated', 'authenticated');

update public.profiles
   set streak = 4, freezes = 0, last_played_day = '2026-06-13'
 where id = '00000000-0000-0000-0000-000000001031';
update public.profiles
   set streak = 3, freezes = 0, last_played_day = '2026-06-13'
 where id = '00000000-0000-0000-0000-000000001041';
insert into public.offline_days (user_id, day, played_at)
select '00000000-0000-0000-0000-000000001041', d::date, d + interval '12 hours'
from unnest(array['2026-06-08', '2026-06-09', '2026-06-10']::timestamptz[]) d;
update public.profiles
   set streak = 3, freezes = 0, last_played_day = '2026-06-14'
 where id = '00000000-0000-0000-0000-000000001051';
insert into public.offline_days (user_id, day, played_at)
select '00000000-0000-0000-0000-000000001051', d::date, d + interval '12 hours'
from unnest(array['2026-06-09', '2026-06-10', '2026-06-11']::timestamptz[]) d;
update public.profiles
   set streak = 3, freezes = 0, last_played_day = '2026-06-14'
 where id = '00000000-0000-0000-0000-000000001061';
insert into public.offline_days (user_id, day, played_at)
select '00000000-0000-0000-0000-000000001061', d::date, d + interval '12 hours'
from unnest(array['2026-06-12', '2026-06-13', '2026-06-14']::timestamptz[]) d;
insert into public.quiz_results (id, user_id, day, played_at, score, total, xp, xp_raw)
values (gen_random_uuid(), '00000000-0000-0000-0000-000000001061', '2026-06-13',
        '2026-06-13 20:00:00+02', 10, 10, 0, 0);

-- I : veille, quiz fini à minuit − 1 min, envoyé à 5 h 30 ------------------------

select throws_ok(
  $$select private.validate_offline_day('00000000-0000-0000-0000-000000001031',
      '2026-06-14 23:59:00+02', '2026-06-15 06:00:00+02')$$,
  '22023', 'jour invalide : quiz joué il y a plus de 6 h',
  'veille : minuit − 1 min envoyé à 6 h 00 (6 h 01 plus tard) : refusé'
);

select is(
  private.validate_offline_day('00000000-0000-0000-0000-000000001031',
    '2026-06-14 23:59:00+02', '2026-06-15 05:30:00+02') - 'profile',
  '{"validated": true, "reason": null, "day": "2026-06-14"}'::jsonb,
  'veille : minuit − 1 min envoyé à 5 h 30 : jour de la veille validé'
);

select is(
  (select jsonb_build_object('streak', streak, 'last_played_day', last_played_day,
                             'quiz_day', quiz_day, 'quiz_count', quiz_count,
                             'last_quiz_at', last_quiz_at)
   from public.profiles where id = '00000000-0000-0000-0000-000000001031'),
  jsonb_build_object('streak', 5, 'last_played_day', '2026-06-14',
                     'quiz_day', '2026-06-14', 'quiz_count', 1,
                     'last_quiz_at', '2026-06-14 23:59:00+02'::timestamptz),
  'veille : série +1, compteur et last_quiz_at du jour de la veille'
);

select is(
  private.validate_offline_day('00000000-0000-0000-0000-000000001031',
    '2026-06-15 05:20:00+02', '2026-06-15 05:30:00+02') - 'profile',
  '{"validated": true, "reason": null, "day": "2026-06-15"}'::jsonb,
  'veille puis aujourd''hui : validé (série 6)'
);

select is(
  private.validate_offline_day('00000000-0000-0000-0000-000000001031',
    '2026-06-14 23:58:00+02', '2026-06-15 05:30:00+02') - 'profile' - 'day',
  '{"validated": false, "reason": "already_validated"}'::jsonb,
  'veille envoyée après le jour même : refus propre (passé non réécrit)'
);

-- J : plafond évalué pour la veille (fenêtre du 8 au 14 juin) -------------------

select is(
  private.validate_offline_day('00000000-0000-0000-0000-000000001041',
    '2026-06-14 23:59:00+02', '2026-06-15 05:30:00+02') - 'profile',
  '{"validated": false, "reason": "limit", "day": "2026-06-14"}'::jsonb,
  'veille : jours hors ligne J-7 à J-5 dans sa fenêtre : plafond'
);

select is(
  private.validate_offline_day('00000000-0000-0000-0000-000000001041',
    '2026-06-15 05:20:00+02', '2026-06-15 05:30:00+02') ->> 'validated',
  'true',
  'aujourd''hui : J-7 sort de la fenêtre, 2 jours comptés : validé'
);

-- K : bords de la fenêtre (J-6, J-5, J-4 comptent) -------------------------------

select is(
  private.validate_offline_day('00000000-0000-0000-0000-000000001051',
    '2026-06-15 05:20:00+02', '2026-06-15 05:30:00+02') - 'profile' - 'day',
  '{"validated": false, "reason": "limit"}'::jsonb,
  'jours hors ligne à J-6, J-5, J-4 : plafond'
);

-- L : jour hors ligne puis validé par un quiz servi : hors plafond ---------------

select is(
  private.validate_offline_day('00000000-0000-0000-0000-000000001061',
    '2026-06-15 05:20:00+02', '2026-06-15 05:30:00+02') ->> 'validated',
  'true',
  '3 jours hors ligne dont 1 aussi validé par un quiz servi : 2 comptés, validé'
);

-- M : last_quiz_at avancé (heure réelle, submit_quiz utilise now()) --------------
--
-- Jour validé hors ligne à now(), puis quiz servi dont la dernière réponse
-- précède (10 min avant) : submit_quiz le date de last_quiz_at, donc
-- d'aujourd'hui, même si sa dernière réponse tombait la veille.

set local role authenticated;
set local "request.jwt.claims" to '{"sub":"00000000-0000-0000-0000-000000001071","role":"authenticated"}';

do $$ begin
  perform public.validate_offline_day(now());
  perform public.submit_quiz(tests.serve(now() - interval '10 minutes'));
end $$;

reset role;

select is(
  (select jsonb_build_object('day', day, 'played_at', played_at)
   from public.quiz_results where user_id = '00000000-0000-0000-0000-000000001071'),
  jsonb_build_object('day', tests.paris_day(), 'played_at', now()),
  'quiz servi antérieur au jour hors ligne : daté de last_quiz_at (aujourd''hui)'
);

select is(
  (select jsonb_build_object('streak', streak, 'last_played_day', last_played_day,
                             'quiz_count', quiz_count, 'last_quiz_at', last_quiz_at)
   from public.profiles where id = '00000000-0000-0000-0000-000000001071'),
  jsonb_build_object('streak', 1, 'last_played_day', tests.paris_day(),
                     'quiz_count', 2, 'last_quiz_at', now()),
  'quiz servi après le jour hors ligne : série non recomptée, compteur 2'
);

select finish();
rollback;
