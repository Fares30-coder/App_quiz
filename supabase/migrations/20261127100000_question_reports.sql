-- Signaler une question (décision D1 : 4 motifs fixes, pas de texte libre).
--
-- Après sa réponse, le joueur peut signaler la question (réponse fausse,
-- question ambiguë, faute, autre). L'app ne connaît jamais l'identifiant des
-- questions (*_questions_serveur.sql) : elle envoie la session (`quiz_id`)
-- et la position (1 à 10) ; le serveur retrouve la question sans jamais
-- renvoyer son identifiant.
--
-- `question_reports` référence `questions` (pas la session) : un
-- signalement survit à la purge des sessions (2 jours) et à la suppression
-- du compte (`user_id` mis à null). Lecture et tri : Dashboard / SQL
-- (supabase/README.md), aucun accès client.

create table public.question_reports (
  id bigint generated always as identity primary key,
  question_id text not null references public.questions (id),
  -- null : compte supprimé depuis le signalement.
  user_id uuid references auth.users (id) on delete set null,
  reason text not null check (reason in ('fausse', 'ambigue', 'faute', 'autre')),
  created_at timestamptz not null default now(),
  -- Un signalement par joueur et par question (doublon ignoré).
  unique (user_id, question_id)
);

comment on table public.question_reports is
  'Signalements de questions par les joueurs (report_question()). Aucun accès client ; tri : supabase/README.md.';

-- Tri par question (et clé étrangère : contrôle à la suppression d'une
-- question).
create index question_reports_question_idx
  on public.question_reports (question_id);

-- Plafond quotidien par joueur.
create index question_reports_user_created_idx
  on public.question_reports (user_id, created_at);

-- RLS sans policy + aucun GRANT : ni anon ni authenticated ne lisent ni
-- n'écrivent la table directement.
alter table public.question_reports enable row level security;
revoke all on table public.question_reports from public, anon, authenticated;

-- report_question() -------------------------------------------------------------
--
-- Paramètres :
-- - p_quiz_id  : session renvoyée par start_quiz() (du joueur connecté) ;
-- - p_position : numéro de la question dans ce quiz (1 à 10), déjà servie
--                ET répondue (le joueur a vu la correction) ;
-- - p_reason   : 'fausse', 'ambigue', 'faute' ou 'autre'.
--
-- Retour : { "reported": true }, identique pour un doublon (aucune nouvelle
-- ligne, motif d'origine gardé). Jamais d'identifiant de question.
--
-- Erreurs : 42501 non authentifié ; 22023 motif invalide, ou question
-- introuvable (même message pour un quiz d'un autre joueur, purgé, une
-- position hors du quiz, pas servie ou sans réponse) ; PT429 plus de 20
-- signalements aujourd'hui (jour Europe/Paris).
create function public.report_question(
  p_quiz_id uuid,
  p_position integer,
  p_reason text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  max_reports_per_day constant integer := 20;

  uid uuid := (select auth.uid());
  v_today date := (now() at time zone 'Europe/Paris')::date;
  -- Début du jour Europe/Paris (changement d'heure compris).
  v_day_start timestamptz := v_today::timestamp at time zone 'Europe/Paris';
  v_question_id text;
begin
  if uid is null then
    raise exception 'non authentifié' using errcode = '42501';
  end if;
  if p_reason is null or p_reason not in ('fausse', 'ambigue', 'faute', 'autre') then
    raise exception 'motif invalide' using errcode = '22023';
  end if;

  -- Verrou sur le profil : les signalements d'un même joueur passent un à
  -- un (plafond fiable).
  perform 1 from public.profiles p where p.id = uid for update;
  if not found then
    raise exception 'profil introuvable' using errcode = 'P0002';
  end if;

  -- Question servie à CE joueur et déjà répondue.
  select sq.question_id into v_question_id
    from public.quiz_sessions s
    join public.quiz_session_questions sq on sq.quiz_id = s.id
   where s.id = p_quiz_id
     and s.user_id = uid
     and sq.position = p_position
     and sq.served_at is not null
     and sq.answered_at is not null;
  if not found then
    raise exception 'question introuvable' using errcode = '22023';
  end if;

  -- Doublon : même réponse, sans compter dans le plafond.
  if exists (select 1 from public.question_reports r
              where r.user_id = uid and r.question_id = v_question_id) then
    return jsonb_build_object('reported', true);
  end if;

  if (select count(*) from public.question_reports r
       where r.user_id = uid and r.created_at >= v_day_start)
     >= max_reports_per_day then
    raise exception 'trop de signalements aujourd''hui, réessayer demain'
      using errcode = 'PT429';
  end if;

  insert into public.question_reports (question_id, user_id, reason)
  values (v_question_id, uid, p_reason)
  on conflict (user_id, question_id) do nothing;

  return jsonb_build_object('reported', true);
end;
$$;

revoke execute on function public.report_question(uuid, integer, text)
  from public, anon;
grant execute on function public.report_question(uuid, integer, text)
  to authenticated;
