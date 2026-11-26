-- Tests pgTAP du signalement de questions : report_question(quiz_id,
-- position, motif), question retrouvée côté serveur et jamais renvoyée,
-- doublon sans effet, plafond quotidien, table illisible par les clients.
-- Lancer en local : `supabase start` puis `supabase test db`.
begin;
create extension if not exists pgtap with schema extensions;

select plan(31);

-- Données de test (propriétaire) -------------------------------------------

delete from public.question_reports;
delete from public.quiz_session_questions;
delete from public.quiz_sessions;
delete from public.daily_challenges;
delete from public.questions;

-- 30 questions « divers » (10 par quiz, 20 de plus pour le plafond).
insert into public.questions
  (id, category, difficulty, question, answers, correct_index, explanation)
select 'qr-' || lpad(i::text, 2, '0'), 'divers', 1, 'Question ' || i,
       array['bonne', 'b', 'c', 'd'], 0, 'Explication ' || i
from generate_series(1, 30) i;

-- Joueur A (signale), joueur B (autre joueur), joueur C (plafond).
insert into auth.users (id, aud, role)
values ('00000000-0000-0000-0000-0000000005a1', 'authenticated', 'authenticated'),
       ('00000000-0000-0000-0000-0000000005b1', 'authenticated', 'authenticated'),
       ('00000000-0000-0000-0000-0000000005c1', 'authenticated', 'authenticated');

-- Schéma et droits -------------------------------------------------------------

select ok(
  (select relrowsecurity from pg_class where oid = 'public.question_reports'::regclass),
  'question_reports : RLS activée'
);

select is(
  (select count(*)::int from pg_policies
    where schemaname = 'public' and tablename = 'question_reports'),
  0,
  'question_reports : aucune policy'
);

select ok(
  not has_table_privilege(r, 'public.question_reports',
                          'select,insert,update,delete,truncate'),
  format('%s : aucun privilège sur question_reports', r)
)
from unnest(array['anon', 'authenticated']) r;

select ok(
  has_function_privilege('authenticated',
    'public.report_question(uuid, integer, text)', 'execute')
  and not has_function_privilege('anon',
    'public.report_question(uuid, integer, text)', 'execute')
  and not has_function_privilege('public',
    'public.report_question(uuid, integer, text)', 'execute'),
  'report_question : authenticated seulement'
);

select ok(
  (select prosecdef and proconfig @> array['search_path=""']
     from pg_proc
    where oid = 'public.report_question(uuid, integer, text)'::regprocedure),
  'report_question : security definer, search_path vide'
);

-- Joueur A : quiz commencé, question 1 répondue, question 2 servie sans
-- réponse ----------------------------------------------------------------------

set local role authenticated;
set local "request.jwt.claims" to '{"sub":"00000000-0000-0000-0000-0000000005a1","role":"authenticated"}';

do $$
declare
  s jsonb := public.start_quiz('mix');
begin
  perform set_config('t.quiz', s ->> 'quiz_id', true);
  perform public.answer_question((s ->> 'quiz_id')::uuid, 1, 0, 2000);
  perform public.next_question((s ->> 'quiz_id')::uuid);
end $$;

-- Signalement accepté -------------------------------------------------------------

select is(
  public.report_question(current_setting('t.quiz')::uuid, 1, 'fausse'),
  '{"reported": true}'::jsonb,
  'question répondue : signalement accepté'
);

select ok(
  position('qr-' in public.report_question(
    current_setting('t.quiz')::uuid, 1, 'fausse')::text) = 0
  and not (public.report_question(
    current_setting('t.quiz')::uuid, 1, 'fausse') ? 'question_id'),
  'report_question : aucun identifiant de question renvoyé'
);

reset role;

select is(
  (select row(r.question_id, r.user_id, r.reason)::text
     from public.question_reports r),
  (select row(sq.question_id, '00000000-0000-0000-0000-0000000005a1'::uuid,
              'fausse')::text
     from public.quiz_session_questions sq
    where sq.quiz_id = current_setting('t.quiz')::uuid and sq.position = 1),
  'ligne enregistrée : question retrouvée par le serveur, joueur, motif'
);

-- Doublon --------------------------------------------------------------------------

set local role authenticated;

select is(
  public.report_question(current_setting('t.quiz')::uuid, 1, 'autre'),
  '{"reported": true}'::jsonb,
  'doublon (autre motif) : même réponse, sans erreur'
);

reset role;

select is(
  (select count(*)::int from public.question_reports),
  1,
  'doublon : aucune nouvelle ligne'
);

select is(
  (select reason from public.question_reports),
  'fausse',
  'doublon : motif d''origine gardé'
);

-- Refus : position non servie, sans réponse, hors du quiz ---------------------------

set local role authenticated;

select throws_ok(
  format($$select public.report_question(%L, 2, 'fausse')$$,
         current_setting('t.quiz')),
  '22023', 'question introuvable',
  'question servie mais sans réponse : refusée'
);

select throws_ok(
  format($$select public.report_question(%L, 5, 'fausse')$$,
         current_setting('t.quiz')),
  '22023', 'question introuvable',
  'question pas encore servie : refusée'
);

select throws_ok(
  format($$select public.report_question(%L, 11, 'fausse')$$,
         current_setting('t.quiz')),
  '22023', 'question introuvable',
  'position hors du quiz : refusée'
);

select throws_ok(
  $$select public.report_question(gen_random_uuid(), 1, 'fausse')$$,
  '22023', 'question introuvable',
  'quiz inconnu : refusé'
);

