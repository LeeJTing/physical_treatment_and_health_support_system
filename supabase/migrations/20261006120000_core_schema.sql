-- APTHS core schema: the 28 entities of the report's Chapter 4 ERD
-- (attribute specifications Tables 4.81 to 4.108), in dependency order.
--
-- Deliberate differences from the report, each marked "-- NOTE" below:
--   * account.account_id is the Supabase Auth user id, and password_hash is
--     not stored: Supabase Auth keeps the (bcrypt) password hash in auth.users.
--   * FKs written as "REFERENCES patient_treatment_plan" point at patient_plan,
--     the table's actual name in Table 4.94.
--   * Extra columns the code needs (supabase/HANDOFF.md):
--     health_profile.version, exercise.pose_key, treatment_plan.goal.
--   * CHECKs on body-area codes, which the recommender relies on.
--   * "Only one ACTIVE plan per patient" (Table 4.94) is a partial unique index.

-- ---------------------------------------------------------------------------
-- M100 Personalised Health Profiling
-- ---------------------------------------------------------------------------

create table public.account (
  -- NOTE: same id as auth.users, so auth.uid() identifies the row.
  account_id              uuid primary key references auth.users (id) on delete cascade,
  email                   varchar(255) not null unique,
  username                varchar(30)  not null check (char_length(username) between 3 and 30),
  -- NOTE: password_hash omitted; Supabase Auth stores it.
  auth_provider           varchar(10)  not null check (auth_provider in ('EMAIL', 'GOOGLE', 'BOTH')),
  is_email_verified       boolean      not null default false,
  health_source_connected boolean      not null default false,
  health_source_last_sync timestamptz,
  created_at              timestamptz  not null default now()
);

create table public.health_profile (
  profile_id  uuid primary key default gen_random_uuid(),
  account_id  uuid         not null unique references public.account (account_id) on delete cascade,
  age         smallint     not null check (age between 13 and 120),
  gender      varchar(6)   not null check (gender in ('Male', 'Female')),
  weight_kg   numeric(5,2) not null check (weight_kg between 20 and 300),
  height_cm   numeric(5,2) not null check (height_cm between 80 and 250),
  bmi         numeric(4,1) not null,
  risk_level  varchar(6)   not null check (risk_level in ('Low', 'Medium', 'High')),
  is_complete boolean      not null default false,
  version     integer      not null default 0, -- NOTE: FR100_053 profile version (HANDOFF.md)
  updated_at  timestamptz  not null default now()
);

create table public.safety_limit (
  safety_limit_id          uuid primary key default gen_random_uuid(),
  profile_id               uuid         not null references public.health_profile (profile_id) on delete cascade,
  max_exercise_intensity   varchar(10)  not null check (max_exercise_intensity in ('LOW', 'MODERATE', 'VIGOROUS')),
  max_session_duration_min smallint     not null check (max_session_duration_min > 0),
  daily_calorie_target     integer      not null,
  daily_sodium_limit_mg    integer      not null,
  daily_sugar_limit_g      numeric(5,1) not null,
  is_current               boolean      not null default true
);
create index safety_limit_profile_idx on public.safety_limit (profile_id);
-- One set in force per profile; older sets are kept for old plans.
create unique index safety_limit_one_current on public.safety_limit (profile_id) where is_current;

create table public.health_condition (
  condition_id   smallint primary key,
  condition_code varchar(20) not null unique,
  condition_name varchar(50) not null,
  category       varchar(20) not null
    check (category in ('CARDIOVASCULAR', 'METABOLIC', 'MUSCULOSKELETAL', 'RESPIRATORY'))
);

create table public.profile_condition (
  profile_id   uuid     not null references public.health_profile (profile_id) on delete cascade,
  condition_id smallint not null references public.health_condition (condition_id),
  primary key (profile_id, condition_id)
);

create table public.physical_limitation (
  limitation_id   smallint primary key,
  limitation_code varchar(30) not null unique,
  limitation_name varchar(60) not null,
  category        varchar(10) not null check (category in ('MOBILITY', 'BALANCE'))
);

