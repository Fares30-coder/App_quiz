-- Tâche 6 de l'étape 2 : classement hebdo global (`weekly_leaderboard()`).
--
-- - Semaine : lundi 00:00 → dimanche 23:59:59, Europe/Paris. `quiz_results.day`
--   est déjà le jour calendaire de Paris (écrit par submit_quiz()).
-- - Score : somme de l'XP **comptée** (`quiz_results.xp`, après plafonds) de
--   la semaine : score officiel du serveur, jamais une valeur du client.
--   Plafond propre au classement : 1 000 XP par jour et par joueur au plus
--   (le profil garde toute son XP).
-- - Données exposées : rang, pseudo d'affichage, XP de la semaine et un
--   drapeau « c'est moi ». Jamais d'identifiant, de série ni de date.
-- - Ex-aequo : même rang (classement « 1, 2, 2, 4 ») ; ordre d'affichage
--   stable : XP décroissante, puis le premier à avoir atteint ce total
--   (dernier quiz rapportant de l'XP, heure serveur), puis identifiant.
--
-- Amis, ligues de 30 et badges : étape suivante.

-- Pseudo d'affichage ---------------------------------------------------------
--
-- Généré à l'inscription (« Joueur » + 6 chiffres aléatoires, sans lien avec
-- l'identifiant du compte), modifiable plus tard par une RPC dédiée (pas
-- encore exposée). 3 à 20 caractères : lettres (accents compris), chiffres,
-- espace, « _ », « - » et « . », sans espace au début ni à la fin.
-- Unique sans tenir compte de la casse (index sur lower(display_name)).
alter table public.profiles
  add column display_name text
    constraint profiles_display_name_format check (
      char_length(display_name) between 3 and 20
      and display_name ~ '^[A-Za-z0-9À-ÖØ-öø-ÿ_.-]([A-Za-z0-9À-ÖØ-öø-ÿ _.-]*[A-Za-z0-9À-ÖØ-öø-ÿ_.-])?$'
    );

create unique index profiles_display_name_lower_key
  on public.profiles (lower(display_name));

-- Pseudo libre au moment de l'appel : 10 essais à 6 chiffres, puis 10 à
-- 9 chiffres (boucle bornée), sinon erreur. Une course entre deux
-- inscriptions reste possible : handle_new_user() réessaie alors.
create function public.generate_display_name()
returns text
language plpgsql
volatile
set search_path = ''
as $$
declare
  candidate text;
begin
  for attempt in 1 .. 20 loop
    candidate := 'Joueur' || case
      when attempt <= 10 then lpad(floor(random() * 1000000)::int::text, 6, '0')
      else lpad(floor(random() * 1000000000)::bigint::text, 9, '0')
    end;
    if not exists (select 1 from public.profiles p
                   where lower(p.display_name) = lower(candidate)) then
      return candidate;
    end if;
  end loop;
  raise exception 'aucun pseudo libre trouvé' using errcode = '23505';
end;
$$;

revoke execute on function public.generate_display_name()
  from public, anon, authenticated;

