-- Lookup lists for the profile screen. Run after the migrations, before
-- seed_catalogue.sql. Values match LookupSeed in lib/data/models/lookups.dart.

begin;

-- Table 3.3 / UC300 C6, and the conditions added on 11 Oct (migration 20261011130000).
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
on conflict (condition_id) do nothing;

-- Table 3.3 / UC300 C7: Physical Limitation List. BALANCE_IMPAIRMENT is not in
-- C7, but Table 4.86's category CHECK and the risk rule set (FR100_054) both
-- use a balance limitation, so it is included. Remove it if the list in C7 is final.
insert into public.physical_limitation (limitation_id, limitation_code, limitation_name, category) values
  (1, 'LEFT_ARM_MOBILITY',  'Left Arm Mobility Limitation',  'MOBILITY'),
  (2, 'RIGHT_ARM_MOBILITY', 'Right Arm Mobility Limitation', 'MOBILITY'),
  (3, 'LEFT_LEG_MOBILITY',  'Left Leg Mobility Limitation',  'MOBILITY'),
  (4, 'RIGHT_LEG_MOBILITY', 'Right Leg Mobility Limitation', 'MOBILITY'),
  (5, 'BALANCE_IMPAIRMENT', 'Balance Impairment',            'BALANCE')
on conflict (limitation_id) do nothing;

-- Table 4.88 gives only examples (PEANUT, SHELLFISH, VEGAN, HALAL; VEGETARIAN
-- in Table 4.103). The full list belongs to M700: confirm with Jun Ting.
insert into public.dietary_restriction (restriction_id, restriction_code, restriction_name, restriction_type) values
  (1, 'PEANUT',     'Peanut allergy',    'ALLERGY'),
  (2, 'SHELLFISH',  'Shellfish allergy', 'ALLERGY'),
  (3, 'VEGAN',      'Vegan',             'DIET'),
  (4, 'VEGETARIAN', 'Vegetarian',        'DIET'),
  (5, 'HALAL',      'Halal',             'RELIGIOUS')
on conflict (restriction_id) do nothing;

commit;
