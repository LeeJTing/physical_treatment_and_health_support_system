-- Row-level security, Data API grants and the account row created at sign-up.
--
-- Access model
--   * Catalogue and lookup tables: read-only for signed-in users. Written only
--     from the dashboard / seed with the service role.
--   * Patient tables: a signed-in user reads and writes only rows whose
--     account_id is their own auth.uid(). Child tables without account_id
--     (profile lists, safety limits, meal items, ...) check the parent row.
--   * anon (not signed in) gets nothing.
-- New tables are not exposed to the Data API by default (Supabase, May 2026),
-- so every grant below is explicit.

-- ---------------------------------------------------------------------------
-- Enable RLS on every table
-- ---------------------------------------------------------------------------
do $$
declare t text;
begin
  foreach t in array array[
    'account', 'health_profile', 'safety_limit', 'health_condition', 'profile_condition',
    'physical_limitation', 'profile_limitation', 'dietary_restriction', 'profile_restriction',
    'biometric_reading', 'exercise', 'treatment_plan', 'plan_exercise', 'patient_plan',
    'exercise_session', 'forecast', 'anomaly_event', 'health_analysis', 'chat_message',
    'reminder', 'notification_log', 'food_item', 'food_restriction', 'meal_log', 'meal_item',
    'suitability_verdict', 'diet_plan', 'planned_meal'
  ] loop
    execute format('alter table public.%I enable row level security', t);
    execute format('grant select, insert, update, delete on table public.%I to service_role', t);
  end loop;
end $$;

-- ---------------------------------------------------------------------------
-- Catalogue and lookups: read-only
-- ---------------------------------------------------------------------------
do $$
declare t text;
begin
  foreach t in array array[
    'health_condition', 'physical_limitation', 'dietary_restriction',
    'exercise', 'treatment_plan', 'plan_exercise', 'food_item', 'food_restriction'
  ] loop
    execute format('grant select on table public.%I to authenticated', t);
    execute format(
      'create policy "signed-in users read %1$s" on public.%1$I for select to authenticated using (true)', t);
  end loop;
end $$;

-- ---------------------------------------------------------------------------
-- Tables owned directly through account_id
-- ---------------------------------------------------------------------------
do $$
declare t text;
begin
  foreach t in array array[
    'health_profile', 'biometric_reading', 'patient_plan', 'exercise_session', 'forecast',
    'anomaly_event', 'health_analysis', 'chat_message', 'reminder', 'notification_log',
    'meal_log', 'diet_plan'
  ] loop
    execute format('grant select, insert, update, delete on table public.%I to authenticated', t);
    execute format(
      'create policy "owner reads %1$s" on public.%1$I for select to authenticated '
      'using ((select auth.uid()) = account_id)', t);
    execute format(
      'create policy "owner inserts %1$s" on public.%1$I for insert to authenticated '
      'with check ((select auth.uid()) = account_id)', t);
    execute format(
      'create policy "owner updates %1$s" on public.%1$I for update to authenticated '
      'using ((select auth.uid()) = account_id) with check ((select auth.uid()) = account_id)', t);
    execute format(
      'create policy "owner deletes %1$s" on public.%1$I for delete to authenticated '
      'using ((select auth.uid()) = account_id)', t);
  end loop;
end $$;

-- account: the row is created by the sign-up trigger below, so no insert or
-- delete from the app (deleting the auth user cascades). Only the columns the
-- app may change are updatable.
grant select on table public.account to authenticated;
grant update (username, health_source_connected, health_source_last_sync) on table public.account to authenticated;
create policy "owner reads account" on public.account for select to authenticated
  using ((select auth.uid()) = account_id);
create policy "owner updates account" on public.account for update to authenticated
  using ((select auth.uid()) = account_id) with check ((select auth.uid()) = account_id);

-- ---------------------------------------------------------------------------
-- Child tables: ownership through the parent row
-- ---------------------------------------------------------------------------

-- Is this profile the caller's? Used by the profile child tables.
-- security invoker: runs under the caller's RLS, so it can only ever see
-- the caller's own profile anyway.
create function public.owns_profile(p_profile_id uuid)
returns boolean
language sql stable security invoker set search_path = ''
as $$
  select exists (
    select 1 from public.health_profile hp
    where hp.profile_id = p_profile_id and hp.account_id = (select auth.uid())
  );
$$;

do $$
declare t text;
begin
  foreach t in array array['safety_limit', 'profile_condition', 'profile_limitation', 'profile_restriction'] loop
    execute format('grant select, insert, update, delete on table public.%I to authenticated', t);
    execute format(
      'create policy "owner reads %1$s" on public.%1$I for select to authenticated '
      'using (public.owns_profile(profile_id))', t);
    execute format(
      'create policy "owner inserts %1$s" on public.%1$I for insert to authenticated '
      'with check (public.owns_profile(profile_id))', t);
    execute format(
      'create policy "owner updates %1$s" on public.%1$I for update to authenticated '
      'using (public.owns_profile(profile_id)) with check (public.owns_profile(profile_id))', t);
    execute format(
      'create policy "owner deletes %1$s" on public.%1$I for delete to authenticated '
      'using (public.owns_profile(profile_id))', t);
  end loop;
end $$;

-- meal_item -> meal_log
grant select, insert, update, delete on table public.meal_item to authenticated;
create policy "owner manages meal_item" on public.meal_item for all to authenticated
  using (exists (select 1 from public.meal_log m where m.meal_id = meal_item.meal_id
                 and m.account_id = (select auth.uid())))
  with check (exists (select 1 from public.meal_log m where m.meal_id = meal_item.meal_id
                      and m.account_id = (select auth.uid())));