create table public.profile_limitation (
  profile_id    uuid     not null references public.health_profile (profile_id) on delete cascade,
  limitation_id smallint not null references public.physical_limitation (limitation_id),
  primary key (profile_id, limitation_id)
);

create table public.dietary_restriction (
  restriction_id   smallint primary key,
  restriction_code varchar(20) not null unique,
  restriction_name varchar(50) not null,
  restriction_type varchar(12) not null check (restriction_type in ('ALLERGY', 'INTOLERANCE', 'DIET', 'RELIGIOUS'))
);

create table public.profile_restriction (
  profile_id     uuid     not null references public.health_profile (profile_id) on delete cascade,
  restriction_id smallint not null references public.dietary_restriction (restriction_id),
  primary key (profile_id, restriction_id)
);

-- ---------------------------------------------------------------------------
-- M200 Health Monitoring and Tracking
-- ---------------------------------------------------------------------------

create table public.biometric_reading (
  reading_id          uuid primary key default gen_random_uuid(),
  account_id          uuid         not null references public.account (account_id) on delete cascade,
  metric_type         varchar(15)  not null check (metric_type in ('BLOOD_PRESSURE', 'BLOOD_GLUCOSE', 'BODY_WEIGHT')),
  primary_value       numeric(6,2) not null,
  secondary_value     numeric(6,2) check (secondary_value < primary_value),
  measurement_context varchar(12)  check (measurement_context in ('FASTING', 'POST_MEAL', 'RANDOM')),
  source              varchar(6)   not null check (source in ('MANUAL', 'IMPORT')),
  -- NOTE: 5-minute allowance for a phone clock slightly ahead of the server (FR200_006).
  recorded_at         timestamptz  not null check (recorded_at <= now() + interval '5 minutes'),
  unique (account_id, metric_type, recorded_at)
);

-- ---------------------------------------------------------------------------
-- M300 Physical Treatment and M500 AI-Assisted Treatment Planning
-- ---------------------------------------------------------------------------

create table public.exercise (
  exercise_id          uuid primary key default gen_random_uuid(),
  exercise_name        varchar(100) not null unique,
  instruction_text     text         not null,
  target_body_area     varchar(30)  not null check (target_body_area in
    ('LEFT_ARM', 'RIGHT_ARM', 'BOTH_ARMS', 'LEFT_LEG', 'RIGHT_LEG', 'BOTH_LEGS', 'CORE', 'FULL_BODY')), -- NOTE
  intensity_level      varchar(10)  not null check (intensity_level in ('LOW', 'MODERATE', 'VIGOROUS')),
  default_repetitions  smallint     not null,
  default_duration_sec integer      not null,
  pose_key             varchar(30)  -- NOTE: posture model key on the AI server (HANDOFF.md)
);

create table public.treatment_plan (
  plan_id            uuid primary key default gen_random_uuid(),
  plan_name          varchar(100) not null,
  aim                text         not null,
  target_body_area   varchar(30)  not null check (target_body_area in
    ('LEFT_ARM', 'RIGHT_ARM', 'BOTH_ARMS', 'LEFT_LEG', 'RIGHT_LEG', 'BOTH_LEGS', 'CORE', 'FULL_BODY')), -- NOTE
  recovery_stage     varchar(15)  not null check (recovery_stage in ('EARLY', 'INTERMEDIATE', 'ADVANCED')),
  mobility_level     varchar(10)  not null check (mobility_level in ('LOW', 'MODERATE', 'HIGH')),
  frequency_per_week smallint     not null check (frequency_per_week between 1 and 7),
  goal               varchar(15)  check (goal in ('STRENGTH', 'MOBILITY', 'BALANCE', 'PAIN_RELIEF', 'ENDURANCE')) -- NOTE
);

create table public.plan_exercise (
  plan_id                 uuid     not null references public.treatment_plan (plan_id) on delete cascade,
  exercise_id             uuid     not null references public.exercise (exercise_id),
  sequence_order          smallint not null,
  prescribed_repetitions  smallint not null,
  prescribed_duration_sec integer  not null,
  primary key (plan_id, exercise_id),
  unique (plan_id, sequence_order)
);
create index plan_exercise_exercise_idx on public.plan_exercise (exercise_id);

