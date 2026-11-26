-- Tests pgTAP de submit_quiz(), questions et quiz_results.
-- Lancer en local : `supabase start` puis `supabase test db`.
begin;
create extension if not exists pgtap with schema extensions;

select plan(62);

-- Données de test (propriétaire) -------------------------------------------

-- 12 questions dont la bonne réponse est toujours l'index 0.
insert into public.questions
  (id, category, difficulty, question, answers, correct_index, explanation)
select 'zz-' || lpad(i::text, 2, '0'), 'divers', 1, 'Question ' || i,
       array['a', 'b', 'c', 'd'], 0, 'Explication ' || i
from generate_series(1, 12) i;

-- A : calcul XP ; B : limite de débit ; C : plafond du jour ; D : date jouée.
insert into auth.users (id, aud, role)
values
  ('00000000-0000-0000-0000-0000000000a1', 'authenticated', 'authenticated'),
  ('00000000-0000-0000-0000-0000000000b1', 'authenticated', 'authenticated'),
  ('00000000-0000-0000-0000-0000000000c1', 'authenticated', 'authenticated'),
  ('00000000-0000-0000-0000-0000000000d1', 'authenticated', 'authenticated');

-- B a déjà 20 quiz validés dans l'heure.
insert into public.quiz_results (id, user_id, day, played_at, score, total, xp, xp_raw)
select gen_random_uuid(), '00000000-0000-0000-0000-0000000000b1',
       (now() at time zone 'Europe/Paris')::date, now(), 0, 10, 20, 20
from generate_series(1, 20);

-- C a déjà gagné 2 900 XP aujourd'hui (il y a plus d'une heure).
insert into public.quiz_results
  (id, user_id, day, played_at, submitted_at, score, total, xp, xp_raw)
values
  (gen_random_uuid(), '00000000-0000-0000-0000-0000000000c1',
   (now() at time zone 'Europe/Paris')::date, now(), now() - interval '2 hours',
   10, 10, 2900, 2900);

-- Droits ---------------------------------------------------------------------

select is(
  (select array_agg(relname::text) from pg_class c
   join pg_namespace n on n.oid = c.relnamespace
   where n.nspname = 'public' and c.relkind = 'r' and not c.relrowsecurity),
  null,
  'aucune table du schéma public sans RLS'
);

select ok(
  not has_function_privilege('anon',
    'public.submit_quiz(uuid, text[], integer[], integer[], timestamptz)', 'execute'),
  'anon ne peut pas appeler submit_quiz'
);

select ok(
  not has_function_privilege('public',
    'public.submit_quiz(uuid, text[], integer[], integer[], timestamptz)', 'execute'),
  'public ne peut pas appeler submit_quiz'
);

select ok(
  has_function_privilege('authenticated',
    'public.submit_quiz(uuid, text[], integer[], integer[], timestamptz)', 'execute'),
  'authenticated peut appeler submit_quiz'
);

select is(
  (select prosecdef and proconfig @> array['search_path=""']
   from pg_proc
   where oid = 'public.submit_quiz(uuid, text[], integer[], integer[], timestamptz)'::regprocedure),
  true,
  'submit_quiz : security definer + search_path vide'
);

select ok(
  not has_table_privilege('anon', 'public.questions',
    'select,insert,update,delete,truncate'),
  'anon : aucun privilège sur questions'
);

select ok(
  not has_table_privilege('authenticated', 'public.questions',
    'select,insert,update,delete,truncate'),
  'authenticated : aucun privilège sur questions'
);

select ok(
  not has_column_privilege('authenticated', 'public.questions', 'correct_index', 'select')
  and not has_column_privilege('anon', 'public.questions', 'correct_index', 'select'),
  'correct_index illisible par le client'
);

select ok(
  not has_table_privilege('anon', 'public.quiz_results',
    'select,insert,update,delete,truncate'),
  'anon : aucun privilège sur quiz_results'
);

select ok(
  not has_table_privilege('authenticated', 'public.quiz_results',
    'insert,update,delete,truncate'),
  'authenticated : aucune écriture directe sur quiz_results'
);

-- Joueur A connecté ------------------------------------------------------------

set local role authenticated;
set local "request.jwt.claims" to '{"sub":"00000000-0000-0000-0000-0000000000a1","role":"authenticated"}';

