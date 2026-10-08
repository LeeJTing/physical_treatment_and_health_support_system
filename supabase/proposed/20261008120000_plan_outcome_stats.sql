-- PROPOSED, NOT APPLIED. Kept out of supabase/migrations/ so `supabase db push` cannot run it by accident.
-- Needs review and OK from Elwin and Jun Ting; then move it to migrations/ (PROJECT_STATE §11).
--
-- plan_outcome_stats(): anonymised evidence for the collaborative part of the hybrid recommender
-- (M500, FR500_05, report 2.7 / Table 2.7). RLS keeps patient_plan and exercise_session owner-only,
-- so a patient's app cannot read other patients' outcomes. This read-only SECURITY DEFINER function
-- returns per-plan aggregates only, grouped by risk level and age band, and drops every cell with
-- fewer than 5 distinct patients (k-anonymity). No account id, date or free text leaves the database.
--
-- Columns map to ai_server/app/recommend/schemas.py PlanOutcomeIn:
--   plan_id, risk_level ('Low'|'Medium'|'High'), age_band ('<60'|'60-74'|'75+'), patients,
--   completion_rate (0..1), mean_accuracy (0..100 or null), mean_progress (0..100 or null).

create or replace function public.plan_outcome_stats()
returns table (
  plan_id         uuid,
  risk_level      varchar,
  age_band        text,
  patients        integer,
  completion_rate numeric,
  mean_accuracy   numeric,
  mean_progress   numeric
)
language sql
stable
security definer
set search_path = public
as $$
  with assignment as (
    select pp.patient_plan_id, pp.account_id, pp.plan_id, pp.progress_percentage,
           hp.risk_level,
           case when hp.age < 60 then '<60' when hp.age < 75 then '60-74' else '75+' end as age_band
    from public.patient_plan pp
    join public.health_profile hp on hp.account_id = pp.account_id
  ),
  per_assignment as (
    select a.plan_id, a.risk_level, a.age_band, a.account_id, a.progress_percentage,
           count(s.session_id)                                               as sessions,
           count(s.session_id) filter (where s.completion_status = 'COMPLETED') as completed,
           avg(s.posture_accuracy) filter (where s.completion_status = 'COMPLETED') as accuracy
    from assignment a
    left join public.exercise_session s on s.patient_plan_id = a.patient_plan_id
    group by a.plan_id, a.risk_level, a.age_band, a.account_id, a.patient_plan_id, a.progress_percentage
  )
  select plan_id,
         risk_level,
         age_band,
         count(distinct account_id)::integer                                   as patients,
         round(coalesce(sum(completed)::numeric / nullif(sum(sessions), 0), 0), 3) as completion_rate,
         round(avg(accuracy), 2)                                               as mean_accuracy,
         round(avg(progress_percentage), 2)                                    as mean_progress
  from per_assignment
  group by plan_id, risk_level, age_band
  having count(distinct account_id) >= 5;
$$;

revoke all on function public.plan_outcome_stats() from public, anon;
grant execute on function public.plan_outcome_stats() to authenticated;
