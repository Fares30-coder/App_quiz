-- Tâche T10 : série hors ligne préservée (`validate_offline_day()`).
--
-- Un quiz joué hors ligne (lot local `assets/questions.json`, jamais soumis)
-- valide la journée sur l'appareil. Sans cette RPC, le profil serveur
-- écrasait cette série au sync suivant. L'app mémorise l'heure du quiz et
-- appelle `validate_offline_day(played_at)` à la reconnexion, AVANT
-- d'appliquer le profil serveur.
--
-- La RPC ne valide QUE le jour (série, gels, compteur du jour) :
-- - aucune XP, aucune ligne dans `quiz_results` (donc aucun effet sur le
--   classement hebdo ni sur les plafonds d'XP) ;
-- - aucun gel gagné (les gels ne font que se consommer, comme submit_quiz).
--
-- Abus connu (inhérent au hors ligne) : rien ne prouve qu'un quiz a été joué,
-- un joueur peut donc valider sa série sans jouer en appelant la RPC. Bornes :
-- - 1 validation par jour au plus (idempotente), aujourd'hui ou la veille
--   seulement, `played_at` jamais dans le futur ni plus de 6 h en arrière ;
-- - au plus 3 jours validés ainsi par période de 7 jours (glissante), hors
--   jours aussi validés par un quiz servi : une série ne peut pas tenir
--   durablement sans quiz servi par le serveur ;
-- - la série ne rapporte ni XP ni place au classement.

-- Jours validés hors ligne ---------------------------------------------------

create table public.offline_days (
  user_id uuid not null references auth.users (id) on delete cascade,
  -- Jour validé (Europe/Paris).
  day date not null,
  -- Heure du quiz hors ligne (appareil, bornée par le serveur).
  played_at timestamptz not null,
  validated_at timestamptz not null default now(),
  primary key (user_id, day)
);

comment on table public.offline_days is
  'Jours validés par un quiz hors ligne (validate_offline_day). Aucun accès client.';

-- RLS sans policy + aucun GRANT : écrit et lu par validate_offline_day()
-- seulement.
alter table public.offline_days enable row level security;
revoke all on table public.offline_days from public, anon, authenticated;

comment on column public.profiles.last_quiz_at is
  'Dernier quiz validé par le serveur (submit_quiz) ou dernier jour validé hors ligne (validate_offline_day) ; null tant qu''aucun des deux n''a écrit la ligne.';

-- validate_offline_day() -----------------------------------------------------
--
-- La logique est dans `private.validate_offline_day(uid, played_at, as_of)`,
-- où `as_of` remplace now() : les tests fixent ainsi l'heure (rattrapage de
-- la veille juste après minuit) sans dépendre de l'heure réelle. Le schéma
-- `private` n'est pas exposé par l'API et n'est accessible à aucun rôle
-- client ; seule la RPC publique ci-dessous (security definer) l'appelle,
-- toujours avec auth.uid() et now().
--
-- Paramètre : played_at = fin du quiz hors ligne selon l'appareil.
--
-- Erreurs : 42501 non authentifié, 22023 entrée invalide (played_at manquant,
-- dans le futur au-delà de 5 min de décalage d'horloge, plus de 6 h en
-- arrière, jour hors de la veille et d'aujourd'hui) : définitif, l'app
-- abandonne l'événement. P0002 profil absent.
--
-- Refus « propres » (pas d'erreur, profil renvoyé tel quel) :
-- - `already_validated` : jour déjà validé (quiz servi, appel précédent,
--   autre appareil) ou antérieur au dernier jour validé (on ne réécrit pas
--   le passé) ;
-- - `limit` : 3 jours déjà validés hors ligne sur les 7 jours précédant le
--   jour du quiz (jour compris). Un jour hors ligne aussi validé par un quiz
--   servi (ligne dans `quiz_results`) ne compte pas.
--
-- Retour : { validated, reason, day,
--            profile: { xp, streak, freezes, last_played_day, daily_goal,
--                       quiz_day, quiz_count, last_quiz_at } }

create schema private;
comment on schema private is
  'Fonctions internes, non exposées par l''API ; aucun accès client.';
revoke all on schema private from public, anon, authenticated;

create function private.validate_offline_day(
  uid uuid,
  played_at timestamptz,
  as_of timestamptz
)
returns jsonb
language plpgsql
security invoker
set search_path = ''
as $$
declare
  max_freezes constant integer := 2;
  max_delay constant interval := interval '6 hours';
  -- Décalage d'horloge toléré (appareil un peu en avance).
  clock_skew constant interval := interval '5 minutes';
  max_offline_days constant integer := 3;
  window_days constant integer := 7;

  v_now timestamptz := as_of;
  v_today date := (as_of at time zone 'Europe/Paris')::date;
  v_played timestamptz;
  v_day date;
  v_reason text;
  v_streak integer;
  v_freezes integer;
  v_missed integer;
  p public.profiles%rowtype;
begin
  if uid is null then
    raise exception 'non authentifié' using errcode = '42501';
  end if;
  if as_of is null then
    raise exception 'heure de référence manquante' using errcode = '22023';
  end if;
  if validate_offline_day.played_at is null then
    raise exception 'jour invalide : heure du quiz manquante' using errcode = '22023';
  end if;
  if validate_offline_day.played_at > v_now + clock_skew then
    raise exception 'jour invalide : quiz dans le futur' using errcode = '22023';
  end if;
  if validate_offline_day.played_at < v_now - max_delay then
    raise exception 'jour invalide : quiz joué il y a plus de 6 h'
      using errcode = '22023';
  end if;
  v_played := least(validate_offline_day.played_at, v_now);
  v_day := (v_played at time zone 'Europe/Paris')::date;
  -- Garde explicite, indépendante de max_delay (comme submit_quiz).
  if v_day < v_today - 1 or v_day > v_today then
    raise exception 'jour invalide : hors de la veille et d''aujourd''hui'
      using errcode = '22023';
  end if;

  -- Verrou : passe après (ou avant) un submit_quiz concurrent du joueur.
  select * into p from public.profiles where id = uid for update;
  if not found then
    raise exception 'profil introuvable' using errcode = 'P0002';
  end if;

  if p.last_played_day is not null and v_day <= p.last_played_day then
    v_reason := 'already_validated';
  elsif (select count(*) from public.offline_days od
         where od.user_id = uid
           and od.day > v_day - window_days
           -- Jour aussi validé par un quiz servi : ne compte pas.
           and not exists (select 1 from public.quiz_results qr
                           where qr.user_id = uid and qr.day = od.day))
        >= max_offline_days then
    v_reason := 'limit';
  end if;

  if v_reason is null then
    -- Série (même logique que submit_quiz) : jours manqués couverts par les
    -- gels, sinon série perdue (gels conservés). Aucun gel gagné.
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
    v_streak := v_streak + 1;

    -- Course impossible (verrou sur le profil), gardé par prudence.
    insert into public.offline_days (user_id, day, played_at, validated_at)
    values (uid, v_day, v_played, v_now)
    on conflict (user_id, day) do nothing;

    -- Purge des jours devenus inutiles au plafond.
    delete from public.offline_days od
     where od.user_id = uid and od.day < v_today - 2 * window_days;

    update public.profiles
    set streak = v_streak,
        freezes = v_freezes,
        last_played_day = v_day,
        quiz_count = case when p.quiz_day = v_day then p.quiz_count + 1 else 1 end,
        quiz_day = v_day,
        last_quiz_at = greatest(p.last_quiz_at, v_played),
        updated_at = v_now
    where id = uid
    returning * into p;
  end if;

  return jsonb_build_object(
    'validated', v_reason is null,
    'reason', v_reason,
    'day', v_day,
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

revoke execute on function private.validate_offline_day(uuid, timestamptz, timestamptz)
  from public, anon, authenticated;

create function public.validate_offline_day(played_at timestamptz)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  uid uuid := (select auth.uid());
begin
  if uid is null then
    raise exception 'non authentifié' using errcode = '42501';
  end if;
  return private.validate_offline_day(uid, validate_offline_day.played_at, now());
end;
$$;

revoke execute on function public.validate_offline_day(timestamptz) from public, anon;
grant execute on function public.validate_offline_day(timestamptz) to authenticated;
