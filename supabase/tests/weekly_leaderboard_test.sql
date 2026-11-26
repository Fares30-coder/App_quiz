-- Tests pgTAP du classement hebdo (weekly_leaderboard, pseudo d'affichage).
-- Lancer en local : `supabase start` puis `supabase test db`.
begin;
create extension if not exists pgtap with schema extensions;

select plan(53);

-- Semaine et fuseau (Europe/Paris) -------------------------------------------

select is(public.leaderboard_week_start('2026-11-26 12:00:00+00'), '2026-11-23'::date,
  'semaine : un jeudi est rattaché au lundi précédent');
select is(public.leaderboard_week_start('2026-11-29 22:59:59+00'), '2026-11-23'::date,
  'heure d''hiver : dimanche 23:59:59 à Paris, encore la semaine du 23');
select is(public.leaderboard_week_start('2026-11-29 23:00:00+00'), '2026-11-30'::date,
  'heure d''hiver : lundi 00:00 à Paris (dimanche 23:00 UTC), nouvelle semaine');
select is(public.leaderboard_week_start('2026-03-29 21:59:59+00'), '2026-03-23'::date,
  'heure d''été : dimanche 23:59:59 à Paris, encore la semaine du 23 mars');
select is(public.leaderboard_week_start('2026-03-29 22:00:00+00'), '2026-03-30'::date,
  'heure d''été : lundi 00:00 à Paris (dimanche 22:00 UTC), nouvelle semaine');

-- Droits ---------------------------------------------------------------------

select ok(not has_function_privilege('anon', 'public.weekly_leaderboard(integer)', 'execute'),
  'anon ne peut pas appeler weekly_leaderboard');
select ok(not has_function_privilege('public', 'public.weekly_leaderboard(integer)', 'execute'),
  'public ne peut pas appeler weekly_leaderboard');
select ok(has_function_privilege('authenticated', 'public.weekly_leaderboard(integer)', 'execute'),
  'authenticated peut appeler weekly_leaderboard');
select ok(not has_function_privilege('authenticated', 'public.leaderboard_week_start(timestamptz)', 'execute')
          and not has_function_privilege('anon', 'public.leaderboard_week_start(timestamptz)', 'execute'),
  'leaderboard_week_start non exposée aux clients');
select ok(not has_function_privilege('public', 'public.leaderboard_week_start(timestamptz)', 'execute'),
  'leaderboard_week_start non exécutable par public');
select ok(not has_function_privilege('public', 'public.generate_display_name()', 'execute')
          and not has_function_privilege('anon', 'public.generate_display_name()', 'execute')
          and not has_function_privilege('authenticated', 'public.generate_display_name()', 'execute'),
  'generate_display_name non exposée aux clients');
select is(
  (select prosecdef and proconfig @> array['search_path=""']
   from pg_proc where oid = 'public.weekly_leaderboard(integer)'::regprocedure),
  true,
  'weekly_leaderboard : security definer + search_path vide');
select is(
  (select array_agg(relname::text) from pg_class c
   join pg_namespace n on n.oid = c.relnamespace
   where n.nspname = 'public' and c.relkind = 'r' and not c.relrowsecurity),
  null,
  'aucune table du schéma public sans RLS');

-- Données (propriétaire) -----------------------------------------------------
--
-- Semaine en cours : A 300, B 250, C 200, D 200 (C y arrive avant D), G 10 ;
-- F n'a que des quiz sans XP (plafond) ; E ne joue que la semaine suivante ;
-- B a aussi 1 000 XP la semaine précédente (dimanche), non comptées.
-- H a 3 000 XP le même jour : plafonnées à 1 000 dans le classement.

insert into auth.users (id, aud, role)
values
  ('00000000-0000-0000-0000-0000000001a0', 'authenticated', 'authenticated'),
  ('00000000-0000-0000-0000-0000000001b0', 'authenticated', 'authenticated'),
  ('00000000-0000-0000-0000-0000000001c0', 'authenticated', 'authenticated'),
  ('00000000-0000-0000-0000-0000000001d0', 'authenticated', 'authenticated'),
  ('00000000-0000-0000-0000-0000000001e0', 'authenticated', 'authenticated'),
  ('00000000-0000-0000-0000-0000000001f0', 'authenticated', 'authenticated'),
  ('00000000-0000-0000-0000-000000000190', 'authenticated', 'authenticated'),
  ('00000000-0000-0000-0000-0000000001a1', 'authenticated', 'authenticated');

select ok(
  (select bool_and(display_name ~ '^Joueur[0-9]{6}$') from public.profiles
   where id::text like '00000000-0000-0000-0000-0000000001%'
      or id = '00000000-0000-0000-0000-000000000190'),
  'pseudo généré par défaut à l''inscription (Joueur + 6 chiffres)');

-- Backfill et unicité : toutes les lignes ont un pseudo au bon format, sans
-- doublon (casse ignorée).
select is(
  (select count(*)::int from public.profiles
   where display_name is null
      or char_length(display_name) not between 3 and 20
      or display_name !~ '^[A-Za-z0-9À-ÖØ-öø-ÿ_.-]([A-Za-z0-9À-ÖØ-öø-ÿ _.-]*[A-Za-z0-9À-ÖØ-öø-ÿ_.-])?$'),
  0,
  'backfill : toutes les lignes ont un pseudo au bon format');
select is(
  (select count(distinct lower(display_name))::int from public.profiles),
  (select count(*)::int from public.profiles),
  'aucun pseudo en double');
select is(
  (select attnotnull from pg_attribute
   where attrelid = 'public.profiles'::regclass and attname = 'display_name'),
  true,
  'display_name obligatoire');

-- Génération : un pseudo déjà pris (même casse différente) est retiré au
-- tirage suivant (graine fixe : même premier tirage).
select setseed(0.42);
select public.generate_display_name() as taken \gset
update public.profiles set display_name = upper(:'taken')
where id = '00000000-0000-0000-0000-0000000001a1';
select setseed(0.42);
select isnt(lower(public.generate_display_name()), lower(:'taken'),
  'collision : nouveau tirage');

update public.profiles p
set display_name = v.name
from (values
  ('00000000-0000-0000-0000-0000000001a0'::uuid, 'Alice'),
  ('00000000-0000-0000-0000-0000000001b0'::uuid, 'Bruno'),
  ('00000000-0000-0000-0000-0000000001c0'::uuid, 'Chloé'),
  ('00000000-0000-0000-0000-0000000001d0'::uuid, 'Dylan'),
  ('00000000-0000-0000-0000-0000000001e0'::uuid, 'Emma'),
  ('00000000-0000-0000-0000-0000000001f0'::uuid, 'Farid'),
  ('00000000-0000-0000-0000-000000000190'::uuid, 'Gaël'),
  ('00000000-0000-0000-0000-0000000001a1'::uuid, 'Hugo')
) as v (id, name)
where p.id = v.id;

insert into public.quiz_results
  (id, user_id, day, played_at, submitted_at, score, total, xp, xp_raw)
select gen_random_uuid(), v.uid::uuid,
       public.leaderboard_week_start(now()) + v.offset_days,
       now(), now() - v.ago, 10, 10, v.xp, greatest(v.xp, 40)
from (values
  ('00000000-0000-0000-0000-0000000001a0', 0, 200, interval '5 hours'),
  ('00000000-0000-0000-0000-0000000001a0', 6, 100, interval '4 hours'),
  ('00000000-0000-0000-0000-0000000001b0', 0, 250, interval '5 hours'),
  ('00000000-0000-0000-0000-0000000001b0', -1, 1000, interval '9 days'),
  ('00000000-0000-0000-0000-0000000001c0', 0, 200, interval '3 hours'),
  ('00000000-0000-0000-0000-0000000001d0', 0, 120, interval '6 hours'),
  ('00000000-0000-0000-0000-0000000001d0', 0, 80, interval '2 hours'),
  ('00000000-0000-0000-0000-0000000001d0', 0, 0, interval '1 hour'),
  ('00000000-0000-0000-0000-0000000001e0', 7, 500, interval '1 hour'),
  ('00000000-0000-0000-0000-0000000001f0', 0, 0, interval '1 hour'),
  ('00000000-0000-0000-0000-000000000190', 0, 10, interval '1 hour'),
  ('00000000-0000-0000-0000-0000000001a1', 0, 2000, interval '7 hours'),
  ('00000000-0000-0000-0000-0000000001a1', 0, 1000, interval '7 hours')
) as v (uid, offset_days, xp, ago);

-- Pseudo : contraintes de longueur et de caractères --------------------------

select throws_ok(
  $$update public.profiles set display_name = 'Al'
    where id = '00000000-0000-0000-0000-0000000001a0'$$,
  '23514', null, 'pseudo de 2 caractères refusé');
select throws_ok(
  $$update public.profiles set display_name = repeat('a', 21)
    where id = '00000000-0000-0000-0000-0000000001a0'$$,
  '23514', null, 'pseudo de 21 caractères refusé');
select throws_ok(
  $$update public.profiles set display_name = '<b>Alice</b>'
    where id = '00000000-0000-0000-0000-0000000001a0'$$,
  '23514', null, 'pseudo avec balises refusé');
select throws_ok(
  $$update public.profiles set display_name = ' Alice'
    where id = '00000000-0000-0000-0000-0000000001a0'$$,
  '23514', null, 'pseudo commençant par une espace refusé');
select throws_ok(
  $$update public.profiles set display_name = 'ALICE'
    where id = '00000000-0000-0000-0000-0000000001b0'$$,
  '23505', null, 'pseudo déjà pris (casse différente) refusé');
select lives_ok(
  $$update public.profiles set display_name = 'Léa B._-2'
    where id = '00000000-0000-0000-0000-0000000001e0'$$,
  'pseudo avec accents, espace et ponctuation autorisée accepté');

-- Visiteur non connecté : refusé ---------------------------------------------

set local role anon;
set local "request.jwt.claims" to '{"role":"anon"}';

select throws_ok($$select public.weekly_leaderboard()$$, '42501', null,
  'anon : appel refusé');
select throws_ok($$select * from public.quiz_results$$, '42501', null,
  'anon : quiz_results illisible');

-- Rôle authenticated sans uid : refusé.
reset role;
set local role authenticated;
set local "request.jwt.claims" to '{"role":"authenticated"}';

select throws_ok($$select public.weekly_leaderboard()$$, '42501', null,
  'sans uid : appel refusé');

-- Joueur A (1er) -------------------------------------------------------------

reset role;
set local role authenticated;
set local "request.jwt.claims" to '{"sub":"00000000-0000-0000-0000-0000000001a0","role":"authenticated"}';

select is(
  (select array_agg(e ->> 'display_name' order by o)
   from jsonb_array_elements(public.weekly_leaderboard() -> 'entries') with ordinality as t (e, o)),
  array['Hugo', 'Alice', 'Bruno', 'Chloé', 'Dylan', 'Gaël'],
  'ordre : XP décroissante, ex-aequo départagés par le premier arrivé ; semaines voisines et quiz sans XP exclus');
select is(
  (select array_agg((e ->> 'rank')::int order by o)
   from jsonb_array_elements(public.weekly_leaderboard() -> 'entries') with ordinality as t (e, o)),
  array[1, 2, 3, 4, 4, 6],
  'ex-aequo : même rang, rang suivant sauté');
select is(
  (select array_agg((e ->> 'xp')::int order by o)
   from jsonb_array_elements(public.weekly_leaderboard() -> 'entries') with ordinality as t (e, o)),
  array[1000, 300, 250, 200, 200, 10],
  'XP de la semaine = somme de l''XP comptée, 1 000 XP par jour au plus');
select is(
  (select array_agg((e ->> 'is_me')::boolean order by o)
   from jsonb_array_elements(public.weekly_leaderboard() -> 'entries') with ordinality as t (e, o)),
  array[false, true, false, false, false, false],
  'is_me vrai seulement sur la ligne du joueur');
select is(public.weekly_leaderboard() -> 'me',
  '{"rank": 2, "xp": 300, "display_name": "Alice"}'::jsonb,
  'me : rang, XP et pseudo du joueur');
select is((public.weekly_leaderboard() ->> 'week_start')::date,
  date_trunc('week', now() at time zone 'Europe/Paris')::date, 'week_start : lundi de la semaine en cours (Paris)');
select is((public.weekly_leaderboard() ->> 'week_end')::date,
  date_trunc('week', now() at time zone 'Europe/Paris')::date + 6, 'week_end : dimanche');
select is((public.weekly_leaderboard() ->> 'ends_at')::timestamptz,
  (date_trunc('week', now() at time zone 'Europe/Paris')::date + 7)::timestamp at time zone 'Europe/Paris',
  'ends_at : lundi suivant 00:00 à Paris');

-- Aucune fuite de colonnes.
select is(
  (select array_agg(k order by k) from jsonb_object_keys(public.weekly_leaderboard()) k),
  array['ends_at', 'entries', 'me', 'week_end', 'week_start'],
  'clés de premier niveau limitées');
select is(
  (select array_agg(distinct k order by k)
   from jsonb_array_elements(public.weekly_leaderboard() -> 'entries') e,
        jsonb_object_keys(e) k),
  array['display_name', 'is_me', 'rank', 'xp'],
  'lignes : rang, pseudo, XP et is_me seulement');
select is(
  (select array_agg(k order by k) from jsonb_object_keys(public.weekly_leaderboard() -> 'me') k),
  array['display_name', 'rank', 'xp'],
  'me : rang, pseudo et XP seulement');
select ok(public.weekly_leaderboard()::text !~ '[0-9a-f]{8}-[0-9a-f]{4}-',
  'aucun identifiant de compte dans la réponse');

-- Limite : bornée à 1..100.
select is(jsonb_array_length(public.weekly_leaderboard(0) -> 'entries'), 1,
  'max_entries 0 ramené à 1');
select is(jsonb_array_length(public.weekly_leaderboard(1000) -> 'entries'), 6,
  'max_entries 1000 ramené à 100 (6 classés)');
select is(jsonb_array_length(public.weekly_leaderboard(null) -> 'entries'), 6,
  'max_entries null : 50 par défaut');

-- Le client ne lit toujours que ses propres résultats.
select is((select count(*)::int from public.quiz_results), 2,
  'A ne lit que ses lignes de quiz_results');
select is(
  (select count(*)::int from public.profiles
   where id = '00000000-0000-0000-0000-0000000001b0'),
  0,
  'A ne lit pas le pseudo de B dans profiles');
select is(
  (select array_agg(display_name) from public.profiles),
  array['Alice'],
  'A ne lit que son propre pseudo dans profiles');

-- Joueur G (6e), hors du top 4 -----------------------------------------------

reset role;
set local role authenticated;
set local "request.jwt.claims" to '{"sub":"00000000-0000-0000-0000-000000000190","role":"authenticated"}';

select is(
  (select array_agg(e ->> 'display_name' order by o)
   from jsonb_array_elements(public.weekly_leaderboard(4) -> 'entries') with ordinality as t (e, o)),
  array['Hugo', 'Alice', 'Bruno', 'Chloé'],
  'top 4 : coupure stable entre ex-aequo (Dylan, arrivé après Chloé, exclu)');
select is(public.weekly_leaderboard(4) -> 'me',
  '{"rank": 6, "xp": 10, "display_name": "Gaël"}'::jsonb,
  'joueur hors du top : rang et XP renvoyés quand même');
select ok(
  not (select bool_or((e ->> 'is_me')::boolean)
       from jsonb_array_elements(public.weekly_leaderboard(4) -> 'entries') e),
  'joueur hors du top : aucune ligne is_me');

-- Joueur H : plafond du classement, profil intact.
reset role;
set local role authenticated;
set local "request.jwt.claims" to '{"sub":"00000000-0000-0000-0000-0000000001a1","role":"authenticated"}';

select is(public.weekly_leaderboard() -> 'me',
  '{"rank": 1, "xp": 1000, "display_name": "Hugo"}'::jsonb,
  '3 000 XP en un jour : 1 000 comptées au classement');
select is((select sum(xp)::int from public.quiz_results), 3000,
  'XP comptée des quiz inchangée (plafond appliqué au classement seulement)');

-- Joueurs F (quiz sans XP) et E (semaine suivante seulement) ---------------

reset role;
set local role authenticated;
set local "request.jwt.claims" to '{"sub":"00000000-0000-0000-0000-0000000001f0","role":"authenticated"}';

select is(public.weekly_leaderboard() -> 'me',
  '{"rank": null, "xp": 0, "display_name": "Farid"}'::jsonb,
  'sans XP cette semaine : pas de rang, 0 XP');

reset role;
set local role authenticated;
set local "request.jwt.claims" to '{"sub":"00000000-0000-0000-0000-0000000001e0","role":"authenticated"}';

select is(public.weekly_leaderboard() -> 'me',
  '{"rank": null, "xp": 0, "display_name": "Léa B._-2"}'::jsonb,
  'XP de la semaine suivante non comptée');

-- Le client ne peut pas modifier son pseudo directement.
select throws_ok(
  $$update public.profiles set display_name = 'Pirate'$$,
  '42501', null, 'UPDATE direct du pseudo refusé');

reset role;

select * from finish();
rollback;
