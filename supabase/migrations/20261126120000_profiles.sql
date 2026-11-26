-- Profils joueurs : progression synchronisée (une ligne par utilisateur).
--
-- Règle sécurité n° 3 (supabase/README.md) : le client ne fait que LIRE sa
-- ligne. XP, série, gels et compteurs de quiz seront écrits uniquement par
-- `submit_quiz()` (security definer, tâche suivante). Seule écriture client :
-- l'objectif du jour, via `set_daily_goal()`.
--
-- Colonnes calquées sur la progression locale (PlayerProgress / Streak) :
-- totalXp → xp, streak.count → streak, streak.freezes → freezes,
-- streak.lastPlayed → last_played_day, dailyGoal → daily_goal,
-- quizzesDay / quizzesCount → quiz_day / quiz_count.

create table public.profiles (
  id uuid primary key references auth.users (id) on delete cascade,
  xp integer not null default 0 check (xp >= 0),
  streak integer not null default 0 check (streak >= 0),
  freezes smallint not null default 0 check (freezes between 0 and 2),
  last_played_day date,
  daily_goal smallint not null default 2 check (daily_goal between 1 and 3),
  -- Nombre de quiz terminés le jour `quiz_day` (jauge de l'objectif du jour).
  quiz_day date,
  quiz_count integer not null default 0 check (quiz_count >= 0),
  -- Dernier quiz validé par le serveur ; null tant que submit_quiz() n'a
  -- jamais écrit cette ligne (l'app garde alors sa progression locale).
  last_quiz_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

comment on table public.profiles is
  'Progression du joueur. Lecture seule pour le client ; écritures via fonctions security definer.';

-- RLS : chaque utilisateur ne lit que sa ligne ; aucune policy d'écriture.
alter table public.profiles enable row level security;

create policy "profiles : lecture de sa ligne"
  on public.profiles
  for select
  to authenticated
  using ((select auth.uid()) = id);

-- GRANT explicites : lecture seule pour authenticated, rien pour anon.
revoke all on table public.profiles from public, anon, authenticated;
grant select on table public.profiles to authenticated;

-- Création automatique de la ligne à l'inscription (y compris anonyme).
create function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.profiles (id) values (new.id)
  on conflict (id) do nothing;
  return new;
end;
$$;

revoke execute on function public.handle_new_user() from public, anon, authenticated;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- Utilisateurs déjà inscrits (comptes anonymes créés avant cette migration).
insert into public.profiles (id)
select id from auth.users
on conflict (id) do nothing;

-- Seule écriture client : l'objectif du jour (1, 2 ou 3 quiz).
create function public.set_daily_goal(goal smallint)
returns void
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
  if goal is null or goal not between 1 and 3 then
    raise exception 'objectif invalide (1 à 3)' using errcode = '22023';
  end if;
  update public.profiles
  set daily_goal = goal,
      updated_at = now()
  where id = uid;
end;
$$;

revoke execute on function public.set_daily_goal(smallint) from public, anon;
grant execute on function public.set_daily_goal(smallint) to authenticated;
