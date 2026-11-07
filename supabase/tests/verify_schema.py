"""Applies supabase/migrations and supabase/seed to a throwaway local Postgres
with a minimal stand-in for Supabase's auth schema and roles, then checks the
sign-up trigger, RLS isolation between two users, constraints and the RPC.

Run:  pip install pgserver "psycopg[binary]"
      python supabase/tests/verify_schema.py .
"""
import shutil, sys, tempfile, uuid
from pathlib import Path

import pgserver
import psycopg

REPO = Path(sys.argv[1])
data = Path(tempfile.mkdtemp())
srv = pgserver.get_server(data, cleanup_mode="stop")
url = srv.get_uri()
conn = psycopg.connect(url, autocommit=True)
x = conn.execute
print("Postgres", conn.execute("show server_version").fetchone()[0])

# --- Supabase stand-in ---------------------------------------------------
x("""
create role anon nologin; create role authenticated nologin; create role service_role nologin bypassrls;
grant usage on schema public to anon, authenticated, service_role;
create schema auth;
grant usage on schema auth to anon, authenticated;
create table auth.users (
  id uuid primary key, email text, raw_user_meta_data jsonb default '{}', raw_app_meta_data jsonb default '{}',
  email_confirmed_at timestamptz, created_at timestamptz default now());
create function auth.uid() returns uuid language sql stable as
  $$ select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid $$;
grant execute on function auth.uid() to anon, authenticated;
""")

for f in sorted((REPO / "supabase" / "migrations").glob("*.sql")):
    x(f.read_text(encoding="utf-8")); print("applied", f.name)
for f in ["seed_lookups.sql", "seed_catalogue.sql", "seed_food.sql"]:
    x((REPO / "supabase" / "seed" / f).read_text(encoding="utf-8")); print("seeded", f)

ok = 0
def check(label, cond):
    global ok
    if not cond:
        raise SystemExit(f"FAIL: {label}")
    ok += 1; print("  ok -", label)

def expect_error(label, sql, params=()):
    global ok
    try:
        x(sql, params)
    except psycopg.Error as e:
        ok += 1; print("  ok -", label, "->", type(e).__name__); return
    raise SystemExit(f"FAIL (no error): {label}")

def as_user(uid):
    x("reset role"); x("select set_config('request.jwt.claim.sub', %s, false)", (str(uid),)); x("set role authenticated")

def as_admin():
    x("reset role"); x("select set_config('request.jwt.claim.sub', '', false)")

# --- sign-up trigger -----------------------------------------------------
a, b, g = uuid.uuid4(), uuid.uuid4(), uuid.uuid4()
x("insert into auth.users (id, email, raw_user_meta_data, raw_app_meta_data) values (%s,'a@x.com','{\"username\":\"alice\"}','{\"provider\":\"email\",\"providers\":[\"email\"]}')", (a,))
x("insert into auth.users (id, email, raw_app_meta_data) values (%s,'bo@x.com','{\"provider\":\"email\",\"providers\":[\"email\"]}')", (b,))
x("insert into auth.users (id, email, raw_user_meta_data, raw_app_meta_data, email_confirmed_at) values (%s,'g@x.com','{\"full_name\":\"Gee Google\"}','{\"provider\":\"google\",\"providers\":[\"google\"]}', now())", (g,))
rows = dict((str(r[0]), r[1:]) for r in x("select account_id, username, auth_provider, is_email_verified from public.account").fetchall())
check("account row per sign-up", len(rows) == 3)
check("username from metadata", rows[str(a)][0] == "alice")
check("short email name padded to 3 chars", rows[str(b)][0] == "bo_")
check("Google sign-up is GOOGLE and verified", rows[str(g)][1:] == ("GOOGLE", True))
x("update auth.users set email_confirmed_at = now() where id = %s", (a,))
check("confirming the code sets is_email_verified", x("select is_email_verified from public.account where account_id=%s", (a,)).fetchone()[0])
x("""update auth.users set raw_app_meta_data = '{"provider":"email","providers":["email","google"]}' where id = %s""", (a,))
check("linking Google gives BOTH", x("select auth_provider from public.account where account_id=%s", (a,)).fetchone()[0] == "BOTH")

