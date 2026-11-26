-- Tâche 7 de l'étape 2 : questions servies par le serveur et défi du jour.
--
-- Avant : l'app tirait ses questions (assets/questions.json) et envoyait à
-- submit_quiz() les questions et réponses de son choix ; un script pouvait
-- donc soumettre des quiz jamais joués. Désormais :
--
-- 1. `start_quiz(mode, category)` tire les 10 questions côté serveur (défi
--    du jour : les mêmes pour tous), mélange les réponses pour ce joueur et
--    enregistre la session (heure de départ serveur). Renvoie les questions
--    SANS la bonne réponse ni l'explication.
-- 2. `answer_question(quiz_id, question_id, choice, time_ms)` enregistre une
--    réponse (horodatée par le serveur) et renvoie seulement alors la
--    correction et l'explication de CETTE question (affichées après chaque
--    réponse). Une réponse ne peut plus être changée.
-- 3. `submit_quiz(quiz_id)` valide un quiz servi à ce joueur, entièrement
--    répondu : score et XP recalculés à partir des réponses enregistrées
--    (plus aucune réponse envoyée à la fin), mêmes contrôles qu'avant
--    (idempotence, plafonds, limite par heure, série, jour Europe/Paris).
--
-- Défi du jour : une seule session par joueur et par jour, reprise par
-- start_quiz('daily') tant qu'elle n'est pas soumise (23505 ensuite).
-- Sessions purgées après 2 jours (pg_cron, purge_quiz_sessions()).
--
-- Tables internes (RLS sans policy, aucun GRANT client) : `daily_challenges`,
-- `quiz_sessions`, `quiz_session_questions`. `questions` reste sans GRANT
-- client (bonne réponse et explication illisibles via l'API).

-- Défi du jour ---------------------------------------------------------------

create table public.daily_challenges (
  -- Jour calendaire Europe/Paris.
  day date primary key,
  -- 10 questions, dans l'ordre joué (identique pour tous les joueurs).
  question_ids text[] not null
    check (array_ndims(question_ids) = 1 and cardinality(question_ids) = 10),
  created_at timestamptz not null default now()
);

comment on table public.daily_challenges is
  'Défi du jour (Europe/Paris), même quiz pour tous. Écrit par ensure_daily_challenge() seulement ; aucun accès client.';

alter table public.daily_challenges enable row level security;
revoke all on table public.daily_challenges from public, anon, authenticated;

-- Questions du défi de `p_day`, créées au premier appel (idempotent : le
-- premier appel du jour choisit, les suivants relisent la même ligne, y
-- compris en cas d'appels simultanés grâce à `on conflict do nothing`).
-- Tirage aléatoire en évitant si possible les questions des 7 jours
-- précédents. Renvoie null s'il y a moins de 10 questions en base.
-- Question du défi supprimée entre-temps (seulement possible si aucune
-- session ne la référence encore) : remplacée par une autre, tirée au
-- hasard, en fin de liste ; les sessions déjà commencées gardent la leur.
-- Fonction interne (appelée par start_quiz, ou par pg_cron si besoin).
create function public.ensure_daily_challenge(p_day date)
returns text[]
language plpgsql
volatile
set search_path = ''
as $$
declare
  v_ids text[];
  v_keep text[];
begin
  select d.question_ids into v_ids
    from public.daily_challenges d where d.day = p_day;
  if found then
    if (select count(*) from public.questions q where q.id = any (v_ids)) = 10 then
      return v_ids;
    end if;
    -- Réparation (rare) : verrou sur la ligne puis relecture.
    select d.question_ids into v_ids
      from public.daily_challenges d where d.day = p_day for update;
    v_keep := array(
      select t.id from unnest(v_ids) with ordinality as t (id, n)
       where exists (select 1 from public.questions q where q.id = t.id)
       order by t.n);
    if cardinality(v_keep) = 10 then
      return v_ids;
    end if;
    v_ids := v_keep || array(
      select q.id from public.questions q
       where q.id <> all (v_keep)
       order by random()
       limit 10 - cardinality(v_keep));
    if cardinality(v_ids) <> 10 then
      return null;
    end if;
    update public.daily_challenges d set question_ids = v_ids where d.day = p_day;
    return v_ids;
  end if;

  insert into public.daily_challenges (day, question_ids)
  select p_day, array_agg(t.id)
    from (
      select q.id
        from public.questions q
       order by exists (
                  select 1 from public.daily_challenges d
                   where d.day between p_day - 7 and p_day - 1
                     and q.id = any (d.question_ids)),
                random()
       limit 10
    ) t
  having count(*) = 10
  on conflict (day) do nothing;

  select d.question_ids into v_ids
    from public.daily_challenges d where d.day = p_day;
  return v_ids;
end;
$$;

revoke execute on function public.ensure_daily_challenge(date)
  from public, anon, authenticated;

-- Sessions de quiz -----------------------------------------------------------

create table public.quiz_sessions (
  -- Identifiant du quiz : repris par submit_quiz() et quiz_results.id.
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  mode text not null check (mode in ('daily', 'category', 'mix')),
  category text
    check (category in ('histoire', 'geo', 'sciences', 'arts', 'sport', 'actu', 'divers')),
  -- Mode « daily » : jour du défi (Europe/Paris).
  challenge_day date,
  started_at timestamptz not null default now(),
  -- Au-delà, plus aucune réponse acceptée.
  expires_at timestamptz not null,
  -- Renseigné par submit_quiz().
  submitted_at timestamptz,
  check ((mode = 'category') = (category is not null)),
  check ((mode = 'daily') = (challenge_day is not null))
);

comment on table public.quiz_sessions is
  'Quiz servis par start_quiz() (heure de départ serveur). Aucun accès client.';

create index quiz_sessions_user_started_idx
  on public.quiz_sessions (user_id, started_at);

-- Purge quotidienne (purge_quiz_sessions).
create index quiz_sessions_started_idx
  on public.quiz_sessions (started_at);

-- Défi du jour : une seule session par joueur et par jour (reprise).
create unique index quiz_sessions_daily_once_idx
  on public.quiz_sessions (user_id, challenge_day)
  where mode = 'daily';

alter table public.quiz_sessions enable row level security;
revoke all on table public.quiz_sessions from public, anon, authenticated;

create table public.quiz_session_questions (
  quiz_id uuid not null references public.quiz_sessions (id) on delete cascade,
  -- 1 à 10, ordre joué.
  position smallint not null check (position between 1 and 10),
  question_id text not null references public.questions (id),
  -- Ordre des réponses servies à ce joueur : answer_order[i + 1] = index
  -- d'origine (`questions.answers`) de la réponse affichée en position i.
  answer_order smallint[] not null
    check (cardinality(answer_order) = 4 and answer_order @> '{0,1,2,3}'),
  -- Réponse donnée (position affichée, 0 à 3), null = temps écoulé.
  choice smallint check (choice between 0 and 3),
  time_ms integer check (time_ms between 500 and 30000),
  -- Heure serveur de la réponse ; null = pas encore répondu.
  answered_at timestamptz,
  primary key (quiz_id, position),
  unique (quiz_id, question_id),
  check ((answered_at is null) = (time_ms is null)),
  check (answered_at is not null or choice is null)
);

-- Clé étrangère vers questions : contrôles à la suppression d'une question.
create index quiz_session_questions_question_idx
  on public.quiz_session_questions (question_id);

comment on table public.quiz_session_questions is
  'Questions servies par quiz (ordre des réponses propre au joueur) et réponses horodatées par le serveur. Aucun accès client.';

alter table public.quiz_session_questions enable row level security;
revoke all on table public.quiz_session_questions from public, anon, authenticated;

-- start_quiz() ---------------------------------------------------------------
--
-- Paramètres :
-- - mode     : 'daily' (défi du jour), 'category' (catégorie obligatoire) ou
--              'mix' (toutes catégories, catégorie absente) ;
-- - category : identifiant de catégorie (mode 'category' seulement).
--
-- Défi du jour : une seule session par joueur et par jour (Europe/Paris).
-- Un nouvel appel le même jour REPREND cette session (même quiz_id, mêmes
-- questions, même ordre des réponses) avec les réponses déjà enregistrées ;
-- elle reste reprenable jusqu'à minuit (au moins 30 min après le départ).
-- Défi déjà soumis : erreur 23505, détail { score, total }.
--
-- Retour :
-- { quiz_id, mode, category, day (défi : jour Europe/Paris, sinon null),
--   expires_at, resumed (true si session du défi reprise),
--   questions: [{ id, category, difficulty, question, answers: [4 textes,
--                 ordre propre à ce quiz],
--                 answer: null tant que la question n'est pas répondue,
--                   sinon { choice, correct, correct_choice, explanation,
--                           time_ms } }] }
-- Bonne réponse et explication seulement pour les questions déjà répondues.
--
-- Erreurs : 42501 non authentifié, 22023 paramètres invalides, P0002 profil
-- absent ou pas assez de questions (moins de 10 pour ce mode), PT429 trop de
-- quiz commencés dans l'heure (30) ou trop de quiz abandonnés dans la
-- journée (10 non soumis), 23505 défi du jour déjà joué.
create function public.start_quiz(mode text, category text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
-- `mode` / `category` non qualifiés (on conflict ... where mode) = colonnes.
#variable_conflict use_column
declare
  quiz_length constant integer := 10;
  max_sessions_per_hour constant integer := 30;
  max_unsubmitted_per_day constant integer := 10;
  session_ttl constant interval := interval '30 minutes';
  -- Sessions conservées 2 jours (submit_quiz accepte 6 h après la fin).
  session_retention constant interval := interval '2 days';

  uid uuid := (select auth.uid());
  v_mode text := start_quiz.mode;
  v_category text := start_quiz.category;
  v_today date := (now() at time zone 'Europe/Paris')::date;
  -- Début et fin du jour Europe/Paris (changement d'heure compris).
  v_day_start timestamptz := v_today::timestamp at time zone 'Europe/Paris';
  v_day_end timestamptz := (v_today + 1)::timestamp at time zone 'Europe/Paris';
  v_ids text[];
  v_resumed boolean := false;
  s public.quiz_sessions%rowtype;
  r public.quiz_results%rowtype;
begin
  if uid is null then
    raise exception 'non authentifié' using errcode = '42501';
  end if;
  if v_mode is null or v_mode not in ('daily', 'category', 'mix')
     or (v_mode = 'category') <> (v_category is not null)
     or (v_category is not null and v_category not in
         ('histoire', 'geo', 'sciences', 'arts', 'sport', 'actu', 'divers')) then
    raise exception 'mode ou catégorie invalide' using errcode = '22023';
  end if;

  -- Verrou sur le profil : les départs d'un même joueur passent un à un
  -- (limites fiables, pas deux défis du jour en parallèle).
  perform 1 from public.profiles p where p.id = uid for update;
  if not found then
    raise exception 'profil introuvable' using errcode = 'P0002';
  end if;

  -- Défi du jour déjà commencé aujourd'hui : reprise (aucune limite, rien
  -- de créé).
  if v_mode = 'daily' then
    select * into s from public.quiz_sessions qs
     where qs.user_id = uid and qs.mode = 'daily' and qs.challenge_day = v_today;
    v_resumed := found;
  end if;

  if not v_resumed then
    if (select count(*) from public.quiz_sessions qs
        where qs.user_id = uid and qs.started_at > now() - interval '1 hour')
       >= max_sessions_per_hour then
      raise exception 'trop de quiz commencés en une heure, réessayer plus tard'
        using errcode = 'PT429';
    end if;
    if (select count(*) from public.quiz_sessions qs
        where qs.user_id = uid and qs.submitted_at is null
          and qs.started_at >= v_day_start)
       >= max_unsubmitted_per_day then
      raise exception 'trop de quiz abandonnés aujourd''hui, réessayer demain'
        using errcode = 'PT429';
    end if;

    -- Ménage : anciennes sessions de ce joueur (purge globale :
    -- purge_quiz_sessions(), chaque nuit).
    delete from public.quiz_sessions qs
     where qs.user_id = uid and qs.started_at < now() - session_retention;

    if v_mode = 'daily' then
      v_ids := public.ensure_daily_challenge(v_today);
    else
      select array_agg(t.id) into v_ids
        from (select q.id from public.questions q
               where v_category is null or q.category = v_category
               order by random()
               limit quiz_length) t;
    end if;
    if v_ids is null or cardinality(v_ids) <> quiz_length
       or (select count(*) from public.questions q where q.id = any (v_ids))
          <> quiz_length then
      raise exception 'pas assez de questions pour ce quiz' using errcode = 'P0002';
    end if;

    -- Défi du jour : valable jusqu'à minuit (Europe/Paris), au moins 30 min.
    insert into public.quiz_sessions
      (user_id, mode, category, challenge_day, expires_at)
    values
      (uid, v_mode, v_category,
       case when v_mode = 'daily' then v_today end,
       case when v_mode = 'daily'
            then greatest(now() + session_ttl, v_day_end)
            else now() + session_ttl end)
    on conflict (user_id, challenge_day) where mode = 'daily' do nothing
    returning * into s;

    if found then
      -- Réponses mélangées pour ce joueur, question par question (la
      -- sous-requête dépend de `t.ord` pour être réévaluée à chaque ligne).
      insert into public.quiz_session_questions
        (quiz_id, position, question_id, answer_order)
      select s.id, t.ord, t.qid,
             (select array_agg(i::smallint order by random())
                from generate_series(0, 3) i
               where t.ord is not null)
        from unnest(v_ids) with ordinality as t (qid, ord);
    else
      -- Course (ne devrait pas arriver grâce au verrou) : défi créé
      -- entre-temps, on le reprend.
      select * into s from public.quiz_sessions qs
       where qs.user_id = uid and qs.mode = 'daily' and qs.challenge_day = v_today;
      v_resumed := true;
    end if;
  end if;

  if s.submitted_at is not null then
    select * into r from public.quiz_results qr where qr.id = s.id;
    raise exception 'défi du jour déjà joué'
      using errcode = '23505',
            detail = jsonb_build_object('score', r.score, 'total', r.total)::text;
  end if;

  return jsonb_build_object(
    'quiz_id', s.id,
    'mode', s.mode,
    'category', s.category,
    'day', s.challenge_day,
    'expires_at', s.expires_at,
    'resumed', v_resumed,
    'questions', (
      select jsonb_agg(jsonb_build_object(
               'id', q.id,
               'category', q.category,
               'difficulty', q.difficulty,
               'question', q.question,
               'answers', (select jsonb_agg(q.answers[o.i + 1] order by o.n)
                             from unnest(sq.answer_order) with ordinality as o (i, n)),
               'answer', case when sq.answered_at is not null then
                 jsonb_build_object(
                   'choice', sq.choice,
                   'correct', sq.choice is not null
                              and sq.answer_order[sq.choice + 1] = q.correct_index,
                   'correct_choice',
                     array_position(sq.answer_order, q.correct_index) - 1,
                   'explanation', q.explanation,
                   'time_ms', sq.time_ms)
               end
             ) order by sq.position)
        from public.quiz_session_questions sq
        join public.questions q on q.id = sq.question_id
       where sq.quiz_id = s.id
    )
  );
end;
$$;

revoke execute on function public.start_quiz(text, text) from public, anon;
grant execute on function public.start_quiz(text, text) to authenticated;

-- answer_question() ----------------------------------------------------------
--
-- Paramètres :
-- - quiz_id     : renvoyé par start_quiz() ;
-- - question_id : question en cours (les questions se répondent dans
--                 l'ordre servi) ;
-- - choice      : position affichée de la réponse (0 à 3), null si le temps
--                 est écoulé ;
-- - time_ms     : temps de réponse mesuré par l'app (500 à 30 000 ms),
--                 jamais supérieur au temps écoulé côté serveur depuis la
--                 réponse précédente (ou le départ) + 1 s de tolérance.
--
-- Réessai (réponse perdue par le réseau) : une question déjà répondue
-- renvoie la correction enregistrée, sans rien changer (même si `choice`
-- diffère). Plus aucune réponse, même un réessai, une fois le quiz soumis.
--
-- Retour : { quiz_id, question_id, position, choice, correct,
--            correct_choice (position affichée de la bonne réponse),
--            explanation }
--
-- Erreurs : 42501 non authentifié, 22023 entrée invalide, quiz inconnu ou
-- d'un autre joueur, déjà soumis, expiré, question hors ordre ou temps
-- impossible.
create function public.answer_question(
  quiz_id uuid,
  question_id text,
  choice integer,
  time_ms integer
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  min_ms constant integer := 500;
  max_ms constant integer := 30000;
  tolerance_ms constant integer := 1000;

  uid uuid := (select auth.uid());
  s public.quiz_sessions%rowtype;
  sq public.quiz_session_questions%rowtype;
  q public.questions%rowtype;
  v_next integer;
  v_since timestamptz;
begin
  if uid is null then
    raise exception 'non authentifié' using errcode = '42501';
  end if;
  if answer_question.quiz_id is null or answer_question.question_id is null then
    raise exception 'quiz ou question manquant' using errcode = '22023';
  end if;

  -- Verrou sur la session : les réponses d'un même quiz passent une à une.
  select * into s from public.quiz_sessions qs
   where qs.id = answer_question.quiz_id and qs.user_id = uid
   for update;
  if not found then
    raise exception 'quiz inconnu' using errcode = '22023';
  end if;
  if s.submitted_at is not null then
    raise exception 'quiz déjà soumis' using errcode = '22023';
  end if;

  select * into sq from public.quiz_session_questions x
   where x.quiz_id = s.id and x.question_id = answer_question.question_id;
  if not found then
    raise exception 'question absente de ce quiz' using errcode = '22023';
  end if;

  if sq.answered_at is null then
    if answer_question.time_ms is null
       or answer_question.time_ms not between min_ms and max_ms then
      raise exception 'temps de réponse hors de % à % ms', min_ms, max_ms
        using errcode = '22023';
    end if;
    if answer_question.choice is not null
       and answer_question.choice not between 0 and 3 then
      raise exception 'réponse hors de 0 à 3' using errcode = '22023';
    end if;
    if now() > s.expires_at then
      raise exception 'quiz expiré' using errcode = '22023';
    end if;

    select coalesce(max(x.position), 0) + 1, max(x.answered_at)
      into v_next, v_since
      from public.quiz_session_questions x
     where x.quiz_id = s.id and x.answered_at is not null;
    if sq.position <> v_next then
      raise exception 'question hors ordre' using errcode = '22023';
    end if;
    v_since := coalesce(v_since, s.started_at);
    if answer_question.time_ms
       > extract(epoch from (now() - v_since)) * 1000 + tolerance_ms then
      raise exception 'temps de réponse impossible' using errcode = '22023';
    end if;

    update public.quiz_session_questions x
       set choice = answer_question.choice,
           time_ms = answer_question.time_ms,
           answered_at = now()
     where x.quiz_id = s.id and x.position = sq.position
    returning * into sq;
  end if;

  select * into q from public.questions where id = sq.question_id;

  return jsonb_build_object(
    'quiz_id', s.id,
    'question_id', sq.question_id,
    'position', sq.position,
    'choice', sq.choice,
    'correct', sq.choice is not null
               and sq.answer_order[sq.choice + 1] = q.correct_index,
    'correct_choice', array_position(sq.answer_order, q.correct_index) - 1,
    'explanation', q.explanation
  );
end;
$$;

revoke execute on function public.answer_question(uuid, text, integer, integer)
  from public, anon;
grant execute on function public.answer_question(uuid, text, integer, integer)
  to authenticated;

-- submit_quiz() --------------------------------------------------------------
--
-- Remplace submit_quiz(quiz_id, question_ids, choices, times_ms, played_at) :
-- les questions, réponses, temps et l'heure de fin viennent maintenant de la
-- session enregistrée par start_quiz() / answer_question().
--
-- Conditions : quiz servi à ce joueur, les 10 questions répondues, durée
-- totale déclarée (somme des temps) au plus égale à la durée serveur
-- (départ → dernière réponse) + 1 s, dernière réponse il y a 6 h au plus
-- (envoi différé après une coupure réseau).
-- Défi du jour repris tard dans la journée : ces contrôles restent valables
-- (la durée serveur ne fait que s'allonger ; les 6 h comptent depuis la
-- dernière réponse, pas depuis le départ).
--
-- Jour du quiz : heure serveur de la dernière réponse (Europe/Paris), ramenée
-- au dernier quiz validé s'il est plus récent ; aujourd'hui ou la veille
-- seulement. Série, gels, plafonds et barème inchangés (voir migration
-- *_submit_quiz.sql).
--
-- Double soumission : renvoie le résultat enregistré (`duplicate: true`)
-- sans rien recompter.
--
-- Erreurs : 42501 non authentifié, 22023 quiz non servi / incomplet / trop
-- ancien / durée impossible / identifiant d'un autre joueur, P0002 profil
-- absent, PT429 trop de quiz validés en une heure.
--
-- Retour (inchangé) : { quiz_id, duplicate, score, total, xp_gained,
--   xp_capped, profile: { xp, streak, freezes, last_played_day, daily_goal,
--                         quiz_day, quiz_count, last_quiz_at } }
drop function public.submit_quiz(uuid, text[], integer[], integer[], timestamptz);

create function public.submit_quiz(quiz_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  -- Règles du jeu.
  quiz_length constant integer := 10;
  speed_ms constant integer := 10000;
  combo_from constant integer := 3;
  max_freezes constant integer := 2;
  -- Plafonds anti-triche.
  max_xp_per_quiz constant integer := 240; -- 10×10 + 10×5 + 8×5 + 20 + 30
  max_xp_per_day constant integer := 3000;
  max_quizzes_per_hour constant integer := 20;
  max_delay constant interval := interval '6 hours';
  tolerance_ms constant integer := 1000;

  uid uuid := (select auth.uid());
  v_now timestamptz := now();
  v_played timestamptz;
  v_day date;
  v_today date := (now() at time zone 'Europe/Paris')::date;
  p public.profiles%rowtype;
  r public.quiz_results%rowtype;
  s public.quiz_sessions%rowtype;
  v_correct boolean[];
  v_times integer[];
  v_answered integer;
  v_total_ms bigint;
  v_score integer := 0;
  v_combo integer := 0;
  v_xp_raw integer := 0;
  v_xp_today integer;
  v_xp integer;
  v_streak integer;
  v_freezes integer;
  v_missed integer;
  v_duplicate boolean := false;
begin
  if uid is null then
    raise exception 'non authentifié' using errcode = '42501';
  end if;
  if submit_quiz.quiz_id is null then
    raise exception 'quiz invalide : identifiant manquant' using errcode = '22023';
  end if;

  -- Verrou sur le profil : les soumissions d'un même joueur passent une à une.
  select * into p from public.profiles where id = uid for update;
  if not found then
    raise exception 'profil introuvable' using errcode = 'P0002';
  end if;

  -- Idempotence : quiz déjà validé, on renvoie le résultat enregistré.
  select * into r from public.quiz_results where id = submit_quiz.quiz_id;
  if found then
    if r.user_id <> uid then
      raise exception 'quiz invalide : identifiant déjà utilisé'
        using errcode = '22023';
    end if;
    v_duplicate := true;
  else
    -- Quiz réellement servi à ce joueur.
    select * into s from public.quiz_sessions qs
     where qs.id = submit_quiz.quiz_id and qs.user_id = uid
     for update;
    if not found then
      raise exception 'quiz invalide : quiz non servi' using errcode = '22023';
    end if;

    -- Limite de débit (heure glissante, heure du serveur).
    if (select count(*) from public.quiz_results qr
        where qr.user_id = uid and qr.submitted_at > v_now - interval '1 hour')
       >= max_quizzes_per_hour then
      raise exception 'trop de quiz en une heure, réessayer plus tard'
        using errcode = 'PT429';
    end if;

    -- Réponses enregistrées, corrigées avec les bonnes réponses du serveur.
    select array_agg(sq.choice is not null
                     and sq.answer_order[sq.choice + 1] = q.correct_index
                     order by sq.position),
           array_agg(sq.time_ms order by sq.position),
           count(sq.answered_at),
           sum(sq.time_ms),
           max(sq.answered_at)
      into v_correct, v_times, v_answered, v_total_ms, v_played
      from public.quiz_session_questions sq
      join public.questions q on q.id = sq.question_id
     where sq.quiz_id = s.id;
    if v_answered is distinct from quiz_length
       or cardinality(v_correct) <> quiz_length then
      raise exception 'quiz invalide : % réponses attendues', quiz_length
        using errcode = '22023';
    end if;
    if v_total_ms > extract(epoch from (v_played - s.started_at)) * 1000 + tolerance_ms then
      raise exception 'quiz invalide : durée totale impossible'
        using errcode = '22023';
    end if;

    -- Date du quiz : dernière réponse (heure serveur), jamais avant le
    -- dernier quiz validé.
    if v_played < v_now - max_delay then
      raise exception 'quiz invalide : terminé il y a plus de 6 h'
        using errcode = '22023';
    end if;
    v_played := greatest(v_played, coalesce(p.last_quiz_at, v_played));
    v_day := (v_played at time zone 'Europe/Paris')::date;
    if v_day < v_today - 1 or v_day > v_today then
      raise exception 'quiz invalide : jour hors de la veille et d''aujourd''hui'
        using errcode = '22023';
    end if;

    -- XP (même calcul que quizXp() dans lib/engagement/xp.dart).
    for i in 1 .. quiz_length loop
      if v_correct[i] then
        v_score := v_score + 1;
        v_combo := v_combo + 1;
        v_xp_raw := v_xp_raw + 10;
        if v_times[i] < speed_ms then
          v_xp_raw := v_xp_raw + 5;
        end if;
        if v_combo >= combo_from then
          v_xp_raw := v_xp_raw + 5;
        end if;
      else
        v_combo := 0;
      end if;
    end loop;
    v_xp_raw := v_xp_raw + 20;
    if v_score = quiz_length then
      v_xp_raw := v_xp_raw + 30;
    end if;
    v_xp_raw := least(v_xp_raw, max_xp_per_quiz);

    -- Plafond d'XP par jour.
    select coalesce(sum(qr.xp), 0) into v_xp_today
      from public.quiz_results qr
      where qr.user_id = uid and qr.day = v_day;
    v_xp := least(v_xp_raw, greatest(max_xp_per_day - v_xp_today, 0));

    -- Série (même logique que settleStreak + recordQuizPlayed).
    v_streak := p.streak;
    v_freezes := least(p.freezes, max_freezes);
    if v_streak > 0 and p.last_played_day is not null then
      v_missed := v_day - p.last_played_day - 1;
      if v_missed > 0 then
        if v_missed > v_freezes then
          v_streak := 0;
        else
          v_freezes := v_freezes - v_missed;
        end if;
      end if;
    end if;
    if p.last_played_day is null or v_day > p.last_played_day then
      v_streak := v_streak + 1;
    end if;

    insert into public.quiz_results
      (id, user_id, day, played_at, score, total, xp, xp_raw)
    values
      (s.id, uid, v_day, v_played, v_score, quiz_length, v_xp, v_xp_raw)
    on conflict (id) do nothing
    returning * into r;
    if not found then
      raise exception 'quiz invalide : identifiant déjà utilisé'
        using errcode = '22023';
    end if;

    update public.quiz_sessions qs
       set submitted_at = v_now
     where qs.id = s.id;

    update public.profiles
    set xp = p.xp + v_xp,
        streak = v_streak,
        freezes = v_freezes,
        last_played_day = greatest(v_day, p.last_played_day),
        quiz_count = case when p.quiz_day = v_day then p.quiz_count + 1 else 1 end,
        quiz_day = v_day,
        last_quiz_at = v_played,
        updated_at = v_now
    where id = uid
    returning * into p;
  end if;

  return jsonb_build_object(
    'quiz_id', r.id,
    'duplicate', v_duplicate,
    'score', r.score,
    'total', r.total,
    'xp_gained', r.xp,
    'xp_capped', r.xp < r.xp_raw,
    'profile', jsonb_build_object(
      'xp', p.xp,
      'streak', p.streak,
      'freezes', p.freezes,
      'last_played_day', p.last_played_day,
      'daily_goal', p.daily_goal,
      'quiz_day', p.quiz_day,
      'quiz_count', p.quiz_count,
      'last_quiz_at', p.last_quiz_at
    )
  );
end;
$$;

revoke execute on function public.submit_quiz(uuid) from public, anon;
grant execute on function public.submit_quiz(uuid) to authenticated;

comment on table public.questions is
  'Questions et bonnes réponses. Aucun accès client : servies sans réponse par start_quiz(), corrigées par answer_question().';

-- Purge globale ----------------------------------------------------------------
--
-- Sessions de plus de 2 jours (réponses comprises, `on delete cascade`),
-- soumises ou non : submit_quiz n'accepte rien au-delà de 6 h après la
-- dernière réponse, et quiz_results garde le résultat. Lancée chaque nuit
-- par pg_cron ; start_quiz purge aussi les sessions du joueur.
create function public.purge_quiz_sessions()
returns integer
language plpgsql
volatile
set search_path = ''
as $$
declare
  v_count integer;
begin
  delete from public.quiz_sessions qs
   where qs.started_at < now() - interval '2 days';
  get diagnostics v_count = row_count;
  return v_count;
end;
$$;

revoke execute on function public.purge_quiz_sessions()
  from public, anon, authenticated;

create extension if not exists pg_cron with schema pg_catalog;

-- 03:30 UTC chaque jour (cron.schedule remplace un job du même nom).
select cron.schedule(
  'purge-quiz-sessions',
  '30 3 * * *',
  'select public.purge_quiz_sessions()'
);