select throws_ok(
  $$select correct_index from public.questions$$,
  '42501', null,
  'authenticated ne lit pas les bonnes réponses'
);

select throws_ok(
  $$select id from public.questions$$,
  '42501', null,
  'authenticated ne lit pas la table questions'
);

select throws_ok(
  $$insert into public.quiz_results (id, user_id, day, played_at, score, total, xp, xp_raw)
    values (gen_random_uuid(), '00000000-0000-0000-0000-0000000000a1',
            current_date, now(), 10, 10, 9999, 9999)$$,
  '42501', null,
  'INSERT direct dans quiz_results refusé'
);

-- Sans-faute rapide : 10×10 + 10×5 (rapidité) + 8×5 (combo) + 20 + 30 = 240.
select is(
  public.submit_quiz(
    '11111111-1111-1111-1111-111111111111',
    '{zz-01,zz-02,zz-03,zz-04,zz-05,zz-06,zz-07,zz-08,zz-09,zz-10}',
    '{0,0,0,0,0,0,0,0,0,0}',
    '{2000,2000,2000,2000,2000,2000,2000,2000,2000,2000}'
  ) - 'profile' - 'quiz_id',
  '{"duplicate": false, "score": 10, "total": 10, "xp_gained": 240, "xp_capped": false}'::jsonb,
  'sans-faute rapide : 240 XP'
);

select is(
  (select row(xp, streak, freezes, quiz_count)::text from public.profiles),
  '(240,1,0,1)',
  'profil : XP, série 1, compteur du jour 1'
);

select is(
  (select last_played_day from public.profiles),
  (now() at time zone 'Europe/Paris')::date,
  'jour validé (Europe/Paris)'
);

select isnt(
  (select last_quiz_at from public.profiles),
  null,
  'last_quiz_at renseigné'
);

-- Double soumission : résultat renvoyé, rien n'est recompté.
select is(
  (public.submit_quiz(
    '11111111-1111-1111-1111-111111111111',
    '{zz-01,zz-02,zz-03,zz-04,zz-05,zz-06,zz-07,zz-08,zz-09,zz-10}',
    '{0,0,0,0,0,0,0,0,0,0}',
    '{2000,2000,2000,2000,2000,2000,2000,2000,2000,2000}'
  ) ->> 'duplicate')::boolean,
  true,
  'double soumission détectée'
);

select is(
  (select row(xp, quiz_count)::text from public.profiles),
  '(240,1)',
  'double soumission : XP et compteur inchangés'
);

select is(
  (select count(*)::int from public.quiz_results),
  1,
  'A lit son unique résultat'
);

-- Combo coupé, réponses lentes : 9×10 + combo (3e, puis 7e à 10e) 5×5 + 20 = 135.
select is(
  (public.submit_quiz(
    gen_random_uuid(),
    '{zz-01,zz-02,zz-03,zz-04,zz-05,zz-06,zz-07,zz-08,zz-09,zz-10}',
    '{0,0,0,1,0,0,0,0,0,0}',
    '{15000,15000,15000,15000,15000,15000,15000,15000,15000,15000}'
  ) ->> 'xp_gained')::int,
  135,
  'combo coupé, sans bonus rapidité : 135 XP'
);

select is(
  (select row(xp, streak, quiz_count)::text from public.profiles),
  '(375,1,2)',
  'même jour : série inchangée, compteur 2'
);

-- Temps écoulés (null) : seul le bonus « quiz terminé ».
select is(
  public.submit_quiz(
    gen_random_uuid(),
    '{zz-03,zz-04,zz-05,zz-06,zz-07,zz-08,zz-09,zz-10,zz-11,zz-12}',
    '{null,null,null,null,null,null,null,null,null,null}',
    '{30000,30000,30000,30000,30000,30000,30000,30000,30000,30000}'
  ) -> 'score',
  '0'::jsonb,
  'temps écoulés : score 0'
);

select is(
  (select xp from public.profiles),
  395,
  'temps écoulés : +20 XP'
);

