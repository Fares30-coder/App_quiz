-- Tâche 5 de l'étape 2 : validation serveur des quiz (`submit_quiz()`).
--
-- - `questions` : bonnes réponses connues du serveur seul (aucun GRANT client,
--   règle sécurité n° 4). Remplie par `supabase/seed.sql`, généré depuis
--   `assets/questions.json` par `dart run tool/generate_seed.dart`.
-- - `quiz_results` : un quiz validé par ligne ; sert à l'idempotence, aux
--   plafonds (XP par jour, quiz par heure) et alimentera le classement hebdo.
--   Lecture de ses propres lignes seulement.
-- - `submit_quiz()` : recalcule score, XP, série, gels et compteur du jour
--   (règle sécurité n° 3), seule écriture de la progression.
--
-- Barème (CLAUDE.md, lib/engagement/xp.dart) : +10 bonne réponse, +5 si
-- réponse en moins de 10 s, +5 par bonne réponse à partir du combo x3,
-- +20 quiz terminé, +30 sans-faute. Série (lib/engagement/streak_rules.dart) :
-- 1 quiz valide la journée, 1 gel protège 1 jour, 2 gels max (les gels ne
-- sont pas gagnés ici). Jour calendaire : Europe/Paris.

-- Questions ------------------------------------------------------------------

create table public.questions (
  -- Identifiant stable de assets/questions.json (ex. « his-001 »).
  id text primary key check (id ~ '^[a-z0-9-]{1,40}$'),
  category text not null
    check (category in ('histoire', 'geo', 'sciences', 'arts', 'sport', 'actu', 'divers')),
  difficulty smallint not null check (difficulty between 1 and 3),
  question text not null,
  answers text[] not null check (cardinality(answers) = 4),
  -- Index de la bonne réponse dans `answers` (ordre du fichier, avant mélange).
  correct_index smallint not null check (correct_index between 0 and 3),
  explanation text not null,
  updated_at timestamptz not null default now()
);

comment on table public.questions is
  'Questions et bonnes réponses. Aucun accès client : lues par submit_quiz() seulement.';

-- RLS sans aucune policy + aucun GRANT : ni anon ni authenticated ne lisent
-- la table (bonne réponse et explication comprises). Une future lecture
-- distante des questions passera par une RPC/vue sans `correct_index`.
alter table public.questions enable row level security;
revoke all on table public.questions from public, anon, authenticated;

-- Résultats de quiz ----------------------------------------------------------

create table public.quiz_results (
  -- Identifiant généré par l'app pour chaque quiz : une double soumission
  -- (réessai après coupure réseau) ne compte qu'une fois.
  id uuid primary key,
  user_id uuid not null references auth.users (id) on delete cascade,
  -- Jour calendaire du quiz (Europe/Paris) : plafond XP du jour, classement.
  day date not null,
  played_at timestamptz not null,
  submitted_at timestamptz not null default now(),
  score smallint not null check (score between 0 and 10),
  total smallint not null check (total between 1 and 10),
  -- XP comptée (après plafond du jour) et XP calculée avant plafond.
  xp integer not null check (xp >= 0),
  xp_raw integer not null check (xp_raw >= 0)
);

comment on table public.quiz_results is
  'Quiz validés par submit_quiz(). Lecture de ses propres lignes ; aucune écriture client.';

create index quiz_results_user_submitted_idx
  on public.quiz_results (user_id, submitted_at);
create index quiz_results_user_day_idx
  on public.quiz_results (user_id, day);

alter table public.quiz_results enable row level security;

create policy "quiz_results : lecture de ses lignes"
  on public.quiz_results
  for select
  to authenticated
  using ((select auth.uid()) = user_id);

revoke all on table public.quiz_results from public, anon, authenticated;
grant select on table public.quiz_results to authenticated;

