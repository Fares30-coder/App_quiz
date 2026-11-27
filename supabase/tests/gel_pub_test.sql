-- Tests pgTAP de grant_rewarded_freeze() : gel de série après une pub
-- récompensée (1 par jour, 2 en réserve, jours manqués appliqués avant).
-- Lancer en local : `supabase start` puis `supabase test db`.
--
-- Heure fixée via private.grant_rewarded_freeze (2026-06-15, Europe/Paris),
-- sauf pour la RPC publique (now()).
begin;
create extension if not exists pgtap with schema extensions;

select plan(26);

insert into auth.users (id, aud, role)
values
  ('00000000-0000-0000-0000-0000000022a1', 'authenticated', 'authenticated'),
  ('00000000-0000-0000-0000-0000000022b1', 'authenticated', 'authenticated'),
  ('00000000-0000-0000-0000-0000000022c1', 'authenticated', 'authenticated'),
  ('00000000-0000-0000-0000-0000000022d1', 'authenticated', 'authenticated'),
  ('00000000-0000-0000-0000-0000000022e1', 'authenticated', 'authenticated'),
  ('00000000-0000-0000-0000-0000000022f1', 'authenticated', 'authenticated'),
  ('00000000-0000-0000-0000-000000002211', 'authenticated', 'authenticated'),
  ('00000000-0000-0000-0000-000000002221', 'authenticated', 'authenticated');

-- A : série à jour (joué la veille), aucun gel.
update public.profiles
   set xp = 400, streak = 5, freezes = 0, last_played_day = '2026-06-14',
       last_quiz_at = '2026-06-14 20:00:00+02'
 where id = '00000000-0000-0000-0000-0000000022a1';
