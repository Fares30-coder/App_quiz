-- Tests pgTAP de delete_account() : droits, compte et données du joueur
-- supprimés (cascade), signalement gardé sans user_id, autre joueur intact.
-- Lancer en local : `supabase start` puis `supabase test db`.
begin;
create extension if not exists pgtap with schema extensions;

select plan(12);

-- Données de test (propriétaire) -------------------------------------------

insert into public.questions
  (id, category, difficulty, question, answers, correct_index, explanation)
values ('da-1', 'divers', 1, 'Question', array['a', 'b', 'c', 'd'], 0, 'Explication');

-- Joueur A (supprime son compte), joueur B (témoin).
insert into auth.users (id, aud, role)
values ('00000000-0000-0000-0000-000000000da1', 'authenticated', 'authenticated'),
       ('00000000-0000-0000-0000-000000000db1', 'authenticated', 'authenticated');

insert into public.quiz_sessions (id, user_id, mode, expires_at)
select ('00000000-0000-0000-0000-0000000000' || s)::uuid, u::uuid, 'mix', now() + interval '30 minutes'
from (values ('a1', '00000000-0000-0000-0000-000000000da1'),
             ('b1', '00000000-0000-0000-0000-000000000db1')) v(s, u);

insert into public.quiz_session_questions (quiz_id, position, question_id, answer_order)
select ('00000000-0000-0000-0000-0000000000' || s)::uuid, 1, 'da-1', array[0, 1, 2, 3]
from (values ('a1'), ('b1')) v(s);

insert into public.quiz_results (id, user_id, day, played_at, score, total, xp, xp_raw)
select gen_random_uuid(), u::uuid, current_date, now(), 5, 10, 50, 50
from (values ('00000000-0000-0000-0000-000000000da1'),
             ('00000000-0000-0000-0000-000000000db1')) v(u);

insert into public.offline_days (user_id, day, played_at)
values ('00000000-0000-0000-0000-000000000da1', current_date, now()),
       ('00000000-0000-0000-0000-000000000db1', current_date, now());

insert into public.question_reports (question_id, user_id, reason)
values ('da-1', '00000000-0000-0000-0000-000000000da1', 'faute');

-- Droits -----------------------------------------------------------------------

select ok(
  not has_function_privilege('anon', 'public.delete_account()', 'execute'),
  'anon : delete_account() interdit'
);

select ok(
  has_function_privilege('authenticated', 'public.delete_account()', 'execute'),
  'authenticated : delete_account() autorisé'
);

set local role authenticated;
set local "request.jwt.claims" to '{"role":"authenticated"}';
select throws_ok(
  'select public.delete_account()',
  '42501', 'non authentifié',
  'sans sub : refusé'
);

-- Suppression par A -------------------------------------------------------------

set local "request.jwt.claims" to '{"sub":"00000000-0000-0000-0000-000000000da1","role":"authenticated"}';
select lives_ok('select public.delete_account()', 'A supprime son compte');
reset role;

select is((select count(*)::int from auth.users
            where id = '00000000-0000-0000-0000-000000000da1'), 0,
          'A : utilisateur supprimé');
select is((select count(*)::int from public.profiles
            where id = '00000000-0000-0000-0000-000000000da1'), 0,
          'A : profil supprimé');
select is((select count(*)::int from public.quiz_sessions
            where user_id = '00000000-0000-0000-0000-000000000da1'), 0,
          'A : sessions supprimées');
select is((select count(*)::int from public.quiz_session_questions
            where quiz_id = '00000000-0000-0000-0000-0000000000a1'), 0,
          'A : questions de session supprimées');
select is((select count(*)::int from public.quiz_results
            where user_id = '00000000-0000-0000-0000-000000000da1'), 0,
          'A : résultats supprimés');
select is((select count(*)::int from public.offline_days
            where user_id = '00000000-0000-0000-0000-000000000da1'), 0,
          'A : journées hors ligne supprimées');
select is((select count(*)::int from public.question_reports
            where question_id = 'da-1' and user_id is null), 1,
          'signalement de A gardé, sans user_id');

select is(
  (select count(*)::int from auth.users u
     join public.profiles p on p.id = u.id
    where u.id = '00000000-0000-0000-0000-000000000db1'
      and exists (select 1 from public.quiz_results r where r.user_id = u.id)
      and exists (select 1 from public.offline_days d where d.user_id = u.id)
      and exists (select 1 from public.quiz_sessions s where s.user_id = u.id)),
  1,
  'B : compte et données intacts'
);

select * from finish();
rollback;
