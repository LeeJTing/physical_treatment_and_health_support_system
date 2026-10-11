-- PROPOSED, NOT APPLIED. Kept out of supabase/migrations/ so `supabase db push` cannot run it by accident.
-- Elwin agreed the table on 10-11 Oct (PROJECT_STATE rows 192, 197); apply it in the SQL Editor, then move
-- this file to migrations/. Until it is applied the app keeps working: the terms screen is skipped when the
-- table cannot be read, and "Delete my account" reports that it could not delete.
--
-- 1. terms_acceptance: one row per acceptance of the Terms of Use and Privacy Notice (assets/legal/terms.json).
--    A record, so the patient can insert and read their own rows but never change or delete them; the rows
--    go when the account is deleted (on delete cascade). The health-data consent is separate and explicit
--    (PDPA 2010 s.40); users aged 13 to 17 record the parent or guardian who agreed (PDP Regulations 2013).
-- 2. delete_my_account(): "Delete my account" in Profile. Deletes the CALLER's own auth user; public.account
--    and every table below it go with it (on delete cascade).
-- 3. Retention (Privacy Notice section 5): a pg_cron job deletes, once a day, accounts not signed in to for
--    2 years. Needs the pg_cron extension (Dashboard -> Database -> Extensions -> pg_cron).

create table if not exists public.terms_acceptance (
  acceptance_id          uuid         primary key default gen_random_uuid(),
  account_id             uuid         not null references public.account (account_id) on delete cascade,
  terms_version          text         not null,
  accepted_at            timestamptz  not null default now(),
  language               text         not null default 'en' check (language in ('en', 'ms')),
  health_data_consent    boolean      not null check (health_data_consent),
  age_group              text         not null check (age_group in ('ADULT', 'MINOR')),
  guardian_name          text,
  guardian_relationship  text         check (guardian_relationship in ('PARENT', 'GUARDIAN')),
  -- A minor's acceptance names the parent or guardian who agreed.
  constraint terms_acceptance_guardian check (
    age_group = 'ADULT'
    or (coalesce(trim(guardian_name), '') <> '' and guardian_relationship is not null)
  )
);

create index if not exists terms_acceptance_account_idx
  on public.terms_acceptance (account_id, accepted_at desc);

alter table public.terms_acceptance enable row level security;

create policy "owner reads terms_acceptance" on public.terms_acceptance
  for select to authenticated using ((select auth.uid()) = account_id);
create policy "owner inserts terms_acceptance" on public.terms_acceptance
  for insert to authenticated with check ((select auth.uid()) = account_id);
-- No update or delete policy: an acceptance is a record.

grant select, insert on public.terms_acceptance to authenticated;

-- 2. Delete my account ------------------------------------------------------------------------------------

create or replace function public.delete_my_account()
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
  delete from auth.users u where u.id = v_uid;
  get diagnostics v_deleted = row_count;
  return v_deleted > 0;
end;
$$;

revoke all on function public.delete_my_account() from public, anon;
grant execute on function public.delete_my_account() to authenticated;

-- 3. Retention: accounts unused for 2 years -----------------------------------------------------------------

create extension if not exists pg_cron with schema pg_catalog;
create schema if not exists private;

create or replace function private.delete_unused_accounts()
returns integer
language plpgsql
security definer set search_path = ''
as $$
declare
  v_deleted integer;
begin
  delete from auth.users u
   where coalesce(u.last_sign_in_at, u.created_at) < now() - interval '2 years';
  get diagnostics v_deleted = row_count;
  return v_deleted;
end;
$$;

revoke all on function private.delete_unused_accounts() from public, anon, authenticated;

select cron.schedule(
  'delete-unused-accounts',
  '41 3 * * *',
  $$select private.delete_unused_accounts();$$
);
