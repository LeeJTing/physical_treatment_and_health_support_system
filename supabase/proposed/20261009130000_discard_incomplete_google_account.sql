-- PROPOSED, NOT APPLIED. Kept out of supabase/migrations/ so `supabase db push` cannot run it by accident.
-- Needs review and OK from Elwin and Jun Ting; then move it to migrations/ (PROJECT_STATE §11).
--
-- 1. discard_incomplete_google_account() — FR100_023 (UC100 A1.4 "Cancel Account Setup").
--    After the first Google sign-in the app asks for a username and a password (FR100_022). When the
--    patient cancels, the app calls this function, then signs out. It deletes the CALLER's own
--    auth user (public.account and everything below it go with it: on delete cascade), and only
--    while the account is still an unfinished Google sign-up:
--      * created by Google (raw_app_meta_data.provider = 'google'),
--      * no username chosen yet (the app writes user_metadata.username when setup finishes;
--        manual registration always has one),
--      * created in the last 24 hours.
--    Anything else is left alone and the function returns false. Until this is applied the app's
--    call fails quietly and the patient is only signed out (SupabaseAuthRepository.discardIncompleteAccount).
--
-- 2. FR100_017 (and leftovers of 1): a pg_cron job deletes, every hour, email sign-ups never
--    verified within 24 hours and Google sign-ups whose setup was never finished within 24 hours.
--    Needs the pg_cron extension (Supabase Dashboard -> Database -> Extensions -> pg_cron).

create or replace function public.discard_incomplete_google_account()
returns boolean
language plpgsql
security definer set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_deleted integer;
begin
  if v_uid is null then
    return false;
  end if;
  delete from auth.users u
   where u.id = v_uid
     and u.raw_app_meta_data ->> 'provider' = 'google'
     and coalesce(trim(u.raw_user_meta_data ->> 'username'), '') = ''
     and u.created_at > now() - interval '24 hours';
  get diagnostics v_deleted = row_count;
  return v_deleted > 0;
end;
$$;

revoke all on function public.discard_incomplete_google_account() from public, anon;
grant execute on function public.discard_incomplete_google_account() to authenticated;

-- FR100_017: hourly clean-up of accounts never completed within 24 hours.
create extension if not exists pg_cron with schema pg_catalog;

create or replace function private.delete_incomplete_accounts()
returns integer
language plpgsql
security definer set search_path = ''
as $$
declare
  v_deleted integer;
begin
  delete from auth.users u
   where u.created_at < now() - interval '24 hours'
     and (
       -- email sign-up whose code was never accepted (FR100_017)
       (coalesce(u.raw_app_meta_data ->> 'provider', 'email') = 'email' and u.email_confirmed_at is null)
       -- Google sign-up whose account setup was never finished (FR100_022 / FR100_023)
       or (u.raw_app_meta_data ->> 'provider' = 'google'
           and coalesce(trim(u.raw_user_meta_data ->> 'username'), '') = '')
     );
  get diagnostics v_deleted = row_count;
  return v_deleted;
end;
$$;

revoke all on function private.delete_incomplete_accounts() from public, anon, authenticated;

select cron.schedule(
  'delete-incomplete-accounts',
  '17 * * * *',
  $$select private.delete_incomplete_accounts();$$
);