-- Limite du bonus rapidité : 9 999 ms oui, 10 000 ms non → 15 + 10 + 20 = 45.
select is(
  (public.submit_quiz(
    gen_random_uuid(),
    '{zz-01,zz-02,zz-03,zz-04,zz-05,zz-06,zz-07,zz-08,zz-09,zz-10}',
    '{0,0,3,3,3,3,3,3,3,3}',
    '{9999,10000,500,500,500,500,500,500,500,500}'
  ) ->> 'xp_gained')::int,
  45,
  'bonus rapidité strictement sous 10 s'
);

-- Entrées invalides ------------------------------------------------------------

select throws_ok(
  $$select public.submit_quiz(gen_random_uuid(),
    '{zz-01,zz-02,zz-03,zz-04,zz-05,zz-06,zz-07,zz-08,zz-09}',
    '{0,0,0,0,0,0,0,0,0}',
    '{2000,2000,2000,2000,2000,2000,2000,2000,2000}')$$,
  '22023', null,
  '9 questions refusées'
);

select throws_ok(
  $$select public.submit_quiz(gen_random_uuid(),
    '{zz-01,zz-01,zz-03,zz-04,zz-05,zz-06,zz-07,zz-08,zz-09,zz-10}',
    '{0,0,0,0,0,0,0,0,0,0}',
    '{2000,2000,2000,2000,2000,2000,2000,2000,2000,2000}')$$,
  '22023', null,
  'question en double refusée'
);

select throws_ok(
  $$select public.submit_quiz(gen_random_uuid(),
    '{zz-01,zz-02,zz-03,zz-04,zz-05,zz-06,zz-07,zz-08,zz-09,inconnue}',
    '{0,0,0,0,0,0,0,0,0,0}',
    '{2000,2000,2000,2000,2000,2000,2000,2000,2000,2000}')$$,
  '22023', null,
  'question inconnue refusée'
);

select throws_ok(
  $$select public.submit_quiz(gen_random_uuid(),
    '{zz-01,zz-02,zz-03,zz-04,zz-05,zz-06,zz-07,zz-08,zz-09,null}',
    '{0,0,0,0,0,0,0,0,0,0}',
    '{2000,2000,2000,2000,2000,2000,2000,2000,2000,2000}')$$,
  '22023', null,
  'question vide refusée'
);

select throws_ok(
  $$select public.submit_quiz(gen_random_uuid(),
    '{zz-01,zz-02,zz-03,zz-04,zz-05,zz-06,zz-07,zz-08,zz-09,zz-10}',
    '{0,0,0,0,0,0,0,0,0,0}',
    '{499,2000,2000,2000,2000,2000,2000,2000,2000,2000}')$$,
  '22023', null,
  'réponse en moins de 0,5 s refusée'
);

select throws_ok(
  $$select public.submit_quiz(gen_random_uuid(),
    '{zz-01,zz-02,zz-03,zz-04,zz-05,zz-06,zz-07,zz-08,zz-09,zz-10}',
    '{0,0,0,0,0,0,0,0,0,0}',
    '{30001,2000,2000,2000,2000,2000,2000,2000,2000,2000}')$$,
  '22023', null,
  'réponse au-delà de 30 s refusée'
);

select throws_ok(
  $$select public.submit_quiz(gen_random_uuid(),
    '{zz-01,zz-02,zz-03,zz-04,zz-05,zz-06,zz-07,zz-08,zz-09,zz-10}',
    '{0,0,0,0,0,0,0,0,0,0}',
    '{null,2000,2000,2000,2000,2000,2000,2000,2000,2000}')$$,
  '22023', null,
  'temps manquant refusé'
);

select throws_ok(
  $$select public.submit_quiz(gen_random_uuid(),
    '{zz-01,zz-02,zz-03,zz-04,zz-05,zz-06,zz-07,zz-08,zz-09,zz-10}',
    '{4,0,0,0,0,0,0,0,0,0}',
    '{2000,2000,2000,2000,2000,2000,2000,2000,2000,2000}')$$,
  '22023', null,
  'réponse hors de 0 à 3 refusée'
);

select throws_ok(
  $$select public.submit_quiz(null,
    '{zz-01,zz-02,zz-03,zz-04,zz-05,zz-06,zz-07,zz-08,zz-09,zz-10}',
    '{0,0,0,0,0,0,0,0,0,0}',
    '{2000,2000,2000,2000,2000,2000,2000,2000,2000,2000}')$$,
  '22023', null,
  'identifiant de quiz manquant refusé'
);