create table public.patient_plan (
  patient_plan_id     uuid primary key default gen_random_uuid(),
  account_id          uuid         not null references public.account (account_id) on delete cascade,
  plan_id             uuid         not null references public.treatment_plan (plan_id),
  suitability_score   numeric(5,2),
  progress_percentage numeric(5,2) not null default 0 check (progress_percentage between 0 and 100),
  status              varchar(10)  not null check (status in ('ACTIVE', 'COMPLETED', 'ABANDONED')),
  selected_at         timestamptz  not null default now()
);
create index patient_plan_account_idx on public.patient_plan (account_id);
create index patient_plan_plan_idx on public.patient_plan (plan_id);
-- NOTE: "Only one ACTIVE plan per patient" (Table 4.94).
create unique index patient_plan_one_active on public.patient_plan (account_id) where status = 'ACTIVE';

create table public.exercise_session (
  session_id            uuid primary key default gen_random_uuid(),
  account_id            uuid         not null references public.account (account_id) on delete cascade,
  patient_plan_id       uuid         references public.patient_plan (patient_plan_id) on delete set null, -- NOTE
  exercise_id           uuid         not null references public.exercise (exercise_id),
  completed_at          timestamptz,
  duration_sec          integer,
  repetitions_completed smallint,
  completion_status     varchar(10)  not null check (completion_status in ('COMPLETED', 'RETRIED', 'ABANDONED')),
  posture_accuracy      numeric(5,2) check (posture_accuracy between 0 and 100),
  posture_feedback      text,
  model_version         varchar(20)
);
create index exercise_session_account_idx on public.exercise_session (account_id, completed_at desc);
create index exercise_session_plan_idx on public.exercise_session (patient_plan_id);
create index exercise_session_exercise_idx on public.exercise_session (exercise_id);

-- ---------------------------------------------------------------------------
-- M400 Predictive Health Analysis
-- ---------------------------------------------------------------------------

create table public.forecast (
  forecast_id         uuid primary key default gen_random_uuid(),
  account_id          uuid        not null references public.account (account_id) on delete cascade,
  metric_type         varchar(15) not null check (metric_type in ('BLOOD_PRESSURE', 'BLOOD_GLUCOSE', 'BODY_WEIGHT')),
  predicted_values    jsonb       not null,
  input_reading_count smallint    not null,
  model_version       varchar(20) not null,
  is_current          boolean     not null default true,
  generated_at        timestamptz not null default now()
);
create index forecast_account_idx on public.forecast (account_id, metric_type) where is_current;

create table public.anomaly_event (
  anomaly_id       uuid primary key default gen_random_uuid(),
  account_id       uuid        not null references public.account (account_id) on delete cascade,
  reading_id       uuid        references public.biometric_reading (reading_id) on delete set null,
  metric_type      varchar(15) not null,
  anomaly_type     varchar(16) not null check (anomaly_type in ('DEVIATION', 'SUSTAINED_TREND')),
  severity         varchar(6)  not null check (severity in ('Low', 'Medium', 'High')),
  explanation_text text        not null,
  detected_at      timestamptz not null default now()
);
create index anomaly_event_account_idx on public.anomaly_event (account_id, detected_at desc);
create index anomaly_event_reading_idx on public.anomaly_event (reading_id);

create table public.health_analysis (
  analysis_id          uuid primary key default gen_random_uuid(),
  account_id           uuid        not null references public.account (account_id) on delete cascade,
  analysis_date        date        not null,
  health_score         smallint    check (health_score between 0 and 100),
  score_band           varchar(10) check (score_band in ('POOR', 'FAIR', 'GOOD', 'EXCELLENT')),
  factor_contributions jsonb,
  condition_risks      jsonb,
  period_comparison    varchar(10) check (period_comparison in ('BETTER', 'UNCHANGED', 'WORSE')),
  summary_text         text,
  model_version        varchar(20) not null,
  unique (account_id, analysis_date)
);