-- suitability_verdict -> meal_item -> meal_log
grant select, insert, update, delete on table public.suitability_verdict to authenticated;
create policy "owner manages suitability_verdict" on public.suitability_verdict for all to authenticated
  using (exists (select 1 from public.meal_item i join public.meal_log m on m.meal_id = i.meal_id
                 where i.meal_item_id = suitability_verdict.meal_item_id and m.account_id = (select auth.uid())))
  with check (exists (select 1 from public.meal_item i join public.meal_log m on m.meal_id = i.meal_id
                      where i.meal_item_id = suitability_verdict.meal_item_id and m.account_id = (select auth.uid())));

-- planned_meal -> diet_plan
grant select, insert, update, delete on table public.planned_meal to authenticated;
create policy "owner manages planned_meal" on public.planned_meal for all to authenticated
  using (exists (select 1 from public.diet_plan d where d.diet_plan_id = planned_meal.diet_plan_id
                 and d.account_id = (select auth.uid())))
  with check (exists (select 1 from public.diet_plan d where d.diet_plan_id = planned_meal.diet_plan_id
                      and d.account_id = (select auth.uid())));

-- ---------------------------------------------------------------------------
-- account row at sign-up
-- ---------------------------------------------------------------------------
-- Lives in a schema the Data API does not expose, so it cannot be called as
-- an RPC. security definer is needed because the trigger runs as the auth
-- service, which has no rights on public.account.
create schema if not exists private;
revoke all on schema private from public, anon, authenticated;

create function private.handle_new_user()
returns trigger
language plpgsql
security definer set search_path = ''
as $$
declare
  v_name text := coalesce(
    nullif(trim(new.raw_user_meta_data ->> 'username'), ''),
    nullif(trim(new.raw_user_meta_data ->> 'full_name'), ''),
    split_part(new.email, '@', 1)
  );
begin
  -- username must be 3 to 30 characters (FR100_002)
  if char_length(v_name) < 3 then
    v_name := rpad(v_name, 3, '_');
  end if;
  v_name := left(v_name, 30);
  insert into public.account (account_id, email, username, auth_provider, is_email_verified, created_at)
  values (
    new.id,
    new.email,
    v_name,
    case when new.raw_app_meta_data ->> 'provider' = 'google' then 'GOOGLE' else 'EMAIL' end,
    new.email_confirmed_at is not null,
    coalesce(new.created_at, now())
  );
  return new;
end;
$$;

-- Keeps is_email_verified and auth_provider in step with Supabase Auth
-- (code accepted: FR100_013; Google added to an email account: BOTH).
create function private.handle_user_updated()
returns trigger
language plpgsql
security definer set search_path = ''
as $$
declare
  v_providers jsonb := coalesce(new.raw_app_meta_data -> 'providers', '[]'::jsonb);
begin
  update public.account a
  set is_email_verified = new.email_confirmed_at is not null,
      email = new.email,
      auth_provider = case
        when v_providers ? 'email' and v_providers ? 'google' then 'BOTH'
        when v_providers ? 'google' then 'GOOGLE'
        else 'EMAIL'
      end
  where a.account_id = new.id;
  return new;
end;
$$;

revoke all on function private.handle_new_user() from public, anon, authenticated;
revoke all on function private.handle_user_updated() from public, anon, authenticated;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function private.handle_new_user();

create trigger on_auth_user_updated
  after update of email, email_confirmed_at, raw_app_meta_data on auth.users
  for each row execute function private.handle_user_updated();

-- ---------------------------------------------------------------------------
-- complete_exercise_session (ASR_04, FR300_11, FR300_21)
-- ---------------------------------------------------------------------------
-- Writes the session and, when given, the plan's new progress in one
-- transaction. security invoker: both writes go through the caller's RLS.
create function public.complete_exercise_session(
  p_session_id            uuid,
  p_exercise_id           uuid,
  p_completion_status     varchar,
  p_patient_plan_id       uuid default null,
  p_completed_at          timestamptz default null,
  p_duration_sec          integer default null,
  p_repetitions_completed smallint default null,
  p_posture_accuracy      numeric default null,
  p_posture_feedback      text default null,
  p_model_version         varchar default null,
  p_new_progress          numeric default null,
  p_new_plan_status       varchar default null
)
returns void
language plpgsql
security invoker set search_path = ''
as $$
begin
  insert into public.exercise_session (
    session_id, account_id, patient_plan_id, exercise_id, completed_at, duration_sec,
    repetitions_completed, completion_status, posture_accuracy, posture_feedback, model_version)
  values (
    p_session_id, (select auth.uid()), p_patient_plan_id, p_exercise_id, p_completed_at, p_duration_sec,
    p_repetitions_completed, p_completion_status, p_posture_accuracy, p_posture_feedback, p_model_version);

  if p_patient_plan_id is not null and p_new_progress is not null then
    update public.patient_plan
    set progress_percentage = p_new_progress,
        status = coalesce(p_new_plan_status, status)
    where patient_plan_id = p_patient_plan_id
      and account_id = (select auth.uid());
    if not found then
      raise exception 'patient plan % not found for this account', p_patient_plan_id
        using errcode = 'P0002';
    end if;
  end if;
end;
$$;

revoke all on function public.complete_exercise_session(
  uuid, uuid, varchar, uuid, timestamptz, integer, smallint, numeric, text, varchar, numeric, varchar
) from public, anon;
grant execute on function public.complete_exercise_session(
  uuid, uuid, varchar, uuid, timestamptz, integer, smallint, numeric, text, varchar, numeric, varchar
) to authenticated;

revoke all on function public.owns_profile(uuid) from public, anon;
grant execute on function public.owns_profile(uuid) to authenticated;
