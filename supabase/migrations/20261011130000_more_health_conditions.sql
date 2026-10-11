-- 11 Oct 2026: more health conditions (Elwin asked for them to be added to Supabase; PROJECT_STATE row 198).
-- Run in the SQL Editor after the earlier migrations. Safe to run again.
--
-- 1. health_condition: four more categories; each condition can carry the question the profile asks about
--    its status, and whether a doctor's (or surgeon's, midwife's) OK is needed before an exercise plan when
--    the answer is "no". Ten conditions and "Other" are added (sources in fyp-notes/Plan_Tailoring_Design.pdf
--    and Evidence_Plan_Tailoring.pdf).
-- 2. profile_condition: the patient's answer (is_controlled) and a note (what the "Other" condition is).
--    Existing rows count as controlled, so nobody's risk level or plans change until they edit the profile.
-- 3. exercise.body_position: how each exercise is done, so a condition can avoid a position (pregnancy:
--    lying on the back; a foot ulcer: standing).

alter table public.health_condition drop constraint if exists health_condition_category_check;
alter table public.health_condition add constraint health_condition_category_check
  check (category in ('CARDIOVASCULAR', 'METABOLIC', 'MUSCULOSKELETAL', 'RESPIRATORY',
                      'NEUROLOGICAL', 'RENAL', 'ONCOLOGY', 'REPRODUCTIVE', 'OTHER'));
alter table public.health_condition add column if not exists status_question varchar(100);
alter table public.health_condition add column if not exists needs_clearance boolean not null default false;

alter table public.profile_condition add column if not exists is_controlled boolean not null default true;
alter table public.profile_condition add column if not exists note varchar(100);

alter table public.exercise add column if not exists body_position varchar(12);
alter table public.exercise drop constraint if exists exercise_body_position_check;
alter table public.exercise add constraint exercise_body_position_check
  check (body_position is null
         or body_position in ('STANDING', 'SEATED', 'EITHER', 'SUPINE', 'ALL_FOURS', 'TABLE'));

insert into public.health_condition
  (condition_id, condition_code, condition_name, category, status_question, needs_clearance) values
  (1,  'HYPERTENSION',         'High blood pressure',                  'CARDIOVASCULAR', 'Is it under control with treatment?', true),
  (2,  'DIABETES',             'Diabetes Mellitus',                    'METABOLIC',      'Is it under control (no frequent low blood sugar)?', true),
  (3,  'HEART_DISEASE',        'Heart Disease',                        'CARDIOVASCULAR', 'Has your doctor said it is stable?', true),
  (4,  'STROKE',               'Stroke',                               'CARDIOVASCULAR', null, false),
  (5,  'ARTHRITIS',            'Arthritis',                            'MUSCULOSKELETAL', 'Is it settled now (no flare-up)?', false),
  (6,  'OSTEOPOROSIS',         'Osteoporosis',                         'MUSCULOSKELETAL', null, false),
  (7,  'ASTHMA',               'Asthma',                               'RESPIRATORY',    'Is it under control with treatment?', true),
  (8,  'PREGNANCY',            'Pregnancy or recent birth',            'REPRODUCTIVE',   'Has your doctor or midwife said exercise is safe for you?', true),
  (9,  'JOINT_REPLACEMENT',    'Hip, knee or shoulder replacement',    'MUSCULOSKELETAL', 'Has your surgeon or physiotherapist cleared you to exercise at home?', true),
  (10, 'RHEUMATOID_ARTHRITIS', 'Rheumatoid arthritis',                 'MUSCULOSKELETAL', 'Is it settled now (no flare-up)?', false),
  (11, 'COPD',                 'Chronic lung disease (COPD)',          'RESPIRATORY',    'Is it stable (no flare-up in the last 4 weeks)?', true),
  (12, 'CANCER',               'Cancer (now or in the past)',          'ONCOLOGY',       'Has your doctor cleared you to exercise?', true),
  (13, 'KIDNEY_DISEASE',       'Chronic kidney disease',               'RENAL',          'Is it stable under your doctor''s care?', false),
  (14, 'PARKINSONS',           'Parkinson''s disease',                 'NEUROLOGICAL',   null, false),
  (15, 'MULTIPLE_SCLEROSIS',   'Multiple sclerosis',                   'NEUROLOGICAL',   'Is it stable (no relapse in the last month)?', true),
  (16, 'FOOT_ULCER',           'Foot ulcer or open wound on the foot', 'METABOLIC',      null, false),
  (17, 'OTHER',                'Other condition (not listed)',         'OTHER',          'Has your doctor cleared you to exercise?', true)
on conflict (condition_id) do update set
  condition_code = excluded.condition_code, condition_name = excluded.condition_name,
  category = excluded.category, status_question = excluded.status_question,
  needs_clearance = excluded.needs_clearance;

update public.exercise e set body_position = v.pos
  from (values ('sit_to_stand', 'STANDING'), ('shoulder_abduction', 'STANDING'), ('shoulder_flexion', 'STANDING'),
               ('hip_abduction', 'STANDING'), ('knee_extension', 'SEATED'), ('elbow_flexion', 'EITHER'),
               ('wall_push_up', 'STANDING'), ('heel_raise', 'STANDING'), ('mini_squat', 'STANDING'),
               ('seated_marching', 'SEATED'), ('glute_bridge', 'SUPINE'), ('tandem_stance', 'STANDING'),
               ('bird_dog', 'ALL_FOURS'), ('step_up', 'STANDING'), ('march_in_place', 'STANDING'),
               ('wrist_extension', 'TABLE'), ('hand_open_close', 'TABLE')) as v(key, pos)
 where e.pose_key = v.key;
