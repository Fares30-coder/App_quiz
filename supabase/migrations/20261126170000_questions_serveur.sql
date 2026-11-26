-- Point critique de la revue sécurité de la PR #16 : les bonnes réponses des
-- questions servies par le serveur ne sont plus dans l'app.
--
-- Avant : assets/questions.json (embarqué dans l'APK / l'IPA) contenait les
-- mêmes questions que le serveur (mêmes `id`, mêmes `correctIndex`) : un
-- script lisait l'app et répondait 10/10 en 600 ms avec le bonus rapidité.
--
-- Désormais :
-- 1. Les questions du serveur vivent dans supabase/questions/questions.json
--    (hors bundle), d'où est généré seed.sql. assets/questions.json ne
--    garde que le lot HORS LIGNE (quiz local, jamais soumis, hors
--    classement), jamais servi par le serveur.
-- 2. `questions.active` : seules les questions actives sont tirées par
--    start_quiz() et ensure_daily_challenge(). Les 21 questions du lot hors
--    ligne (peut-être déjà poussées par un seed précédent) sont désactivées.
--    Une question n'est jamais supprimée (référencée par les sessions) : on
--    la désactive.
-- 3. L'identifiant des questions n'est plus envoyé à l'app : elle répond
--    par position (`answer_question(quiz_id, position, choice, time_ms)`).
--    Mêmes contrôles et même erreur unique « question non servie » pour
--    une position pas encore servie ou hors de 1 à 10.

-- Questions actives -------------------------------------------------------------

alter table public.questions
  add column active boolean not null default true;

comment on column public.questions.active is
  'false = jamais tirée par start_quiz / ensure_daily_challenge (question retirée ou du lot hors ligne de l''app). Ne jamais supprimer une question : la désactiver.';

comment on column public.questions.id is
  'Identifiant stable (supabase/questions/questions.json), jamais envoyé à l''app.';

-- Lot hors ligne de l'app (assets/questions.json) : bonnes réponses lisibles
-- dans l'APK, donc plus jamais servies.
update public.questions
   set active = false, updated_at = now()
 where id in (
  'his-001', 'his-002', 'his-003', 'geo-001', 'geo-002', 'geo-003',
  'sci-001', 'sci-002', 'sci-003', 'art-001', 'art-002', 'art-003',
  'spo-001', 'spo-002', 'spo-003', 'act-001', 'act-002', 'act-003',
  'div-001', 'div-002', 'div-003');

