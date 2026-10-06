-- Lookup lists for the profile screen. Run after the migrations, before
-- seed_catalogue.sql. Values match LookupSeed in lib/data/models/lookups.dart.

begin;

-- Table 3.3 / UC300 C6: Health Condition List
insert into public.health_condition (condition_id, condition_code, condition_name, category) values
  (1, 'HYPERTENSION',  'High blood pressure', 'CARDIOVASCULAR'),
  (2, 'DIABETES',      'Diabetes Mellitus',   'METABOLIC'),
  (3, 'HEART_DISEASE', 'Heart Disease',       'CARDIOVASCULAR'),
  (4, 'STROKE',        'Stroke',              'CARDIOVASCULAR'),
  (5, 'ARTHRITIS',     'Arthritis',           'MUSCULOSKELETAL'),
  (6, 'OSTEOPOROSIS',  'Osteoporosis',        'MUSCULOSKELETAL'),
  (7, 'ASTHMA',        'Asthma',              'RESPIRATORY')
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