select throws_ok(
  $$select public.submit_quiz(gen_random_uuid(),
    '{zz-01,zz-02,zz-03,zz-04,zz-05,zz-06,zz-07,zz-08,zz-09,zz-10}',
    '{0,0,0,0,0,0,0,0,0,0}',
    '{2000,2000,2000,2000,2000,2000,2000,2000,2000,2000}',
    now() - interval '3 days')$$,
  '22023', null,
  'quiz joué il y a plus de 48 h refusé'
);

select is(
  (select row(xp, quiz_count)::text from public.profiles),
  '(440,4)',
  'entrées refusées : profil inchangé'
);

-- Série et gels (profil préparé par le propriétaire) ---------------------------

-- 2 jours manqués, 2 gels : série protégée, gels consommés.
reset role;
update public.profiles
set streak = 5, freezes = 2,
    last_played_day = (now() at time zone 'Europe/Paris')::date - 3
where id = '00000000-0000-0000-0000-0000000000a1';
set local role authenticated;

select is(
  (public.submit_quiz(gen_random_uuid(),
    '{zz-01,zz-02,zz-03,zz-04,zz-05,zz-06,zz-07,zz-08,zz-09,zz-10}',
    '{0,0,0,0,0,0,0,0,0,0}',
    '{2000,2000,2000,2000,2000,2000,2000,2000,2000,2000}'
  ) -> 'profile' ->> 'streak')::int,
  6,
  '2 jours manqués + 2 gels : série continue (6)'
);

select is(
  (select freezes::int from public.profiles),
  0,
  '2 gels consommés'
);

-- 2 jours manqués, 1 gel : série perdue puis relancée, gel conservé.
reset role;
update public.profiles
set streak = 5, freezes = 1,
    last_played_day = (now() at time zone 'Europe/Paris')::date - 3
where id = '00000000-0000-0000-0000-0000000000a1';
set local role authenticated;

select is(
  (public.submit_quiz(gen_random_uuid(),
    '{zz-01,zz-02,zz-03,zz-04,zz-05,zz-06,zz-07,zz-08,zz-09,zz-10}',
    '{0,0,0,0,0,0,0,0,0,0}',
    '{2000,2000,2000,2000,2000,2000,2000,2000,2000,2000}'
  ) -> 'profile' ->> 'streak')::int,
  1,
  '2 jours manqués + 1 gel : série repart à 1'
);

select is(
  (select freezes::int from public.profiles),
  1,
  'série perdue : gel conservé'
);

-- Joué hier : série +1, gels intacts, compteur du jour remis à 1.
reset role;
update public.profiles
set streak = 5, freezes = 2,
    last_played_day = (now() at time zone 'Europe/Paris')::date - 1,
    quiz_day = (now() at time zone 'Europe/Paris')::date - 1, quiz_count = 3
where id = '00000000-0000-0000-0000-0000000000a1';
set local role authenticated;

select is(
  (public.submit_quiz(gen_random_uuid(),
    '{zz-01,zz-02,zz-03,zz-04,zz-05,zz-06,zz-07,zz-08,zz-09,zz-10}',
    '{0,0,0,0,0,0,0,0,0,0}',
    '{2000,2000,2000,2000,2000,2000,2000,2000,2000,2000}'
  ) -> 'profile') - 'xp' - 'last_quiz_at' - 'daily_goal',
  jsonb_build_object(
    'streak', 6, 'freezes', 2,
    'last_played_day', (now() at time zone 'Europe/Paris')::date,
    'quiz_day', (now() at time zone 'Europe/Paris')::date,
    'quiz_count', 1
  ),
  'joué hier : série 6, gels intacts, compteur 1'
);

-- Série à 0 : aucun gel consommé.
reset role;
update public.profiles
set streak = 0, freezes = 2,
    last_played_day = (now() at time zone 'Europe/Paris')::date - 5
where id = '00000000-0000-0000-0000-0000000000a1';
set local role authenticated;

select is(
  (public.submit_quiz(gen_random_uuid(),
    '{zz-01,zz-02,zz-03,zz-04,zz-05,zz-06,zz-07,zz-08,zz-09,zz-10}',
    '{0,0,0,0,0,0,0,0,0,0}',
    '{2000,2000,2000,2000,2000,2000,2000,2000,2000,2000}'
  ) -> 'profile') - 'xp' - 'last_quiz_at' - 'daily_goal' - 'quiz_day' - 'quiz_count'
    - 'last_played_day',
  '{"streak": 1, "freezes": 2}'::jsonb,
  'série à 0 : nouvelle série, gels non consommés'
);