-- B : 2 jours manqués, 2 gels (consommés par l'appareil, pas encore par le serveur).
update public.profiles
   set streak = 10, freezes = 2, last_played_day = '2026-06-12'
 where id = '00000000-0000-0000-0000-0000000022b1';
-- C : 3 jours manqués, 1 gel : série perdue.
update public.profiles
   set streak = 10, freezes = 1, last_played_day = '2026-06-11'
 where id = '00000000-0000-0000-0000-0000000022c1';
-- D : réserve pleine, rien à appliquer.
update public.profiles
   set streak = 0, freezes = 2
 where id = '00000000-0000-0000-0000-0000000022d1';
-- E : joué aujourd'hui, 1 gel, ancienne ligne à purger.
update public.profiles
   set streak = 3, freezes = 1, last_played_day = '2026-06-15'
 where id = '00000000-0000-0000-0000-0000000022e1';
insert into public.freeze_grants (user_id, day, granted_at)
values ('00000000-0000-0000-0000-0000000022e1', '2026-05-01', '2026-05-01 10:00:00+02'),
       ('00000000-0000-0000-0000-0000000022e1', '2026-06-01', '2026-06-01 10:00:00+02');
-- F : profil absent.
delete from public.profiles where id = '00000000-0000-0000-0000-0000000022f1';

-- Droits ---------------------------------------------------------------------

select ok(
  not has_function_privilege('anon', 'public.grant_rewarded_freeze()', 'execute')
  and not has_function_privilege('public', 'public.grant_rewarded_freeze()', 'execute'),
  'anon et public ne peuvent pas appeler grant_rewarded_freeze'
);

select ok(
  has_function_privilege('authenticated', 'public.grant_rewarded_freeze()', 'execute'),
  'authenticated peut appeler grant_rewarded_freeze'
);

select is(
  (select prosecdef and proconfig @> array['search_path=""']
   from pg_proc where oid = 'public.grant_rewarded_freeze()'::regprocedure),
  true,
  'grant_rewarded_freeze : security definer, search_path vide'
);

select ok(
  not has_function_privilege('authenticated',
    'private.grant_rewarded_freeze(uuid, timestamptz)', 'execute'),
  'private.grant_rewarded_freeze : aucun accès client'
);

select ok(
  not has_table_privilege('authenticated', 'public.freeze_grants', 'select')
  and not has_table_privilege('authenticated', 'public.freeze_grants', 'insert')
  and not has_table_privilege('anon', 'public.freeze_grants', 'select'),
  'freeze_grants : aucun accès client'
);

-- A : cas nominal puis plafond du jour ----------------------------------------

select is(
  private.grant_rewarded_freeze('00000000-0000-0000-0000-0000000022a1',
    '2026-06-15 21:00:00+02'),
  jsonb_build_object('granted', true, 'reason', null, 'profile', jsonb_build_object(
    'xp', 400, 'streak', 5, 'freezes', 1, 'last_played_day', '2026-06-14',
    'daily_goal', 2, 'quiz_day', null, 'quiz_count', 0,
    'last_quiz_at', '2026-06-14T18:00:00+00:00')),
  'série à jour, aucun gel : gel accordé, rien d''autre ne change'
);

select is(
  private.grant_rewarded_freeze('00000000-0000-0000-0000-0000000022a1',
    '2026-06-15 23:30:00+02') - 'profile',
  '{"granted": false, "reason": "daily_limit"}'::jsonb,
  'second gel le même jour : refusé (daily_limit)'
);

select is(
  (select freezes from public.profiles where id = '00000000-0000-0000-0000-0000000022a1'),
  1::smallint,
  'refus du jour : gels inchangés'
);

-- 23 h 30 UTC = 01 h 30 à Paris le 16 : nouveau jour. La veille (15) n'a
-- pas été jouée : le gel la couvre (0), puis un nouveau gel est accordé (1).
select is(
  (private.grant_rewarded_freeze('00000000-0000-0000-0000-0000000022a1',
    '2026-06-15 23:30:00+00') -> 'profile')
    - array['xp', 'daily_goal', 'quiz_day', 'quiz_count', 'last_quiz_at'],
  jsonb_build_object('streak', 5, 'freezes', 1, 'last_played_day', '2026-06-15'),
  'lendemain (heure de Paris) : veille gelée, nouveau gel accordé'
);

select is(
  (select array_agg(day order by day) from public.freeze_grants
   where user_id = '00000000-0000-0000-0000-0000000022a1'),
  array['2026-06-15', '2026-06-16']::date[],
  'un octroi enregistré par jour de Paris'
);

-- 2026-06-17 : la veille (16) est manquée, couverte par le gel → 0, puis +1.
select is(
  private.grant_rewarded_freeze('00000000-0000-0000-0000-0000000022a1',
    '2026-06-17 10:00:00+02') -> 'profile',
  jsonb_build_object(
    'xp', 400, 'streak', 5, 'freezes', 1, 'last_played_day', '2026-06-16',
    'daily_goal', 2, 'quiz_day', null, 'quiz_count', 0,
    'last_quiz_at', '2026-06-14T18:00:00+00:00'),
  'jour manqué couvert par un gel, puis gel accordé : 1 en réserve'
);

-- B : gels déjà consommés par les jours manqués --------------------------------

select is(
  (private.grant_rewarded_freeze('00000000-0000-0000-0000-0000000022b1',
    '2026-06-15 09:00:00+02') -> 'profile')
    - array['xp', 'daily_goal', 'quiz_day', 'quiz_count', 'last_quiz_at'],
  jsonb_build_object('streak', 10, 'freezes', 1, 'last_played_day', '2026-06-14'),
  '2 gels pour 2 jours manqués : consommés, série gardée, puis 1 gel accordé'
);

-- C : série perdue, gels conservés ---------------------------------------------

select is(
  (private.grant_rewarded_freeze('00000000-0000-0000-0000-0000000022c1',
    '2026-06-15 09:00:00+02') -> 'profile')
    - array['xp', 'daily_goal', 'quiz_day', 'quiz_count', 'last_quiz_at'],
  jsonb_build_object('streak', 0, 'freezes', 2, 'last_played_day', '2026-06-11'),
  '3 jours manqués pour 1 gel : série perdue, gel gardé, puis 1 gel accordé'
);

-- D : réserve pleine ----------------------------------------------------------

select is(
  private.grant_rewarded_freeze('00000000-0000-0000-0000-0000000022d1',
    '2026-06-15 09:00:00+02') - 'profile',
  '{"granted": false, "reason": "full"}'::jsonb,
  '2 gels en réserve : refusé (full)'
);

select is(
  (select count(*)::int from public.freeze_grants
   where user_id = '00000000-0000-0000-0000-0000000022d1'),
  0,
  'réserve pleine : aucun octroi enregistré (le plafond du jour reste libre)'
);

-- E : joué aujourd'hui, purge ---------------------------------------------------

select is(
  (private.grant_rewarded_freeze('00000000-0000-0000-0000-0000000022e1',
    '2026-06-15 09:00:00+02') -> 'profile')
    - array['xp', 'daily_goal', 'quiz_day', 'quiz_count', 'last_quiz_at'],
  jsonb_build_object('streak', 3, 'freezes', 2, 'last_played_day', '2026-06-15'),
  'joué aujourd''hui : rien à appliquer, gel accordé'
);

select is(
  (select array_agg(day order by day) from public.freeze_grants
   where user_id = '00000000-0000-0000-0000-0000000022e1'),
  array['2026-06-01', '2026-06-15']::date[],
  'octrois de plus de 30 jours purgés'
);

-- Le lendemain, réserve pleine : refusé, le jour manqué (aujourd'hui = 16,
-- veille = 15 jouée) ne change rien.
select is(
  private.grant_rewarded_freeze('00000000-0000-0000-0000-0000000022e1',
    '2026-06-16 09:00:00+02') ->> 'reason',
  'full',
  'lendemain, 2 gels : refusé (full)'
);

-- F : erreurs ------------------------------------------------------------------

select throws_ok(
  $$ select private.grant_rewarded_freeze('00000000-0000-0000-0000-0000000022f1',
       '2026-06-15 09:00:00+02') $$,
  'P0002', 'profil introuvable',
  'profil absent : P0002'
);

select throws_ok(
  $$ select private.grant_rewarded_freeze(null, '2026-06-15 09:00:00+02') $$,
  '42501', 'non authentifié',
  'sans utilisateur : 42501'
);

-- G : RPC publique (rôle authenticated, now()) -----------------------------------

set local role authenticated;
set local "request.jwt.claims" to '{"sub":"00000000-0000-0000-0000-000000002211","role":"authenticated"}';

select is(
  public.grant_rewarded_freeze() - 'profile',
  '{"granted": true, "reason": null}'::jsonb,
  'RPC publique : gel accordé au joueur connecté'
);

select is(
  public.grant_rewarded_freeze() ->> 'reason',
  'daily_limit',
  'RPC publique : second appel du jour refusé'
);

select throws_ok(
  $$ select count(*) from public.freeze_grants $$,
  '42501', null,
  'authenticated ne lit pas freeze_grants'
);

reset role;

set local role authenticated;
set local "request.jwt.claims" to '{"role":"authenticated"}';

select throws_ok(
  $$ select public.grant_rewarded_freeze() $$,
  '42501', 'non authentifié',
  'RPC publique sans sub : 42501'
);

reset role;

select is(
  (select freezes from public.profiles where id = '00000000-0000-0000-0000-000000002211'),
  1::smallint,
  'RPC publique : 1 gel en réserve'
);

-- H : suppression du compte -----------------------------------------------------

delete from auth.users where id = '00000000-0000-0000-0000-000000002211';

select is(
  (select count(*)::int from public.freeze_grants
   where user_id = '00000000-0000-0000-0000-000000002211'),
  0,
  'compte supprimé : octrois supprimés (cascade)'
);

select finish();
rollback;
