create table public.recovery_check_in (
  check_in_id uuid primary key default gen_random_uuid(),
  account_id uuid not null references public.account(account_id) on delete cascade,
  patient_plan_id uuid not null references public.patient_plan(patient_plan_id) on delete cascade,
  check_in_date date not null check (check_in_date <= (now() at time zone 'Asia/Kuala_Lumpur')::date),
  pain smallint not null check (pain between 0 and 10),
  stiffness smallint not null check (stiffness between 0 and 10),
  difficulty smallint not null check (difficulty between 1 and 5),
  notes text not null default '' check (char_length(notes) <= 500),
  is_demo boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (account_id,patient_plan_id,check_in_date)
);
create index recovery_check_in_account_date on public.recovery_check_in(account_id,check_in_date);
alter table public.recovery_check_in enable row level security;
revoke all on public.recovery_check_in from anon;
grant select,insert,update,delete on public.recovery_check_in to authenticated;
grant all on public.recovery_check_in to service_role;
create policy "owner reads recovery check-ins" on public.recovery_check_in for select to authenticated
  using (account_id=(select auth.uid()));
create policy "owner inserts recovery check-ins" on public.recovery_check_in for insert to authenticated
  with check (account_id=(select auth.uid()) and exists (
    select 1 from public.patient_plan p where p.patient_plan_id=recovery_check_in.patient_plan_id
      and p.account_id=(select auth.uid())
      and recovery_check_in.check_in_date >= (p.selected_at at time zone 'Asia/Kuala_Lumpur')::date));
create policy "owner updates recovery check-ins" on public.recovery_check_in for update to authenticated
  using (account_id=(select auth.uid()))
  with check (account_id=(select auth.uid()) and exists (
    select 1 from public.patient_plan p where p.patient_plan_id=recovery_check_in.patient_plan_id
      and p.account_id=(select auth.uid())
      and recovery_check_in.check_in_date >= (p.selected_at at time zone 'Asia/Kuala_Lumpur')::date));
create policy "owner deletes recovery check-ins" on public.recovery_check_in for delete to authenticated
  using (account_id=(select auth.uid()));
create function public.recovery_check_in_updated_at() returns trigger
  language plpgsql security invoker set search_path='' as $$
begin
  new.updated_at=now();
  return new;
end;
$$;
revoke execute on function public.recovery_check_in_updated_at() from public,anon,authenticated;
create trigger recovery_check_in_updated_at before update on public.recovery_check_in
  for each row execute function public.recovery_check_in_updated_at();
comment on table public.recovery_check_in is 'Self-reported symptoms per treatment assignment and local calendar date. Does not advance or alter treatment plans.';