-- submit_quiz() --------------------------------------------------------------
--
-- Paramètres (dans l'ordre joué) :
-- - quiz_id      : uuid généré par l'app (idempotence) ;
-- - question_ids : 10 identifiants distincts de `questions` ;
-- - choices      : index choisi dans l'ordre d'origine des réponses (0 à 3),
--                  null si le temps est écoulé ;
-- - times_ms     : temps de réponse en millisecondes (500 à 30 000) ;
-- - played_at    : fin du quiz selon l'appareil (quiz joué hors ligne), ramené
--                  entre le dernier quiz validé et maintenant ; refusé s'il
--                  date de plus de 6 h.
--
-- Quiz joué hors ligne (antidatage) : avec 6 h de retard au plus, le jour du
-- quiz (Europe/Paris) ne peut être qu'aujourd'hui ou la veille, sinon refus
-- 22023 (vérifié aussi explicitement). Un quiz rattaché à la veille suit les
-- règles normales : il ne valide que la veille, les jours manqués avant elle
-- consomment des gels ou cassent la série, et il ne compte que dans le
-- plafond d'XP de la veille. Il ne peut donc ni rattraper une série déjà
-- manquée, ni ouvrir le plafond d'un jour antérieur à hier. Après 6 h, la
-- veille ne peut plus être validée hors ligne (accepté).
--
-- Erreurs : 42501 non authentifié, 22023 entrée invalide (définitif : l'app
-- abandonne la soumission), PT429 trop de quiz en une heure (HTTP 429,
-- l'app réessaiera plus tard).
--
-- Retour : { quiz_id, duplicate, score, total, xp_gained, xp_capped,
--            profile: { xp, streak, freezes, last_played_day, daily_goal,
--                       quiz_day, quiz_count, last_quiz_at } }
create function public.submit_quiz(
  quiz_id uuid,
  question_ids text[],
  choices integer[],
  times_ms integer[],
  played_at timestamptz default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  -- Règles du jeu.
  quiz_length constant integer := 10;
  min_ms constant integer := 500;
  max_ms constant integer := 30000;
  speed_ms constant integer := 10000;
  combo_from constant integer := 3;
  max_freezes constant integer := 2;
  -- Plafonds anti-triche.
  max_xp_per_quiz constant integer := 240; -- 10×10 + 10×5 + 8×5 + 20 + 30
  max_xp_per_day constant integer := 3000;
  max_quizzes_per_hour constant integer := 20;
  max_delay constant interval := interval '6 hours';

  uid uuid := (select auth.uid());
  v_now timestamptz := now();
  v_played timestamptz;
  v_day date;
  v_today date := (now() at time zone 'Europe/Paris')::date;
  p public.profiles%rowtype;
  r public.quiz_results%rowtype;
  v_correct boolean[];
  v_found integer;
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

  -- Forme des entrées.
  if submit_quiz.quiz_id is null
     or question_ids is null or choices is null or times_ms is null
     or array_ndims(question_ids) <> 1 or array_ndims(choices) <> 1
     or array_ndims(times_ms) <> 1
     or cardinality(question_ids) <> quiz_length
     or cardinality(choices) <> quiz_length
     or cardinality(times_ms) <> quiz_length then
    raise exception 'quiz invalide : % questions, réponses et temps attendus', quiz_length
      using errcode = '22023';
  end if;
  if (select count(distinct t.qid) from unnest(question_ids) as t (qid)) <> quiz_length then
    raise exception 'quiz invalide : questions en double ou vides'
      using errcode = '22023';
  end if;
  if exists (select 1 from unnest(times_ms) as t (ms)
             where t.ms is null or t.ms < min_ms or t.ms > max_ms) then
    raise exception 'quiz invalide : temps de réponse hors de % à % ms', min_ms, max_ms
      using errcode = '22023';
  end if;
  if exists (select 1 from unnest(choices) as t (choice)
             where t.choice not between 0 and 3) then
    raise exception 'quiz invalide : réponse hors de 0 à 3'
      using errcode = '22023';
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
    -- Limite de débit (heure glissante, heure du serveur).
    if (select count(*) from public.quiz_results qr
        where qr.user_id = uid and qr.submitted_at > v_now - interval '1 hour')
       >= max_quizzes_per_hour then
      raise exception 'trop de quiz en une heure, réessayer plus tard'
        using errcode = 'PT429';
    end if;

    -- Date du quiz : jamais dans le futur, jamais avant le dernier quiz validé.
    v_played := least(coalesce(submit_quiz.played_at, v_now), v_now);
    if v_played < v_now - max_delay then
      raise exception 'quiz invalide : joué il y a plus de 6 h'
        using errcode = '22023';
    end if;
    v_played := greatest(v_played, coalesce(p.last_quiz_at, v_played));
    v_day := (v_played at time zone 'Europe/Paris')::date;
    -- Aujourd'hui ou la veille seulement (garde explicite, indépendante de
    -- max_delay).
    if v_day < v_today - 1 or v_day > v_today then
      raise exception 'quiz invalide : jour hors de la veille et d''aujourd''hui'
        using errcode = '22023';
    end if;

    -- Correction : réponses comparées aux bonnes réponses du serveur.
    select array_agg(a.choice is not null and a.choice = q.correct_index
                     order by a.ord),
           count(q.id)
      into v_correct, v_found
      from unnest(question_ids, choices) with ordinality as a (qid, choice, ord)
      left join public.questions q on q.id = a.qid;
    if v_found <> quiz_length then
      raise exception 'quiz invalide : question inconnue'
        using errcode = '22023';
    end if;

    -- XP (même calcul que quizXp() dans lib/engagement/xp.dart).
    for i in 1 .. quiz_length loop
      if v_correct[i] then
        v_score := v_score + 1;
        v_combo := v_combo + 1;
        v_xp_raw := v_xp_raw + 10;
        if times_ms[i] < speed_ms then
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

    -- Plafond d'XP par jour : au-delà, le quiz compte (série, objectif)
    -- mais ne rapporte plus d'XP.
    select coalesce(sum(qr.xp), 0) into v_xp_today
      from public.quiz_results qr
      where qr.user_id = uid and qr.day = v_day;
    v_xp := least(v_xp_raw, greatest(max_xp_per_day - v_xp_today, 0));

    -- Série (même logique que settleStreak + recordQuizPlayed) : jours
    -- manqués couverts par les gels, sinon série perdue (gels conservés).
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

    -- Course sur quiz_id (même id envoyé par un autre joueur au même
    -- moment) : aucune écriture, refus définitif.
    insert into public.quiz_results
      (id, user_id, day, played_at, score, total, xp, xp_raw)
    values
      (submit_quiz.quiz_id, uid, v_day, v_played, v_score, quiz_length, v_xp, v_xp_raw)
    on conflict (id) do nothing
    returning * into r;
    if not found then
      raise exception 'quiz invalide : identifiant déjà utilisé'
        using errcode = '22023';
    end if;

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

revoke execute on function public.submit_quiz(uuid, text[], integer[], integer[], timestamptz)
  from public, anon;
grant execute on function public.submit_quiz(uuid, text[], integer[], integer[], timestamptz)
  to authenticated;
