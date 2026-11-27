-- Tâche T22 : gel de série obtenu par une pub récompensée
-- (`grant_rewarded_freeze()`).
--
-- L'app appelle la RPC seulement quand le SDK AdMob signale la récompense
-- (`onUserEarnedReward`, vidéo regardée jusqu'au bout). Le serveur ne voit
-- pas la pub : rien ne prouve qu'elle a été vue (la vérification côté
-- serveur AdMob, SSV, demande de vrais blocs d'annonces et une Edge
-- Function : piste ultérieure). Abus possible, borné :
-- - 1 gel par jour (Europe/Paris) au plus par ce moyen ;
-- - 2 gels en réserve au maximum (contrainte de `profiles`) ;
-- - un gel ne rapporte ni XP ni place au classement, il protège seulement
--   un jour sans jeu.
--
-- Gels « paresseux » : `submit_quiz` et `validate_offline_day` ne consomment
-- les gels des jours manqués qu'au quiz suivant. Avant d'accorder un gel, la
-- RPC applique donc les jours manqués jusqu'à la veille (même règle que
-- settleStreak dans lib/engagement/streak_rules.dart), sinon un joueur dont
-- les gels sont déjà consommés sur l'appareil serait refusé (« réserve
-- pleine ») ou en recevrait un de trop :
-- - assez de gels : ils sont consommés et `last_played_day` passe à la
--   veille (jours gelés = jours couverts, la série ne monte pas) ;
-- - pas assez : série perdue (0), gels conservés.
--
-- Ordre imposé à l'app : envoyer les quiz et journées hors ligne en attente
-- AVANT cet appel (ProgressSync.readyForFreezeGrant). Sinon un quiz d'hier
-- encore en file serait compté comme jour manqué (série perdue ou gel
-- consommé), puis refusé ou sans effet sur la série.

-- Gels accordés ------------------------------------------------------------

create table public.freeze_grants (
  user_id uuid not null references auth.users (id) on delete cascade,
  -- Jour de l'octroi (Europe/Paris) : 1 gel par jour.
  day date not null,
  granted_at timestamptz not null default now(),
  primary key (user_id, day)
);

comment on table public.freeze_grants is
  'Gels obtenus par pub récompensée (grant_rewarded_freeze), 1 par jour. Aucun accès client.';

-- RLS sans policy + aucun GRANT : écrit et lu par grant_rewarded_freeze()
-- seulement. Supprimé avec le compte (cascade, delete_account).
alter table public.freeze_grants enable row level security;
revoke all on table public.freeze_grants from public, anon, authenticated;

-- grant_rewarded_freeze() ----------------------------------------------------
--
-- Logique dans `private.grant_rewarded_freeze(uid, as_of)` (heure fixée par
-- les tests), appelée par la RPC publique avec auth.uid() et now().
--
-- Erreurs : 42501 non authentifié, P0002 profil absent.
--
-- Refus « propres » (pas d'erreur, profil renvoyé, gels inchangés) :
-- - `daily_limit` : un gel déjà obtenu aujourd'hui ;
-- - `full` : 2 gels déjà en réserve (après application des jours manqués).
--
-- Retour : { granted, reason,
--            profile: { xp, streak, freezes, last_played_day, daily_goal,
--                       quiz_day, quiz_count, last_quiz_at } }

create function private.grant_rewarded_freeze(uid uuid, as_of timestamptz)
returns jsonb
language plpgsql
security invoker
set search_path = ''
as $$
declare
  max_freezes constant integer := 2;
  -- Lignes gardées : 1 par jour au plus, le plafond ne lit qu'aujourd'hui.
  history_days constant integer := 30;

  v_today date := (as_of at time zone 'Europe/Paris')::date;
  v_reason text;
  v_streak integer;
  v_freezes integer;
  v_last date;
  v_missed integer;
  p public.profiles%rowtype;
begin
  if uid is null then
    raise exception 'non authentifié' using errcode = '42501';
  end if;
  if as_of is null then
    raise exception 'heure de référence manquante' using errcode = '22023';
  end if;

  -- Verrou : passe après (ou avant) un submit_quiz concurrent du joueur.
  select * into p from public.profiles where id = uid for update;
  if not found then
    raise exception 'profil introuvable' using errcode = 'P0002';
  end if;

  -- Jours manqués jusqu'à la veille (voir l'en-tête).
  v_streak := p.streak;
  v_freezes := least(p.freezes, max_freezes);
  v_last := p.last_played_day;
  if v_streak > 0 and v_last is not null then
    v_missed := (v_today - 1) - v_last;
    if v_missed > 0 then
      if v_missed > v_freezes then
        v_streak := 0;
      else
        v_freezes := v_freezes - v_missed;
        v_last := v_today - 1;
      end if;
    end if;
  end if;

  if exists (select 1 from public.freeze_grants fg
             where fg.user_id = uid and fg.day = v_today) then
    v_reason := 'daily_limit';
  elsif v_freezes >= max_freezes then
    v_reason := 'full';
  end if;

  if v_reason is null then
    insert into public.freeze_grants (user_id, day, granted_at)
    values (uid, v_today, as_of)
    on conflict (user_id, day) do nothing;
    -- Course impossible (verrou sur le profil), gardé par prudence.
    if found then
      v_freezes := v_freezes + 1;
    else
      v_reason := 'daily_limit';
    end if;

    delete from public.freeze_grants fg
     where fg.user_id = uid and fg.day < v_today - history_days;
  end if;

  -- Jours manqués appliqués même en cas de refus (état équivalent).
  if v_streak is distinct from p.streak
     or v_freezes is distinct from p.freezes
     or v_last is distinct from p.last_played_day then
    update public.profiles
       set streak = v_streak,
           freezes = v_freezes,
           last_played_day = v_last,
           updated_at = as_of
     where id = uid
    returning * into p;
  end if;

  return jsonb_build_object(
    'granted', v_reason is null,
    'reason', v_reason,
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

revoke execute on function private.grant_rewarded_freeze(uuid, timestamptz)
  from public, anon, authenticated;

create function public.grant_rewarded_freeze()
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
  return private.grant_rewarded_freeze(uid, now());
end;
$$;

comment on function public.grant_rewarded_freeze() is
  'Gel de série après une pub récompensée : 1 par jour, 2 en réserve au maximum. T22.';

revoke execute on function public.grant_rewarded_freeze() from public, anon;
grant execute on function public.grant_rewarded_freeze() to authenticated;
