-- Correctif 2 de la revue sécurité (PR #15) : temps de réponse mesuré par le
-- serveur.
--
-- Avant : start_quiz() renvoyait les 10 énoncés d'un coup et le temps de
-- réponse était déclaré par l'app. Un script pouvait chercher les réponses
-- pendant 20 min puis tout envoyer avec time_ms = 500 (bonus rapidité à
-- chaque question, aucune vraie limite de 30 s).
--
-- Désormais :
-- 1. start_quiz() ne renvoie que la question 1 et note son heure d'envoi
--    (`served_at`) ;
-- 2. next_question(quiz_id) renvoie la question suivante seulement quand la
--    précédente a une réponse enregistrée, et note son `served_at` ;
-- 3. answer_question() mesure le temps serveur `served_at → maintenant` :
--    - temps officiel (`time_ms`) = min(temps déclaré, temps serveur) ;
--    - temps serveur > 30 s + 3 s de tolérance : réponse enregistrée comme
--      temps écoulé (fausse), quel que soit le choix envoyé ;
--    - temps serveur gardé dans `elapsed_ms` ;
-- 4. submit_quiz() n'accorde le bonus rapidité que si le temps officiel est
--    sous 10 s ET le temps serveur au plus 10 s + 2 s de tolérance réseau.
--
-- Tolérances : le temps serveur inclut, en plus du temps de réflexion, le
-- trajet de la question vers l'app et celui de la réponse vers le serveur
-- (quelques centaines de ms en 4G, jusqu'à 1 à 2 s sur un réseau faible).
-- 2 s pour le bonus (un tricheur gagne au plus 2 s de recherche) et 3 s pour
-- le temps écoulé (une réponse donnée à 29 s sur un réseau lent reste
-- valable).
--
-- Reprise d'un quiz (défi du jour repris après fermeture de l'app) : la
-- question en cours garde son `served_at` d'origine ; si plus de 33 s se
-- sont écoulées, elle compte comme temps écoulé. Voulu : renvoyer un
-- nouveau `served_at` à la reprise donnerait un temps illimité pour
-- chercher une réponse (fermer l'app, chercher, reprendre). start_quiz et
-- next_question renvoient `seconds_left` (calculé par le serveur) pour que
-- le chrono de l'app reparte du temps restant réel.
--
-- Question non servie : answer_question() ne cherche que parmi les
-- questions déjà servies et renvoie la même erreur que pour un identifiant
-- absent du quiz (sinon, en essayant des identifiants, on connaîtrait les
-- 10 questions d'un quiz ou du défi avant qu'elles soient servies).

-- Sessions en cours créées par l'ancien start_quiz : elles ont déjà reçu
-- leurs 10 énoncés d'un coup. Supprimées (réponses comprises, `on delete
-- cascade`) ; le joueur recommence un quiz, défi du jour compris (contrainte
-- unique par jour : raccourcir `expires_at` bloquerait le défi du jour).
delete from public.quiz_sessions where submitted_at is null;

-- Heure d'envoi et temps serveur ---------------------------------------------

alter table public.quiz_session_questions
  -- Heure serveur à laquelle l'énoncé a été envoyé à l'app ; null = pas
  -- encore servi (énoncé jamais renvoyé avant la réponse précédente).
  add column served_at timestamptz,
  -- Temps serveur de la réponse (served_at → answered_at), en ms.
  add column elapsed_ms integer check (elapsed_ms >= 0);

-- Lignes existantes (sessions de moins de 2 jours) : temps déclaré repris.
update public.quiz_session_questions
   set served_at = answered_at - time_ms * interval '1 millisecond',
       elapsed_ms = time_ms
 where answered_at is not null;

alter table public.quiz_session_questions
  add constraint quiz_session_questions_served_check
    check (answered_at is null or served_at is not null),
  add constraint quiz_session_questions_elapsed_check
    check ((answered_at is null) = (elapsed_ms is null));

comment on column public.quiz_session_questions.time_ms is
  'Temps officiel : min(temps déclaré par l''app, temps serveur), 500 à 30 000 ms.';

-- Secondes restantes de la question `p_position` (chrono de 30 s depuis son
-- heure d'envoi, 0 si dépassé, null si pas servie). Fonction interne.
create function public.question_seconds_left(p_quiz_id uuid, p_position integer)
returns integer
language sql
stable
set search_path = ''
as $$
  select greatest(0, 30 - floor(extract(epoch from (now() - sq.served_at)))::integer)
    from public.quiz_session_questions sq
   where sq.quiz_id = p_quiz_id and sq.position = p_position
     and sq.served_at is not null;
$$;

revoke execute on function public.question_seconds_left(uuid, integer)
  from public, anon, authenticated;

-- Énoncé d'une question servie (fonction interne) ------------------------------

-- Question `p_position` du quiz `p_quiz_id`, au format renvoyé à l'app.
-- Bonne réponse et explication seulement si la question est déjà répondue
-- (`answer`, reprise du défi du jour) ; sinon `answer` vaut null.
create function public.served_question_json(p_quiz_id uuid, p_position integer)
returns jsonb
language sql
stable
set search_path = ''
as $$
  select jsonb_build_object(
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
           end)
    from public.quiz_session_questions sq
    join public.questions q on q.id = sq.question_id
   where sq.quiz_id = p_quiz_id and sq.position = p_position;
$$;

revoke execute on function public.served_question_json(uuid, integer)
  from public, anon, authenticated;

-- start_quiz() ---------------------------------------------------------------
--
-- Mêmes paramètres, contrôles, reprise du défi du jour et erreurs que dans
-- *_start_quiz.sql. Seule différence : `questions` ne contient plus que les
-- questions déjà servies :
-- - les questions déjà répondues (reprise du défi : champ `answer`) ;
-- - puis la question en cours (`answer` null), servie maintenant si elle ne
--   l'était pas encore. Reprise : une question déjà servie garde son
--   `served_at` d'origine (plus de 33 s écoulées = temps écoulé).
-- Pas de question en cours si les 10 sont répondues (quiz à soumettre).
--
-- Retour :
-- { quiz_id, mode, category, day, expires_at, resumed, total (10),
--   position (question en cours, null si tout est répondu),
--   seconds_left (chrono restant de la question en cours, 0 à 30, null si
--   tout est répondu),
--   questions: [{ id, category, difficulty, question, answers, answer }] }
-- Les questions suivantes s'obtiennent une à une avec next_question().
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

-- next_question() --------------------------------------------------------------
--
-- Question suivant la dernière question répondue. Refusée tant que la
-- question en cours n'a pas de réponse enregistrée (la question 1 vient de
-- start_quiz()). Idempotente : rappeler (réponse perdue par le réseau)
-- renvoie la même question sans changer son heure d'envoi.
--
-- Retour : { quiz_id, total, position, seconds_left (chrono restant, 0 à
--            30 : moins de 30 si la question était déjà servie),
--            question: { id, category, difficulty, question, answers } }
--
-- Erreurs : 42501 non authentifié, 22023 quiz manquant, inconnu ou d'un autre
-- joueur, expiré ou déjà validé, question en cours sans réponse, quiz
-- terminé.
create function public.next_question(quiz_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  quiz_length constant integer := 10;

  uid uuid := (select auth.uid());
  s public.quiz_sessions%rowtype;
  v_answered integer;
  v_position integer;
begin
  if uid is null then
    raise exception 'non authentifié' using errcode = '42501';
  end if;
  if next_question.quiz_id is null then
    raise exception 'quiz manquant' using errcode = '22023';
  end if;

  -- Verrou sur la session : même ordre que answer_question().
  select * into s from public.quiz_sessions qs
   where qs.id = next_question.quiz_id and qs.user_id = uid
   for update;
  if not found then
    raise exception 'quiz inconnu' using errcode = '22023';
  end if;
  if now() > s.expires_at or s.submitted_at is not null then
    raise exception 'quiz expiré' using errcode = '22023';
  end if;

  -- Réponses enregistrées dans l'ordre : la dernière répondue est
  -- `v_answered`.
  select count(*) into v_answered
    from public.quiz_session_questions x
   where x.quiz_id = s.id and x.answered_at is not null;
  if v_answered = 0 then
    raise exception 'répondre d''abord à la question en cours'
      using errcode = '22023';
  end if;
  if v_answered >= quiz_length then
    raise exception 'quiz terminé' using errcode = '22023';
  end if;
  v_position := v_answered + 1;

  update public.quiz_session_questions x
     set served_at = now()
   where x.quiz_id = s.id and x.position = v_position
     and x.served_at is null;

  return jsonb_build_object(
    'quiz_id', s.id,
    'total', quiz_length,
    'position', v_position,
    'seconds_left', public.question_seconds_left(s.id, v_position),
    'question', public.served_question_json(s.id, v_position)
  );
end;
$$;

revoke execute on function public.next_question(uuid) from public, anon;
grant execute on function public.next_question(uuid) to authenticated;

-- answer_question() ----------------------------------------------------------
--
-- Mêmes paramètres et erreurs que dans *_start_quiz.sql, sauf :
-- - la question doit avoir été servie (start_quiz ou next_question) ; une
--   question pas encore servie et un identifiant absent du quiz donnent la
--   même erreur (« question non servie ») : impossible de deviner les
--   questions à venir en essayant des identifiants ;
-- - `time_ms` déclaré (500 à 30 000 ms) n'est plus refusé s'il dépasse le
--   temps serveur : le temps officiel est min(time_ms, temps serveur),
--   ramené à 500 ms au moins (il peut donc dépasser un temps serveur de
--   moins de 500 ms, d'au plus 500 ms ; sans effet sur le bonus rapidité) ;
-- - temps serveur > 33 s : réponse enregistrée comme temps écoulé (choix
--   ignoré, temps officiel 30 000 ms).
--
-- Retour : { quiz_id, question_id, position, choice, correct, timed_out,
--            time_ms (temps officiel), correct_choice, explanation }
create or replace function public.answer_question(
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

  -- Seulement parmi les questions déjà servies : même erreur pour une
  -- question absente du quiz ou pas encore servie.
  select * into sq from public.quiz_session_questions x
   where x.quiz_id = s.id and x.question_id = answer_question.question_id
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

    select coalesce(max(x.position), 0) + 1 into v_next
      from public.quiz_session_questions x
     where x.quiz_id = s.id and x.answered_at is not null;
    -- Servie et sans réponse = question en cours (servies une à une) ;
    -- contrôle gardé par prudence, même message.
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
    'question_id', sq.question_id,
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

revoke execute on function public.answer_question(uuid, text, integer, integer)
  from public, anon;
grant execute on function public.answer_question(uuid, text, integer, integer)
  to authenticated;

-- submit_quiz() --------------------------------------------------------------
--
-- Identique à *_start_quiz.sql, sauf le bonus rapidité : temps officiel
-- sous 10 s ET temps serveur (`elapsed_ms`) au plus 10 s + 2 s.
create or replace function public.submit_quiz(quiz_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  -- Règles du jeu.
  quiz_length constant integer := 10;
  speed_ms constant integer := 10000;
  -- Tolérance réseau du bonus rapidité sur le temps serveur.
  speed_tolerance_ms constant integer := 2000;
  combo_from constant integer := 3;
  max_freezes constant integer := 2;
  -- Plafonds anti-triche.
  max_xp_per_quiz constant integer := 240; -- 10×10 + 10×5 + 8×5 + 20 + 30
  max_xp_per_day constant integer := 3000;
  max_quizzes_per_hour constant integer := 20;
  max_delay constant interval := interval '6 hours';
  tolerance_ms constant integer := 1000;
  -- Temps officiel minimal d'une réponse (answer_question).
  min_ms constant integer := 500;

  uid uuid := (select auth.uid());
  v_now timestamptz := now();
  v_played timestamptz;
  v_day date;
  v_today date := (now() at time zone 'Europe/Paris')::date;
  p public.profiles%rowtype;
  r public.quiz_results%rowtype;
  s public.quiz_sessions%rowtype;
  v_correct boolean[];
  v_fast boolean[];
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

    -- Réponses enregistrées, corrigées avec les bonnes réponses du serveur ;
    -- rapidité jugée sur le temps officiel et sur le temps serveur.
    select array_agg(sq.choice is not null
                     and sq.answer_order[sq.choice + 1] = q.correct_index
                     order by sq.position),
           array_agg(coalesce(sq.time_ms < speed_ms
                              and sq.elapsed_ms <= speed_ms + speed_tolerance_ms,
                              false)
                     order by sq.position),
           count(sq.answered_at),
           sum(sq.time_ms),
           max(sq.answered_at)
      into v_correct, v_fast, v_answered, v_total_ms, v_played
      from public.quiz_session_questions sq
      join public.questions q on q.id = sq.question_id
     where sq.quiz_id = s.id;
    if v_answered is distinct from quiz_length
       or cardinality(v_correct) <> quiz_length then
      raise exception 'quiz invalide : % réponses attendues', quiz_length
        using errcode = '22023';
    end if;
    -- Redondant avec le temps officiel (borné par le temps serveur de
    -- chaque question), gardé par prudence. Chaque temps officiel peut
    -- dépasser son temps serveur de moins de 500 ms (minimum de 500 ms) :
    -- 10 × 500 ms ajoutés à la tolérance pour ne jamais refuser un joueur
    -- très rapide.
    if v_total_ms > extract(epoch from (v_played - s.started_at)) * 1000
                    + tolerance_ms + quiz_length * min_ms then
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
        if v_fast[i] then
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
  'Questions et bonnes réponses. Aucun accès client : servies une à une sans réponse par start_quiz() / next_question(), corrigées par answer_question().';