-- ---------------------------------------------------------------------------
-- M500 chat and M600 Notification and Alert
-- ---------------------------------------------------------------------------

create table public.chat_message (
  message_id        uuid primary key default gen_random_uuid(),
  account_id        uuid        not null references public.account (account_id) on delete cascade,
  patient_plan_id   uuid        references public.patient_plan (patient_plan_id) on delete set null, -- NOTE
  sender            varchar(7)  not null check (sender in ('PATIENT', 'SYSTEM')),
  question_category varchar(50),
  message_text      text        not null,
  is_matched        boolean     not null default true,
  created_at        timestamptz not null default now()
);
create index chat_message_account_idx on public.chat_message (account_id, created_at);
create index chat_message_plan_idx on public.chat_message (patient_plan_id);

create table public.reminder (
  reminder_id     uuid primary key default gen_random_uuid(),
  account_id      uuid         not null references public.account (account_id) on delete cascade,
  patient_plan_id uuid         references public.patient_plan (patient_plan_id) on delete cascade, -- NOTE
  reminder_type   varchar(10)  not null check (reminder_type in ('EXERCISE', 'HEALTH_LOG', 'MEAL')),
  title           varchar(100) not null,
  scheduled_time  time         not null,
  repeat_days     char(7)      not null default '1111111' check (repeat_days ~ '^[01]{7}$'),
  is_enabled      boolean      not null default true
);
create index reminder_account_idx on public.reminder (account_id);
create index reminder_plan_idx on public.reminder (patient_plan_id);

create table public.notification_log (
  notification_id   uuid primary key default gen_random_uuid(),
  account_id        uuid        not null references public.account (account_id) on delete cascade,
  reminder_id       uuid        references public.reminder (reminder_id) on delete set null,
  anomaly_id        uuid        references public.anomaly_event (anomaly_id) on delete set null,
  notification_type varchar(8)  not null check (notification_type in ('REMINDER', 'ALERT')),
  severity          varchar(6)  check (severity in ('Low', 'Medium', 'High')),
  message_body      text        not null,
  delivery_status   varchar(10) not null check (delivery_status in ('DELIVERED', 'FAILED', 'SUPPRESSED')),
  is_read           boolean     not null default false,
  issued_at         timestamptz not null default now()
);
create index notification_log_account_idx on public.notification_log (account_id, issued_at desc);
create index notification_log_unread_idx on public.notification_log (account_id) where not is_read;
create index notification_log_reminder_idx on public.notification_log (reminder_id);
create index notification_log_anomaly_idx on public.notification_log (anomaly_id);

-- ---------------------------------------------------------------------------
-- M700 Diet Support
-- ---------------------------------------------------------------------------

create table public.food_item (
  food_id              uuid primary key default gen_random_uuid(),
  food_name            varchar(100) not null unique,
  food_category        varchar(40)  not null,
  base_serving_g       numeric(6,2) not null,
  energy_kcal_per_100g numeric(6,2) not null,
  carb_g_per_100g      numeric(6,2) not null,
  protein_g_per_100g   numeric(6,2) not null,
  fat_g_per_100g       numeric(6,2) not null,
  sodium_mg_per_100g   numeric(7,2) not null,
  sugar_g_per_100g     numeric(6,2) not null
);

create table public.food_restriction (
  food_id        uuid     not null references public.food_item (food_id) on delete cascade,
  restriction_id smallint not null references public.dietary_restriction (restriction_id),
  primary key (food_id, restriction_id)
);
create index food_restriction_restriction_idx on public.food_restriction (restriction_id);

create table public.diet_plan (
  diet_plan_id    uuid primary key default gen_random_uuid(),
  account_id      uuid         not null references public.account (account_id) on delete cascade,
  safety_limit_id uuid         not null references public.safety_limit (safety_limit_id),
  plan_type       varchar(8)   not null check (plan_type in ('DAILY', 'WEEKLY')),
  start_date      date         not null,
  end_date        date         not null check (end_date >= start_date),
  adherence_rate  numeric(5,2),
  model_version   varchar(20)  not null,
  generated_at    timestamptz  not null default now()
);
create index diet_plan_account_idx on public.diet_plan (account_id, start_date desc);
create index diet_plan_limit_idx on public.diet_plan (safety_limit_id);