-- Défi du jour : questions actives seulement ---------------------------------------
--
-- Comme dans *_start_quiz.sql, avec en plus : une question du défi devenue
-- inactive (ou supprimée) est remplacée au prochain appel par une question
-- active tirée au hasard, en fin de liste ; les sessions déjà commencées
-- gardent la leur.
create or replace function public.ensure_daily_challenge(p_day date)
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
    if (select count(*) from public.questions q
         where q.id = any (v_ids) and q.active) = 10 then
      return v_ids;
    end if;
    -- Réparation (rare) : verrou sur la ligne puis relecture.
    select d.question_ids into v_ids
      from public.daily_challenges d where d.day = p_day for update;
    v_keep := array(
      select t.id from unnest(v_ids) with ordinality as t (id, n)
       where exists (select 1 from public.questions q
                      where q.id = t.id and q.active)
       order by t.n);
    if cardinality(v_keep) = 10 then
      return v_ids;
    end if;
    v_ids := v_keep || array(
      select q.id from public.questions q
       where q.active and q.id <> all (v_keep)
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
       where q.active
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

-- Énoncé servi : sans identifiant -------------------------------------------------
--
-- Comme dans *_temps_serveur.sql, sans `id` : l'app ne connaît que la
-- position (1 à 10) de la question dans son quiz.
create or replace function public.served_question_json(p_quiz_id uuid, p_position integer)
returns jsonb
language sql
stable
set search_path = ''
as $$
  select jsonb_build_object(
           'position', sq.position,
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
           end)
    from public.quiz_session_questions sq
    join public.questions q on q.id = sq.question_id
   where sq.quiz_id = p_quiz_id and sq.position = p_position;
$$;

revoke execute on function public.served_question_json(uuid, integer)
  from public, anon, authenticated;

-- start_quiz() ---------------------------------------------------------------
--
-- Identique à *_temps_serveur.sql, sauf : tirage parmi les questions
-- actives seulement (mix et catégorie ; défi : ensure_daily_challenge) ;
-- questions renvoyées sans `id` (champ `position` à la place).
create or replace function public.start_quiz(mode text, category text default null)
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
  v_answered integer;
  v_position integer;
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
  -- Verrou sur la session (même ordre que answer_question/next_question).
  if v_mode = 'daily' then
    select * into s from public.quiz_sessions qs
     where qs.user_id = uid and qs.mode = 'daily' and qs.challenge_day = v_today
       for update;
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
               where q.active
                 and (v_category is null or q.category = v_category)
               order by random()
               limit quiz_length) t;
    end if;
    if v_ids is null or cardinality(v_ids) <> quiz_length
       or (select count(*) from public.questions q
            where q.id = any (v_ids) and q.active) <> quiz_length then
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
       where qs.user_id = uid and qs.mode = 'daily' and qs.challenge_day = v_today
         for update;
      v_resumed := true;
    end if;
  end if;

  if s.submitted_at is not null then
    select * into r from public.quiz_results qr where qr.id = s.id;
    raise exception 'défi du jour déjà joué'
      using errcode = '23505',
            detail = jsonb_build_object('score', r.score, 'total', r.total)::text;
  end if;

  -- Question en cours : la première sans réponse (réponses dans l'ordre).
  -- Servie maintenant si elle ne l'était pas ; sinon (reprise) son heure
  -- d'envoi d'origine est gardée.
  select count(*) into v_answered
    from public.quiz_session_questions x
   where x.quiz_id = s.id and x.answered_at is not null;
  if v_answered < quiz_length then
    v_position := v_answered + 1;
    update public.quiz_session_questions x
       set served_at = now()
     where x.quiz_id = s.id and x.position = v_position
       and x.served_at is null;
  end if;

  return jsonb_build_object(
    'quiz_id', s.id,
    'mode', s.mode,
    'category', s.category,
    'day', s.challenge_day,
    'expires_at', s.expires_at,
    'resumed', v_resumed,
    'total', quiz_length,
    'position', v_position,
    'seconds_left', public.question_seconds_left(s.id, v_position),
    'questions', (
      select jsonb_agg(public.served_question_json(s.id, p) order by p)
        from generate_series(1, least(v_answered + 1, quiz_length)) p
    )
  );
end;
$$;

revoke execute on function public.start_quiz(text, text) from public, anon;
grant execute on function public.start_quiz(text, text) to authenticated;

-- answer_question() par position ---------------------------------------------------
--
-- Remplace answer_question(quiz_id, question_id, choice, time_ms) :
-- l'app ne connaît plus les identifiants. Paramètres :
-- - quiz_id  : renvoyé par start_quiz() ;
-- - position : numéro de la question en cours (1 à 10, champ `position`
--              de start_quiz / next_question) ;
-- - choice, time_ms : inchangés.
-- Mêmes contrôles qu'avant (*_temps_serveur.sql). Position hors de 1 à 10,
-- pas encore servie ou déjà dépassée sans réponse : même erreur 22023
-- « question non servie ».
--
-- Retour : { quiz_id, position, choice, correct, timed_out, time_ms,
--            correct_choice, explanation }
drop function public.answer_question(uuid, text, integer, integer);

create function public.answer_question(
  quiz_id uuid,
  "position" integer,
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
  -- Tolérance réseau avant de compter le temps comme écoulé.
  timeout_tolerance_ms constant integer := 3000;

  uid uuid := (select auth.uid());
  s public.quiz_sessions%rowtype;
  sq public.quiz_session_questions%rowtype;
  q public.questions%rowtype;
  v_next integer;
  v_elapsed bigint;
  v_choice integer := answer_question.choice;
  v_time integer;
begin
  if uid is null then
    raise exception 'non authentifié' using errcode = '42501';
  end if;
  if answer_question.quiz_id is null or answer_question."position" is null then
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

  -- Seulement parmi les questions déjà servies : même erreur pour une
  -- position hors du quiz ou pas encore servie.
  select * into sq from public.quiz_session_questions x
   where x.quiz_id = s.id and x.position = answer_question."position"
     and x.served_at is not null;
  if not found then
    raise exception 'question non servie' using errcode = '22023';
  end if;

  if sq.answered_at is null then
    if answer_question.time_ms is null
       or answer_question.time_ms not between min_ms and max_ms then
      raise exception 'temps de réponse hors de % à % ms', min_ms, max_ms
        using errcode = '22023';
    end if;
    if v_choice is not null and v_choice not between 0 and 3 then
      raise exception 'réponse hors de 0 à 3' using errcode = '22023';
    end if;
    if now() > s.expires_at then
      raise exception 'quiz expiré' using errcode = '22023';
    end if;

    -- Servie et sans réponse = question en cours (servies une à une) ;
    -- contrôle gardé par prudence, même message.
    select coalesce(max(x.position), 0) + 1 into v_next
      from public.quiz_session_questions x
     where x.quiz_id = s.id and x.answered_at is not null;
    if sq.position <> v_next then
      raise exception 'question non servie' using errcode = '22023';
    end if;

    v_elapsed := greatest(
      floor(extract(epoch from (now() - sq.served_at)) * 1000)::bigint, 0);
    if v_elapsed > max_ms + timeout_tolerance_ms then
      -- Temps écoulé côté serveur : le choix envoyé ne compte pas.
      v_choice := null;
      v_time := max_ms;
    else
      -- Temps officiel : min(déclaré, serveur), au moins 500 ms (il peut donc
      -- dépasser de moins de 500 ms un temps serveur très court).
      v_time := greatest(least(answer_question.time_ms, v_elapsed), min_ms);
    end if;

    update public.quiz_session_questions x
       set choice = v_choice,
           time_ms = v_time,
           elapsed_ms = least(v_elapsed, 2147483647),
           answered_at = now()
     where x.quiz_id = s.id and x.position = sq.position
    returning * into sq;
  end if;

  select * into q from public.questions where id = sq.question_id;

  return jsonb_build_object(
    'quiz_id', s.id,
    'position', sq.position,
    'choice', sq.choice,
    'correct', sq.choice is not null
               and sq.answer_order[sq.choice + 1] = q.correct_index,
    'timed_out', sq.choice is null,
    'time_ms', sq.time_ms,
    'correct_choice', array_position(sq.answer_order, q.correct_index) - 1,
    'explanation', q.explanation
  );
end;
$$;

revoke execute on function public.answer_question(uuid, integer, integer, integer)
  from public, anon;
grant execute on function public.answer_question(uuid, integer, integer, integer)
  to authenticated;

comment on table public.questions is
  'Questions et bonnes réponses (supabase/questions/questions.json, jamais dans l''app). Aucun accès client : servies une à une sans réponse ni identifiant par start_quiz() / next_question(), corrigées par answer_question(). Seules les questions actives sont tirées.';
