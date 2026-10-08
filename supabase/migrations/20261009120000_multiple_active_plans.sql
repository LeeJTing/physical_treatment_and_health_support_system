-- APPLIED on 9 Oct 2026 by Elwin in the Supabase SQL editor (reviewed by the PC session); moved here from
-- supabase/proposed/. Idempotent: safe if `supabase db push` runs it again.
--
-- Multiple active plans (Elwin, 9 Oct 2026): a patient may follow several treatment plans at once,
-- within the app's PlanRules (no two plans with an overlapping body area AND the same goal; at most
-- 3 / 2 / 1 active plans for Low / Medium / High risk; one exercise per plan per day).
--
-- The core schema enforces "only one ACTIVE plan per patient" (Table 4.16) with a unique partial
-- index. Until this file is applied, adding a second plan fails with Postgres 23505 and the app says:
-- "Following more than one plan at a time is not switched on yet. You can replace your current plan
-- instead." Replacing a plan keeps working either way.

drop index if exists public.patient_plan_one_active;

-- Still never the SAME plan twice at once for one patient.
create unique index if not exists patient_plan_one_active_per_plan
  on public.patient_plan (account_id, plan_id)
  where status = 'ACTIVE';

-- Safety net in the database for the app's highest cap (3 active plans, Low risk). The per-risk
-- caps and the clash rule stay in the app, where the current health profile is known.
create or replace function public.patient_plan_active_cap()
returns trigger
language plpgsql
as $$
begin
  if new.status = 'ACTIVE' and (
       select count(*) from public.patient_plan
       where account_id = new.account_id
         and status = 'ACTIVE'
         and patient_plan_id <> new.patient_plan_id
     ) >= 3 then
    raise exception 'A patient can follow at most 3 plans at a time' using errcode = 'check_violation';
  end if;
  return new;
end;
$$;

drop trigger if exists patient_plan_active_cap on public.patient_plan;
create trigger patient_plan_active_cap
  before insert or update of status on public.patient_plan
  for each row execute function public.patient_plan_active_cap();