-- Created before meal_log, which references it.
create table public.planned_meal (
  planned_meal_id uuid primary key default gen_random_uuid(),
  diet_plan_id    uuid         not null references public.diet_plan (diet_plan_id) on delete cascade,
  food_id         uuid         not null references public.food_item (food_id),
  plan_date       date         not null,
  meal_slot       varchar(10)  not null check (meal_slot in ('BREAKFAST', 'LUNCH', 'DINNER', 'SNACK')),
  portion_size_g  numeric(6,2) not null check (portion_size_g > 0),
  energy_kcal     numeric(7,2) not null,
  sodium_mg       numeric(8,2) not null,
  sugar_g         numeric(6,2) not null,
  is_locked       boolean      not null default false,
  is_logged       boolean      not null default false
);
create index planned_meal_plan_idx on public.planned_meal (diet_plan_id, plan_date);
create index planned_meal_food_idx on public.planned_meal (food_id);

create table public.meal_log (
  meal_id                uuid primary key default gen_random_uuid(),
  account_id             uuid         not null references public.account (account_id) on delete cascade,
  planned_meal_id        uuid         references public.planned_meal (planned_meal_id) on delete set null,
  meal_type              varchar(10)  not null check (meal_type in ('BREAKFAST', 'LUNCH', 'DINNER', 'SNACK')),
  entry_method           varchar(12)  not null check (entry_method in ('RECOGNITION', 'MANUAL')),
  image_uri              varchar(255),
  recognition_confidence numeric(4,3),
  model_version          varchar(20),
  total_energy_kcal      numeric(7,2) not null default 0,
  total_sodium_mg        numeric(8,2) not null default 0,
  total_sugar_g          numeric(6,2) not null default 0,
  consumed_at            timestamptz  not null
);
create index meal_log_account_idx on public.meal_log (account_id, consumed_at desc);
create index meal_log_planned_idx on public.meal_log (planned_meal_id);

create table public.meal_item (
  meal_item_id      uuid primary key default gen_random_uuid(),
  meal_id           uuid         not null references public.meal_log (meal_id) on delete cascade,
  food_id           uuid         not null references public.food_item (food_id),
  portion_size_g    numeric(6,2) not null check (portion_size_g > 0),
  energy_kcal       numeric(7,2) not null,
  carb_g            numeric(6,2) not null,
  protein_g         numeric(6,2) not null,
  fat_g             numeric(6,2) not null,
  sodium_mg         numeric(8,2) not null,
  sugar_g           numeric(6,2) not null,
  is_user_corrected boolean      not null default false
);
create index meal_item_meal_idx on public.meal_item (meal_id);
create index meal_item_food_idx on public.meal_item (food_id);

create table public.suitability_verdict (
  verdict_id        uuid primary key default gen_random_uuid(),
  meal_item_id      uuid        not null references public.meal_item (meal_item_id) on delete cascade,
  condition_id      smallint    references public.health_condition (condition_id),
  restriction_id    smallint    references public.dietary_restriction (restriction_id),
  verdict           varchar(12) not null check (verdict in ('SUITABLE', 'CAUTION', 'NOT_SUITABLE')),
  reason_text       text        not null,
  suggested_food_id uuid        references public.food_item (food_id),
  -- "Exactly one" of condition or restriction raised the verdict (Table 4.106).
  check (num_nonnulls(condition_id, restriction_id) = 1)
);
create index suitability_verdict_item_idx on public.suitability_verdict (meal_item_id);
create index suitability_verdict_condition_idx on public.suitability_verdict (condition_id);
create index suitability_verdict_restriction_idx on public.suitability_verdict (restriction_id);
create index suitability_verdict_food_idx on public.suitability_verdict (suggested_food_id);