# --- anon ------------------------------------------------------------------
x("reset role"); x("set role anon")
expect_error("anon cannot read the catalogue", "select * from public.treatment_plan")
expect_error("anon cannot read accounts", "select * from public.account")

# --- user A ------------------------------------------------------------------
as_user(a)
# Counts from the catalogue itself (11 plans and 17 exercises since 9 Oct).
_cat = __import__("json").loads((REPO / "assets" / "seed" / "catalogue.json").read_text(encoding="utf-8"))
check(f"A reads the {len(_cat['plans'])} seeded plans",
      x("select count(*) from public.treatment_plan").fetchone()[0] == len(_cat["plans"]))
check(f"A reads {len(_cat['exercises'])} exercises",
      x("select count(*) from public.exercise").fetchone()[0] == len(_cat["exercises"]))
check("A sees only own account", x("select count(*) from public.account").fetchone()[0] == 1)
expect_error("A cannot change own email column", "update public.account set email='z@x.com'")
x("update public.account set username='alice2'")
check("A can rename", x("select username from public.account").fetchone()[0] == "alice2")
expect_error("A cannot write the catalogue", "insert into public.health_condition values (99,'X','X','METABOLIC')")

pa = uuid.uuid4()
x("insert into public.health_profile (profile_id, account_id, age, gender, weight_kg, height_cm, bmi, risk_level, is_complete) values (%s,%s,58,'Male',72,170,24.9,'Low',true)", (pa, a))
x("insert into public.safety_limit (profile_id, max_exercise_intensity, max_session_duration_min, daily_calorie_target, daily_sodium_limit_mg, daily_sugar_limit_g) values (%s,'MODERATE',45,1900,2000,50)", (pa,))
x("insert into public.profile_condition values (%s, 2)", (pa,))
expect_error("profile age 12 rejected (CHECK)", "insert into public.health_profile (account_id, age, gender, weight_kg, height_cm, bmi, risk_level) values (%s,12,'Male',72,170,24.9,'Low')", (a,))
# Limits = the largest ever recorded (14 Oct): 272 cm and 635 kg accepted, one more rejected.
x("update public.health_profile set height_cm=272, weight_kg=635, bmi=85.8 where profile_id=%s", (pa,))
check("272 cm and 635 kg accepted", x("select height_cm, weight_kg from public.health_profile where profile_id=%s", (pa,)).fetchone() == (272, 635))
expect_error("273 cm rejected (CHECK)", "update public.health_profile set height_cm=273 where profile_id=%s", (pa,))
expect_error("636 kg rejected (CHECK)", "update public.health_profile set weight_kg=636 where profile_id=%s", (pa,))
x("update public.health_profile set height_cm=170, weight_kg=72, bmi=24.9 where profile_id=%s", (pa,))
expect_error("A cannot create a profile for B", "insert into public.health_profile (account_id, age, gender, weight_kg, height_cm, bmi, risk_level) values (%s,58,'Male',72,170,24.9,'Low')", (b,))
expect_error("second current safety limit rejected", "insert into public.safety_limit (profile_id, max_exercise_intensity, max_session_duration_min, daily_calorie_target, daily_sodium_limit_mg, daily_sugar_limit_g) values (%s,'LOW',20,1600,1500,25)", (pa,))

plan = x("select plan_id from public.treatment_plan where plan_name='Early Knee Recovery'").fetchone()[0]
ex = x("select exercise_id from public.plan_exercise where plan_id=%s order by sequence_order limit 1", (plan,)).fetchone()[0]
ppa = uuid.uuid4()
x("insert into public.patient_plan (patient_plan_id, account_id, plan_id, suitability_score, status) values (%s,%s,%s,1.0,'ACTIVE')", (ppa, a, plan))
expect_error("second ACTIVE plan rejected", "insert into public.patient_plan (account_id, plan_id, status) values (%s,%s,'ACTIVE')", (a, plan))
x("insert into public.reminder (account_id, patient_plan_id, reminder_type, title, scheduled_time, repeat_days) values (%s,%s,'EXERCISE','Time for it','09:00:00','1010100')", (a, ppa))
expect_error("bad repeat_days mask rejected", "insert into public.reminder (account_id, reminder_type, title, scheduled_time, repeat_days) values (%s,'EXERCISE','t','09:00','10101')", (a,))