-- Motif invalide ---------------------------------------------------------------------

select throws_ok(
  format($$select public.report_question(%L, 1, 'nul')$$,
         current_setting('t.quiz')),
  '22023', 'motif invalide',
  'motif hors liste : refusé'
);

select throws_ok(
  format($$select public.report_question(%L, 1, null)$$,
         current_setting('t.quiz')),
  '22023', 'motif invalide',
  'motif absent : refusé'
);

-- Session d'un autre joueur -------------------------------------------------------------

set local "request.jwt.claims" to '{"sub":"00000000-0000-0000-0000-0000000005b1","role":"authenticated"}';

select throws_ok(
  format($$select public.report_question(%L, 1, 'ambigue')$$,
         current_setting('t.quiz')),
  '22023', 'question introuvable',
  'quiz d''un autre joueur : refusé (même erreur)'
);

-- Accès direct à la table : refusé -----------------------------------------------------

select throws_ok(
  $$select * from public.question_reports$$,
  '42501', null,
  'authenticated : lecture directe refusée'
);

select throws_ok(
  $$insert into public.question_reports (question_id, user_id, reason)
    values ('qr-01', '00000000-0000-0000-0000-0000000005b1', 'autre')$$,
  '42501', null,
  'authenticated : écriture directe refusée'
);

-- Sans compte ---------------------------------------------------------------------------

set local "request.jwt.claims" to '{"role":"authenticated"}';

select throws_ok(
  format($$select public.report_question(%L, 1, 'fausse')$$,
         current_setting('t.quiz')),
  '42501', 'non authentifié',
  'sans uid : refusé'
);

set local role anon;
set local "request.jwt.claims" to '{"role":"anon"}';

select throws_ok(
  format($$select public.report_question(%L, 1, 'fausse')$$,
         current_setting('t.quiz')),
  '42501', null,
  'anon : report_question refusée'
);

select throws_ok(
  $$select * from public.question_reports$$,
  '42501', null,
  'anon : lecture directe refusée'
);

select throws_ok(
  $$insert into public.question_reports (question_id, reason)
    values ('qr-01', 'autre')$$,
  '42501', null,
  'anon : écriture directe refusée'
);

-- Plafond : 20 signalements par joueur et par jour (Europe/Paris) ------------------------

reset role;

-- Joueur C : quiz joué (question 1 répondue), puis 20 signalements déjà
-- faits aujourd'hui (questions hors de ce quiz) et 5 hier (non comptés).
set local role authenticated;
set local "request.jwt.claims" to '{"sub":"00000000-0000-0000-0000-0000000005c1","role":"authenticated"}';

do $$
declare
  s jsonb := public.start_quiz('mix');
begin
  perform set_config('t.quiz_c', s ->> 'quiz_id', true);
  perform public.answer_question((s ->> 'quiz_id')::uuid, 1, 0, 2000);
end $$;

reset role;

create temporary table t_other on commit drop as
select q.id
  from public.questions q
 where q.id not in (select sq.question_id from public.quiz_session_questions sq
                     where sq.quiz_id = current_setting('t.quiz_c')::uuid)
 order by q.id;

insert into public.question_reports (question_id, user_id, reason, created_at)
select t.id, '00000000-0000-0000-0000-0000000005c1', 'autre',
       case when n <= 19 then now() else now() - interval '2 days' end
  from (select id, row_number() over (order by id) n from t_other) t
 where n <= 20;

set local role authenticated;

select is(
  public.report_question(current_setting('t.quiz_c')::uuid, 1, 'faute'),
  '{"reported": true}'::jsonb,
  '19 signalements aujourd''hui (+1 avant-hier) : 20e accepté'
);

reset role;

update public.question_reports
   set created_at = now()
 where user_id = '00000000-0000-0000-0000-0000000005c1';

set local role authenticated;

select is(
  public.report_question(current_setting('t.quiz_c')::uuid, 1, 'fausse'),
  '{"reported": true}'::jsonb,
  'plafond atteint : un doublon reste accepté sans erreur'
);

reset role;

-- Signalement de la question 1 de C retiré : elle redevient signalable,
-- avec 20 autres signalements aujourd'hui.
delete from public.question_reports
 where user_id = '00000000-0000-0000-0000-0000000005c1'
   and question_id = (select sq.question_id from public.quiz_session_questions sq
                       where sq.quiz_id = current_setting('t.quiz_c')::uuid
                         and sq.position = 1);

set local role authenticated;

select throws_ok(
  format($$select public.report_question(%L, 1, 'fausse')$$,
         current_setting('t.quiz_c')),
  'PT429', 'trop de signalements aujourd''hui, réessayer demain',
  '21e signalement du jour : refusé (PT429)'
);

reset role;

select is(
  (select count(*)::int from public.question_reports
    where user_id = '00000000-0000-0000-0000-0000000005c1'),
  20,
  'plafond : aucune ligne de plus'
);

-- Purge des sessions et suppression du compte : signalement gardé ------------------------

delete from public.quiz_sessions
 where id = current_setting('t.quiz')::uuid;

select is(
  (select count(*)::int from public.question_reports
    where user_id = '00000000-0000-0000-0000-0000000005a1'),
  1,
  'session purgée : signalement gardé'
);

delete from auth.users where id = '00000000-0000-0000-0000-0000000005a1';

select is(
  (select count(*)::int from public.question_reports
    where user_id is null and reason = 'fausse'),
  1,
  'compte supprimé : signalement gardé, joueur effacé'
);

select * from finish();
rollback;
