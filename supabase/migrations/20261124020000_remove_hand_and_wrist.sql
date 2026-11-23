-- 24 Nov 2026 (Elwin): Wrist Extension and Hand Open and Close were never tested on a real person's
-- video (only on a public stroke data set), so they and the Hand and Wrist Recovery plan come out of
-- the catalogue: 15 exercises and 10 plans remain (supabase/seed/build_seed.py, seed_catalogue.sql).
--
-- On 24 Nov no patient had the plan (0 patient_plan rows) and no session used either exercise.
-- patient_plan and exercise_session reference these rows with ON DELETE NO ACTION, so if that has
-- changed, the deletes below fail and nothing is removed; plan_exercise rows go with the plan.
BEGIN;

DELETE FROM plan_exercise
WHERE plan_id = '665e8567-b75b-565f-b6e3-85bdb1e6538b'          -- Hand and Wrist Recovery
   OR exercise_id IN ('d0a54f13-94f7-5f98-820a-b9ea0b9818ab',   -- Wrist Extension
                      '00c205b4-5b48-5ceb-828a-e7b6366a4128');  -- Hand Open and Close

DELETE FROM treatment_plan
WHERE plan_id = '665e8567-b75b-565f-b6e3-85bdb1e6538b';

DELETE FROM exercise
WHERE exercise_id IN ('d0a54f13-94f7-5f98-820a-b9ea0b9818ab',
                      '00c205b4-5b48-5ceb-828a-e7b6366a4128');

COMMIT;
