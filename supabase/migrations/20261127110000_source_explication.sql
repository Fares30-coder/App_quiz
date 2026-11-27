-- Source dans l'explication (décision D2).
--
-- Chaque question peut citer une source courte (libellé texte : « Larousse »,
-- « Insee », « Britannica », « NASA »…), affichée sous l'explication. Pas
-- d'URL au MVP, pas ajoutée au texte de l'explication. Nullable : une
-- question sans source n'affiche rien. Contrainte `questions_source_check` :
-- 1 à 60 caractères, sans espace au bord, sans `://` ni caractère de
-- contrôle (mêmes règles que validateSource() de tool/generate_seed.dart).
--
-- Anti-triche : la source peut trahir la bonne réponse. Comme l'explication,
-- elle n'est JAMAIS envoyée avant la réponse : seulement dans la correction
-- (objet `answer` de served_question_json(), utilisé par start_quiz() et
-- next_question() pour les questions déjà répondues ; retour de
-- answer_question(), réponse ou temps écoulé). submit_quiz() ne renvoie
-- aucun contenu de question.
--
-- Droits de `questions` inchangés : RLS sans policy, aucun GRANT client (la
-- nouvelle colonne n'est pas lisible par l'API).

alter table public.questions
  add column source text
    constraint questions_source_check
    check (source is null
           or (char_length(source) between 1 and 60
               and source = btrim(source)
               and source !~ '://'
               and source !~ '[[:cntrl:]]'));

comment on column public.questions.source is
  'Source courte de l''explication (ex. « Larousse »), sans URL. Renvoyée seulement avec la correction (après answer_question ou temps écoulé), jamais avant la réponse.';

-- Énoncé servi ----------------------------------------------------------------
--
-- Identique à *_questions_serveur.sql, avec `source` dans l'objet `answer`
-- (renseigné seulement une fois la question répondue).
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
               'source', q.source,
               'time_ms', sq.time_ms)
           end)
    from public.quiz_session_questions sq
    join public.questions q on q.id = sq.question_id
   where sq.quiz_id = p_quiz_id and sq.position = p_position;
$$;

revoke execute on function public.served_question_json(uuid, integer)
  from public, anon, authenticated;

-- answer_question() --------------------------------------------------------------
--
-- Identique à *_questions_serveur.sql, avec `source` dans la correction.
--
-- Retour : { quiz_id, position, choice, correct, timed_out, time_ms,
--            correct_choice, explanation, source }
create or replace function public.answer_question(
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
    'explanation', q.explanation,
    'source', q.source
  );
end;
$$;

revoke execute on function public.answer_question(uuid, integer, integer, integer)
  from public, anon;
grant execute on function public.answer_question(uuid, integer, integer, integer)
  to authenticated;