-- Comptes existants : un pseudo chacun, ligne par ligne (chaque UPDATE voit
-- les pseudos déjà attribués ; l'index unique interdit tout doublon).
do $$
declare
  r record;
begin
  for r in select id from public.profiles where display_name is null loop
    update public.profiles
    set display_name = public.generate_display_name()
    where id = r.id;
  end loop;
end;
$$;

alter table public.profiles
  alter column display_name set default public.generate_display_name(),
  alter column display_name set not null;

comment on column public.profiles.display_name is
  'Pseudo public du classement, unique (casse ignorée) ; seule donnée du profil visible des autres joueurs, via weekly_leaderboard().';

-- Inscription : réessaie si deux inscriptions simultanées tirent le même
-- pseudo (violation de l'index unique), au plus 3 fois.
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  for attempt in 1 .. 3 loop
    begin
      insert into public.profiles (id) values (new.id)
      on conflict (id) do nothing;
      return new;
    exception when unique_violation then
      if attempt = 3 then
        raise;
      end if;
    end;
  end loop;
  return new;
end;
$$;

revoke execute on function public.handle_new_user() from public, anon, authenticated;

-- Index ----------------------------------------------------------------------
--
-- Agrégation de la semaine (filtre sur `day`) en parcours d'index seul.
create index quiz_results_day_user_idx
  on public.quiz_results (day, user_id) include (xp, submitted_at);

-- Semaine (Europe/Paris) -----------------------------------------------------

-- Lundi de la semaine contenant l'instant `at`, à Paris. Fonction interne
-- (testée par pgTAP), non exposée aux clients.
create function public.leaderboard_week_start(at timestamptz)
returns date
language sql
stable
set search_path = ''
as $$
  select date_trunc('week', at at time zone 'Europe/Paris')::date;
$$;

revoke execute on function public.leaderboard_week_start(timestamptz)
  from public, anon, authenticated;

-- weekly_leaderboard() -------------------------------------------------------
--
-- Paramètre : `max_entries` (1 à 100, 50 par défaut ; hors bornes ramené
-- dans l'intervalle).
--
-- Retour :
-- { week_start: 'AAAA-MM-JJ' (lundi), week_end: 'AAAA-MM-JJ' (dimanche),
--   ends_at: lundi suivant 00:00 Paris (timestamptz),
--   entries: [{ rank, display_name, xp, is_me }]  (top N, ordre d'affichage),
--   me: { rank (null si aucune XP cette semaine), display_name, xp } }
--
-- Erreur : 42501 non authentifié.
create function public.weekly_leaderboard(max_entries integer default 50)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  max_xp_per_day constant integer := 1000;
  uid uuid := (select auth.uid());
  v_start date := public.leaderboard_week_start(now());
  v_limit integer := least(greatest(coalesce(max_entries, 50), 1), 100);
  v_entries jsonb;
  v_me jsonb;
begin
  if uid is null then
    raise exception 'non authentifié' using errcode = '42501';
  end if;

  -- Plafond propre au classement : 1 000 XP par joueur et par jour au plus
  -- (l'XP du profil n'est pas touchée).
  with daily as (
    select qr.user_id,
           least(sum(qr.xp), max_xp_per_day) as xp,
           max(qr.submitted_at) filter (where qr.xp > 0) as reached_at
      from public.quiz_results qr
     where qr.day between v_start and v_start + 6
     group by qr.user_id, qr.day
  ),
  totals as (
    select d.user_id,
           sum(d.xp)::integer as xp,
           max(d.reached_at) as reached_at
      from daily d
     group by d.user_id
    having sum(d.xp) > 0
  ),
  ranked as (
    select t.user_id,
           t.xp,
           p.display_name,
           rank() over (order by t.xp desc) as rank,
           row_number() over (order by t.xp desc, t.reached_at, t.user_id) as pos
      from totals t
      join public.profiles p on p.id = t.user_id
  )
  select
    coalesce(
      jsonb_agg(jsonb_build_object(
        'rank', r.rank,
        'display_name', r.display_name,
        'xp', r.xp,
        'is_me', r.user_id = uid
      ) order by r.pos) filter (where r.pos <= v_limit),
      '[]'::jsonb
    ),
    (select jsonb_build_object('rank', m.rank, 'xp', m.xp)
       from ranked m where m.user_id = uid)
  into v_entries, v_me
  from ranked r;

  v_me := coalesce(v_me, jsonb_build_object('rank', null, 'xp', 0))
    || jsonb_build_object(
         'display_name',
         (select p.display_name from public.profiles p where p.id = uid));

  return jsonb_build_object(
    'week_start', v_start,
    'week_end', v_start + 6,
    'ends_at', ((v_start + 7)::timestamp at time zone 'Europe/Paris'),
    'entries', v_entries,
    'me', v_me
  );
end;
$$;

revoke execute on function public.weekly_leaderboard(integer) from public, anon;
grant execute on function public.weekly_leaderboard(integer) to authenticated;