x("select public.complete_exercise_session(%s,%s,'COMPLETED',%s,now(),90,10::smallint,86.5,null,'pose-v1',33.33,null)", (uuid.uuid4(), ex, ppa))
check("RPC wrote the session", x("select count(*) from public.exercise_session").fetchone()[0] == 1)
check("RPC advanced the plan", float(x("select progress_percentage from public.patient_plan").fetchone()[0]) == 33.33)

# --- user B ------------------------------------------------------------------
as_user(b)
check("B sees no profiles", x("select count(*) from public.health_profile").fetchone()[0] == 0)
check("B sees no safety limits", x("select count(*) from public.safety_limit").fetchone()[0] == 0)
check("B sees no condition declarations", x("select count(*) from public.profile_condition").fetchone()[0] == 0)
check("B sees no sessions", x("select count(*) from public.exercise_session").fetchone()[0] == 0)
x("update public.patient_plan set progress_percentage = 100")  # silently 0 rows
expect_error("B cannot advance A's plan through the RPC",
             "select public.complete_exercise_session(%s,%s,'COMPLETED',%s,now(),90,10::smallint,90,null,'v',66,null)", (uuid.uuid4(), ex, ppa))
expect_error("B cannot add to A's safety limits", "insert into public.safety_limit (profile_id, max_exercise_intensity, max_session_duration_min, daily_calorie_target, daily_sodium_limit_mg, daily_sugar_limit_g, is_current) values (%s,'LOW',20,1600,1500,25,false)", (pa,))
expect_error("B cannot call the sign-up trigger function", "select private.handle_new_user()")

as_admin()
check("A's plan untouched by B", float(x("select progress_percentage from public.patient_plan").fetchone()[0]) == 33.33)

# --- 11 Oct: more conditions, their status, exercise positions ---------------
check("17 health conditions, each status question set where a doctor's OK is needed",
      x("select count(*), count(*) filter (where needs_clearance and status_question is null) from public.health_condition").fetchone() == (17, 0))
check("every exercise has a body position",
      x("select count(*) from public.exercise where body_position is null").fetchone()[0] == 0)
check("pregnancy avoids the only exercise on the back (Glute Bridge)",
      x("select string_agg(exercise_name, ',') from public.exercise where body_position = 'SUPINE'").fetchone()[0] == "Glute Bridge")
check("a profile's condition is controlled unless the patient says no",
      x("select column_default from information_schema.columns where table_name='profile_condition' and column_name='is_controlled'").fetchone()[0] == "true")
expect_error("an unknown body position is refused",
             "update public.exercise set body_position = 'HANDSTAND' where pose_key = 'bird_dog'")

# --- 26 Oct: M200 / M400 / M700 (Jun Ting) ------------------------------------
check("209 foods with a key, a plan role and meal slots",
      x("select count(*), count(food_key), count(*) filter (where cardinality(meal_slots) > 0) from public.food_item where food_key is not null").fetchone() == (209, 209, 209))
check("10 dietary restrictions", x("select count(*) from public.dietary_restriction").fetchone()[0] == 10)
check("nasi lemak breaches peanut", x("select count(*) from public.food_restriction fr join public.food_item f using (food_id) join public.dietary_restriction d using (restriction_id) where f.food_key='nasi_lemak' and d.restriction_code='PEANUT'").fetchone()[0] == 1)
sl = x("select safety_limit_id from public.safety_limit sl join public.health_profile hp using (profile_id) where hp.account_id=%s limit 1", (a,)).fetchone()
nasi = x("select food_id from public.food_item where food_key='nasi_lemak'").fetchone()[0]
as_user(a)
x("insert into public.biometric_reading (account_id, metric_type, primary_value, secondary_value, source, recorded_at) values (%s,'BLOOD_PRESSURE',128,82,'MANUAL',now() - interval '1 hour')", (a,))
expect_error("a duplicate reading (same metric and time) is refused",
             "insert into public.biometric_reading (account_id, metric_type, primary_value, secondary_value, source, recorded_at) select account_id, metric_type, 120, 80, 'IMPORT', recorded_at from public.biometric_reading limit 1")