-- B : limite de débit et identifiant d'un autre joueur -----------------------

reset role;
set local role authenticated;
set local "request.jwt.claims" to '{"sub":"00000000-0000-0000-0000-0000000000b1","role":"authenticated"}';

select throws_ok(
  $$select public.submit_quiz('11111111-1111-1111-1111-111111111111',
    '{zz-01,zz-02,zz-03,zz-04,zz-05,zz-06,zz-07,zz-08,zz-09,zz-10}',
    '{0,0,0,0,0,0,0,0,0,0}',
    '{2000,2000,2000,2000,2000,2000,2000,2000,2000,2000}')$$,
  '22023', null,
  'identifiant de quiz d''un autre joueur refusé'
);

select throws_ok(
  $$select public.submit_quiz(gen_random_uuid(),
    '{zz-01,zz-02,zz-03,zz-04,zz-05,zz-06,zz-07,zz-08,zz-09,zz-10}',
    '{0,0,0,0,0,0,0,0,0,0}',
    '{2000,2000,2000,2000,2000,2000,2000,2000,2000,2000}')$$,
  'PT429', null,
  '21e quiz dans l''heure refusé'
);

select is(
  (select count(*)::int from public.quiz_results
   where user_id = '00000000-0000-0000-0000-0000000000a1'),
  0,
  'B ne lit pas les résultats de A'
);

select is(
  (select row(xp, quiz_count)::text from public.profiles),
  '(0,0)',
  'B : profil inchangé après refus'
);

-- C : plafond d'XP du jour -----------------------------------------------------

reset role;
set local role authenticated;
set local "request.jwt.claims" to '{"sub":"00000000-0000-0000-0000-0000000000c1","role":"authenticated"}';

select is(
  public.submit_quiz(gen_random_uuid(),
    '{zz-01,zz-02,zz-03,zz-04,zz-05,zz-06,zz-07,zz-08,zz-09,zz-10}',
    '{0,0,0,0,0,0,0,0,0,0}',
    '{2000,2000,2000,2000,2000,2000,2000,2000,2000,2000}'
  ) - 'profile' - 'quiz_id',
  '{"duplicate": false, "score": 10, "total": 10, "xp_gained": 100, "xp_capped": true}'::jsonb,
  'plafond du jour : 100 XP sur 240'
);

select is(
  (public.submit_quiz(gen_random_uuid(),
    '{zz-01,zz-02,zz-03,zz-04,zz-05,zz-06,zz-07,zz-08,zz-09,zz-10}',
    '{0,0,0,0,0,0,0,0,0,0}',
    '{2000,2000,2000,2000,2000,2000,2000,2000,2000,2000}'
  ) ->> 'xp_gained')::int,
  0,
  'plafond atteint : 0 XP'
);

select is(
  (select row(xp, streak, quiz_count)::text from public.profiles),
  '(100,1,2)',
  'plafond atteint : série et compteur comptés quand même'
);

-- D : quiz joué hors ligne (played_at) -----------------------------------------

reset role;
set local role authenticated;
set local "request.jwt.claims" to '{"sub":"00000000-0000-0000-0000-0000000000d1","role":"authenticated"}';

select is(
  (public.submit_quiz(gen_random_uuid(),
    '{zz-01,zz-02,zz-03,zz-04,zz-05,zz-06,zz-07,zz-08,zz-09,zz-10}',
    '{0,0,0,0,0,0,0,0,0,0}',
    '{2000,2000,2000,2000,2000,2000,2000,2000,2000,2000}',
    (((now() at time zone 'Europe/Paris')::date - 1) + time '12:00')
      at time zone 'Europe/Paris'
  ) -> 'profile' ->> 'last_played_day')::date,
  (now() at time zone 'Europe/Paris')::date - 1,
  'quiz joué hier hors ligne : compté hier'
);

