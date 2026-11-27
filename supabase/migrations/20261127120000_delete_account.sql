-- Suppression de compte (T13 : App Store 5.1.1(v), Google Play).
--
-- `delete_account()` supprime l'utilisateur connecté de `auth.users`. Les
-- données suivent par clé étrangère :
-- - `on delete cascade` : profiles, quiz_results, quiz_sessions (et
--   quiz_session_questions), offline_days, sessions et jetons Auth ;
-- - `on delete set null` : question_reports (signalement gardé, anonyme).
-- Le classement hebdo est calculé à partir de quiz_results : le joueur en
-- disparaît aussitôt.
--
-- Comptes anonymes seulement pour l'instant. Avec la liaison Apple (T12),
-- il faudra aussi révoquer le jeton Apple (TN3194) : cela demandera une
-- Edge Function (clé privée Apple, jamais en base ni dans l'app).
--
-- Erreurs : 42501 non authentifié.
create function public.delete_account()
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
  delete from auth.users u where u.id = uid;
end;
$$;

comment on function public.delete_account() is
  'Supprime le compte connecté et ses données (cascade). T13.';

revoke execute on function public.delete_account() from public, anon;
grant execute on function public.delete_account() to authenticated;