x("insert into public.forecast (account_id, metric_type, predicted_values, input_reading_count, model_version) values (%s,'BLOOD_PRESSURE','{\"points\":[]}',14,'forecast-gbdt-1.0')", (a,))
x("insert into public.health_analysis (account_id, analysis_date, health_score, score_band, model_version) values (%s, current_date, 72, 'FAIR', 'analysis-1.0+health-score-1.0+risk-gbdt-nhanes-1.0')", (a,))
expect_error("an old score band is refused", "insert into public.health_analysis (account_id, analysis_date, score_band, model_version) values (%s, current_date - 1, 'EXCELLENT', 'v')", (a,))
mid = uuid.uuid4(); iid = uuid.uuid4()
x("insert into public.meal_log (meal_id, account_id, meal_type, entry_method, recognition_confidence, model_version, total_energy_kcal, total_sodium_mg, total_sugar_g, consumed_at) values (%s,%s,'BREAKFAST','RECOGNITION',0.82,'food-clip-vitb16-head-1',450,750,3.8,now())", (mid, a))
x("insert into public.meal_item (meal_item_id, meal_id, food_id, portion_size_g, energy_kcal, carb_g, protein_g, fat_g, sodium_mg, sugar_g) values (%s,%s,%s,250,450,55,13.8,20,750,3.8)", (iid, mid, nasi))
x("insert into public.suitability_verdict (meal_item_id, condition_id, verdict, reason_text) values (%s,1,'NOT_SUITABLE','high in sodium')", (iid,))
if sl:
    did = uuid.uuid4()
    x("insert into public.diet_plan (diet_plan_id, account_id, safety_limit_id, plan_type, start_date, end_date, model_version) values (%s,%s,%s,'DAILY',current_date,current_date,'diet-planner-1.0+pref-logreg-1')", (did, a, sl[0]))
    x("insert into public.planned_meal (diet_plan_id, food_id, plan_date, meal_slot, portion_size_g, energy_kcal, sodium_mg, sugar_g) values (%s,%s,current_date,'LUNCH',250,450,750,3.8)", (did, nasi))
    check("A's plan stored with its planned meal", x("select count(*) from public.planned_meal").fetchone()[0] == 1)
check("A sees the meal with its item and verdict",
      x("select count(*) from public.meal_log m join public.meal_item i using (meal_id) join public.suitability_verdict v using (meal_item_id)").fetchone()[0] == 1)
as_user(b)
check("B sees none of A's readings, meals, verdicts, plans or analyses",
      x("select (select count(*) from public.biometric_reading) + (select count(*) from public.meal_log) + (select count(*) from public.meal_item) + (select count(*) from public.suitability_verdict) + (select count(*) from public.diet_plan) + (select count(*) from public.health_analysis) + (select count(*) from public.forecast)").fetchone()[0] == 0)
expect_error("B cannot add an item to A's meal", "insert into public.meal_item (meal_id, food_id, portion_size_g, energy_kcal, carb_g, protein_g, fat_g, sodium_mg, sugar_g) values (%s,%s,100,1,1,1,1,1,1)", (mid, nasi))
check("B reads the food catalogue", x("select count(*) from public.food_item").fetchone()[0] >= 209)
as_admin()

# --- deleting the auth user cascades -----------------------------------------
x("delete from auth.users where id = %s", (a,))
check("account deletion cascades to all A's data",
      x("select (select count(*) from public.account where account_id=%s) + (select count(*) from public.health_profile) + (select count(*) from public.patient_plan) + (select count(*) from public.exercise_session)", (a,)).fetchone()[0] == 0)

print(f"\nALL {ok} CHECKS PASSED")
conn.close(); srv.cleanup(); shutil.rmtree(data, ignore_errors=True)