select is(
  (public.submit_quiz(gen_random_uuid(),
    '{zz-01,zz-02,zz-03,zz-04,zz-05,zz-06,zz-07,zz-08,zz-09,zz-10}',
    '{0,0,0,0,0,0,0,0,0,0}',
    '{2000,2000,2000,2000,2000,2000,2000,2000,2000,2000}'
  ) -> 'profile' ->> 'streak')::int,
  2,
  'puis aujourd''hui : série 2'
);

select is(
  (public.submit_quiz(gen_random_uuid(),
    '{zz-01,zz-02,zz-03,zz-04,zz-05,zz-06,zz-07,zz-08,zz-09,zz-10}',
    '{0,0,0,0,0,0,0,0,0,0}',
    '{2000,2000,2000,2000,2000,2000,2000,2000,2000,2000}',
    (((now() at time zone 'Europe/Paris')::date - 1) + time '12:00')
      at time zone 'Europe/Paris'
  ) -> 'profile') - 'xp' - 'last_quiz_at' - 'daily_goal' - 'freezes',
  jsonb_build_object(
    'streak', 2,
    'last_played_day', (now() at time zone 'Europe/Paris')::date,
    'quiz_day', (now() at time zone 'Europe/Paris')::date,
    'quiz_count', 2
  ),
  'date antérieure au dernier quiz : ramenée au dernier quiz'
);

select is(
  (select day from public.quiz_results order by submitted_at, played_at limit 1),
  (now() at time zone 'Europe/Paris')::date - 1,
  'quiz_results : jour du quiz hors ligne'
);

select ok(
  (select bool_and(played_at <= now()) from public.quiz_results),
  'played_at jamais dans le futur'
);

select is(
  (public.submit_quiz(gen_random_uuid(),
    '{zz-01,zz-02,zz-03,zz-04,zz-05,zz-06,zz-07,zz-08,zz-09,zz-10}',
    '{0,0,0,0,0,0,0,0,0,0}',
    '{2000,2000,2000,2000,2000,2000,2000,2000,2000,2000}',
    now() + interval '2 days'
  ) -> 'profile' ->> 'quiz_day')::date,
  (now() at time zone 'Europe/Paris')::date,
  'date future ramenée à maintenant'
);

-- Sans uid / anon ----------------------------------------------------------------

reset role;
set local role authenticated;
set local "request.jwt.claims" to '{"role":"authenticated"}';

select throws_ok(
  $$select public.submit_quiz(gen_random_uuid(),
    '{zz-01,zz-02,zz-03,zz-04,zz-05,zz-06,zz-07,zz-08,zz-09,zz-10}',
    '{0,0,0,0,0,0,0,0,0,0}',
    '{2000,2000,2000,2000,2000,2000,2000,2000,2000,2000}')$$,
  '42501', null,
  'submit_quiz sans uid refusé'
);

reset role;
set local role anon;
set local "request.jwt.claims" to '{"role":"anon"}';

select throws_ok(
  $$select public.submit_quiz(gen_random_uuid(),
    '{zz-01,zz-02,zz-03,zz-04,zz-05,zz-06,zz-07,zz-08,zz-09,zz-10}',
    '{0,0,0,0,0,0,0,0,0,0}',
    '{2000,2000,2000,2000,2000,2000,2000,2000,2000,2000}')$$,
  '42501', null,
  'anon ne peut pas appeler submit_quiz'
);

select throws_ok(
  $$select correct_index from public.questions$$,
  '42501', null,
  'anon ne lit pas les bonnes réponses'
);

select throws_ok(
  $$select * from public.quiz_results$$,
  '42501', null,
  'anon ne lit pas quiz_results'
);

-- Vérifications finales (propriétaire) ---------------------------------------------

reset role;

select is(
  (select xp from public.profiles
   where id = '00000000-0000-0000-0000-0000000000a1'),
  (select sum(xp)::int from public.quiz_results
   where user_id = '00000000-0000-0000-0000-0000000000a1'),
  'A : XP du profil = somme des quiz validés'
);

select is(
  (select count(*)::int from public.quiz_results
   where user_id = '00000000-0000-0000-0000-0000000000a1'),
  8,
  'A : 8 quiz validés (doublon et refus exclus)'
);

select is(
  (select count(*)::int from public.quiz_results
   where user_id = '00000000-0000-0000-0000-0000000000b1'),
  20,
  'B : aucun quiz ajouté'
);

select * from finish();
rollback;
