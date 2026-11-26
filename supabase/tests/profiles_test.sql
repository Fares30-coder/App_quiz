-- Tests pgTAP de la table profiles (RLS, GRANT, set_daily_goal).
-- Lancer en local : `supabase start` puis `supabase test db`.
begin;
create extension if not exists pgtap with schema extensions;

select plan(17);

-- Deux joueurs ; le trigger crée leurs profils.
insert into auth.users (id, aud, role)
values
  ('00000000-0000-0000-0000-00000000000a', 'authenticated', 'authenticated'),
  ('00000000-0000-0000-0000-00000000000b', 'authenticated', 'authenticated');

select is(
  (select count(*)::int from public.profiles
   where id in ('00000000-0000-0000-0000-00000000000a',
                '00000000-0000-0000-0000-00000000000b')),
  2,
  'trigger : un profil créé par utilisateur'
);

select is(
  (select array_agg(relname::text) from pg_class c
   join pg_namespace n on n.oid = c.relnamespace
   where n.nspname = 'public' and c.relkind = 'r' and not c.relrowsecurity),
  null,
  'aucune table du schéma public sans RLS'
);

select ok(
  not has_function_privilege('anon', 'public.set_daily_goal(smallint)', 'execute'),
  'anon ne peut pas appeler set_daily_goal'
);

select ok(
  not has_function_privilege('authenticated', 'public.handle_new_user()', 'execute'),
  'handle_new_user non exécutable par le client'
);

-- Joueur A connecté.
set local role authenticated;
set local "request.jwt.claims" to '{"sub":"00000000-0000-0000-0000-00000000000a","role":"authenticated"}';

select is(
  (select count(*)::int from public.profiles),
  1,
  'A ne voit qu''une ligne'
);

select is(
  (select id from public.profiles),
  '00000000-0000-0000-0000-00000000000a'::uuid,
  'A ne voit que sa propre ligne'
);

select is(
  (select count(*)::int from public.profiles
   where id = '00000000-0000-0000-0000-00000000000b'),
  0,
  'A ne lit pas la ligne de B'
);

select throws_ok(
  $$update public.profiles set xp = 9999$$,
  '42501', null,
  'UPDATE direct refusé'
);

select throws_ok(
  $$insert into public.profiles (id) values (gen_random_uuid())$$,
  '42501', null,
  'INSERT direct refusé'
);

select throws_ok(
  $$delete from public.profiles$$,
  '42501', null,
  'DELETE direct refusé'
);

select throws_ok(
  $$select public.set_daily_goal(5::smallint)$$,
  '22023', null,
  'set_daily_goal(5) refusé'
);

select throws_ok(
  $$select public.set_daily_goal(0::smallint)$$,
  '22023', null,
  'set_daily_goal(0) refusé'
);

select lives_ok(
  $$select public.set_daily_goal(3::smallint)$$,
  'set_daily_goal(3) accepté'
);

select is(
  (select daily_goal::int from public.profiles),
  3,
  'objectif de A mis à jour'
);

-- Visiteur non connecté (clé publishable seule) : aucun accès.
reset role;
set local role anon;
set local "request.jwt.claims" to '{"role":"anon"}';

select throws_ok(
  $$select * from public.profiles$$,
  '42501', null,
  'anon ne lit pas profiles'
);

-- Vérifications en tant que propriétaire : seul daily_goal a changé, B intact.
reset role;

select is(
  (select xp from public.profiles
   where id = '00000000-0000-0000-0000-00000000000a'),
  0,
  'set_daily_goal ne touche pas à l''XP'
);

select is(
  (select daily_goal::int from public.profiles
   where id = '00000000-0000-0000-0000-00000000000b'),
  2,
  'objectif de B inchangé'
);

select * from finish();
rollback;
