"""Build an account-scoped, repeatable presentation seed; never executes SQL.

Private input/output belongs under ignored build/. The caller must inspect the
generated manifest and obtain the account owner's consent before applying it.
The generator reuses the project's actual planner and catalogue, not an AI mock.
"""
from __future__ import annotations

import argparse
from datetime import date, datetime, time, timedelta, timezone
from decimal import Decimal, ROUND_HALF_UP
import json
from pathlib import Path
import sys
from uuid import UUID, uuid5

TAG = "presentation-demo-v1"
NAMESPACE = UUID("975c415a-b448-4807-81fe-1ca402225ad0")
LOCAL = timezone(timedelta(hours=8))
CORE = ("energy_kcal", "carb_g", "protein_g", "fat_g", "sodium_mg", "sugar_g")


def number(value):
    return float(Decimal(str(value)).quantize(Decimal("0.1"), rounding=ROUND_HALF_UP))


def instant(day, hour, minute=0, second=0):
    return datetime.combine(day, time(hour, minute, second), LOCAL).isoformat()


def sql_literal(value):
    return "'" + str(value).replace("'", "''") + "'"


def insert_sql(table, rows, key):
    if not rows:
        return ""
    columns = list(rows[0])
    assert all(set(r) == set(columns) for r in rows)
    payload = json.dumps(rows, separators=(",", ":"), ensure_ascii=False)
    assert "$demo_payload$" not in payload
    cols = ",".join(columns)
    projection = ",".join("now()" if table == "biometric_reading" and c == "imported_at" else c for c in columns)
    return (f"insert into public.{table} ({cols}) select {projection} from "
            f"jsonb_populate_recordset(null::public.{table},$demo_payload${payload}$demo_payload$::jsonb) "
            f"on conflict ({key}) do nothing;\n")


def build(context_path, server_root, output):
    source = json.loads(context_path.read_text(encoding="utf-8"))
    ctx = source["context"]
    account = ctx["account"]["account_id"]
    foods = {r["food_key"]: r for r in source["foods"]}
    blocked = set(ctx["restrictions"])
    prefix = f"{TAG}|{account}|2026-11-24|"
    uid = lambda name: str(uuid5(NAMESPACE, prefix + name))
    sys.dont_write_bytecode = True
    sys.path.insert(0, str(server_root))
    # The bundled Python can reuse the existing compatible scientific wheels.
    sys.path.append(str(server_root / ".venv/Lib/site-packages"))
    from app.food.planner import plan
    from app.food.targets import energy_target

    profile = dict(ctx["profile"], weight_kg=65.0, bmi=20.1, updated_at=datetime.now(LOCAL).isoformat(),
                   version=ctx["profile"]["version"] + 1)
    calories = energy_target(profile["age"], profile["gender"], 65.0,
                            profile["height_cm"], ctx["limitations"], ())
    assert calories == 2429
    limit_id = uid("safety-limit")
    safety = dict(ctx["limits"], safety_limit_id=limit_id, daily_calorie_target=calories,
                  is_current=True)
    start = date(2026, 10, 5)
    base_plan = plan({"plan_type": "WEEKLY", "start_date": start.isoformat(),
                     "today": "2026-11-24", "seed": 241105, "history": [],
                     "conditions": [], "restrictions": ctx["restrictions"],
                     "limitations": ctx["limitations"], "profile": profile,
                     "limits": {"daily_calorie_target": calories,
                                "daily_sodium_limit_mg": safety["daily_sodium_limit_mg"],
                                "daily_sugar_limit_g": safety["daily_sugar_limit_g"]}})

    def nutrients(key, grams):
        f = foods[key]
        return {n: number(Decimal(str(f[n + "_per_100g"])) * Decimal(str(grams)) / 100)
                for n in CORE}

    def allowed(key):
        f = foods[key]
        return not blocked.intersection(f["restrictions"]) and not f["needs_two_hands"]

    alternatives = {
        "BREAKFAST": [[("roti_canai", 180), ("teh_tarik", 350)],
                      [("roti_bakar_kaya", 150), ("kopi_susu", 300)],
                      [("mee_siam", 350), ("teh_tarik", 300)]],
        "LUNCH": [[("mee_goreng_mamak", 400), ("teh_o_ais_limau", 350)],
                  [("nasi_goreng_kampung", 400), ("teh_o_ais_limau", 400)],
                  [("nasi_tomato", 400), ("teh_o_ais_limau", 300)]],
        "DINNER": [[("maggi_goreng", 400), ("teh_tarik", 300)],
                   [("nasi_minyak", 400), ("tauhu_goreng", 120), ("kopi_susu", 250)],
                   [("mee_goreng_mamak", 400), ("telur_goreng", 100), ("teh_o_ais_limau", 350)]],
        "SNACK": [[("kuih_lapis", 200), ("kopi_susu", 250)],
                  [("kuih_keria", 180), ("teh_tarik", 250)],
                  [("kuih_bahulu", 150), ("teh_tarik", 250)]],
    }
    rows = {t: [] for t in ("diet_plan", "planned_meal", "meal_log", "meal_item",
                            "biometric_reading", "patient_plan", "exercise_session")}
    weeks = []
    day_summaries = []
    for week in range(3):
        first = start + timedelta(days=week * 7)
        plan_id = uid(f"plan-{week}")
        followed = 0
        for index, original in enumerate(base_plan["days"]):
            day = first + timedelta(days=index)
            plan_energy = log_energy = 0.0
            for slot_index, meal in enumerate(original["meals"]):
                slot = meal["meal_slot"]
                match = (week == 0 or (week == 2 and
                         (index in (0, 2) or (index in (4, 5, 6) and slot_index < 2))))
                followed += int(match)
                planned_keys = {i["food_key"] for i in meal["items"]}
                planned_ids = []
                for item_index, item in enumerate(meal["items"]):
                    key, grams = item["food_key"], item["portion_g"]
                    assert allowed(key), key
                    n = nutrients(key, grams)
                    plan_energy += n["energy_kcal"]
                    planned_id = uid(f"planned-{week}-{index}-{slot}-{item_index}")
                    planned_ids.append(planned_id)
                    rows["planned_meal"].append(dict(planned_meal_id=planned_id, diet_plan_id=plan_id,
                        food_id=foods[key]["food_id"], plan_date=day.isoformat(), meal_slot=slot,
                        portion_size_g=grams, energy_kcal=n["energy_kcal"], sodium_mg=n["sodium_mg"],
                        sugar_g=n["sugar_g"], is_locked=False, is_logged=match))
                if match:
                    portions = [(i["food_key"], i["portion_g"]) for i in meal["items"]]
                else:
                    choices = alternatives[slot]
                    rotated = choices[index % len(choices):] + choices[:index % len(choices)]
                    portions = next(p for p in rotated if all(allowed(k) for k, _ in p)
                                    and not planned_keys.intersection(k for k, _ in p))
                meal_id = uid(f"meal-{week}-{index}-{slot}")
                total = {n: 0.0 for n in CORE}
                for item_index, (key, grams) in enumerate(portions):
                    n = nutrients(key, grams)
                    total = {k: number(total[k] + n[k]) for k in CORE}
                    rows["meal_item"].append(dict(meal_item_id=uid(f"item-{week}-{index}-{slot}-{item_index}"),
                        meal_id=meal_id, food_id=foods[key]["food_id"], portion_size_g=grams,
                        **n, is_user_corrected=False,
                        recognition_details={"presentation_demo": True, "dataset": TAG}))
                log_energy += total["energy_kcal"]
                hour = {"BREAKFAST": 8, "LUNCH": 13, "DINNER": 19, "SNACK": 16}[slot]
                rows["meal_log"].append(dict(meal_id=meal_id, account_id=account,
                    planned_meal_id=planned_ids[0] if match else None, meal_type=slot,
                    entry_method="MANUAL", image_uri=None, recognition_confidence=None,
                    model_version=TAG, total_energy_kcal=total["energy_kcal"],
                    total_sodium_mg=total["sodium_mg"], total_sugar_g=total["sugar_g"],
                    consumed_at=instant(day, hour)))
            day_summaries.append({"date": day.isoformat(), "planned_kcal": number(plan_energy),
                                  "logged_kcal": number(log_energy)})
        slots = sum(len(d["meals"]) for d in base_plan["days"])
        assert slots == 28 and followed == (28, 0, 14)[week]
        rows["diet_plan"].append(dict(diet_plan_id=plan_id, account_id=account,
            safety_limit_id=limit_id, plan_type="WEEKLY", start_date=first.isoformat(),
            end_date=(first + timedelta(days=6)).isoformat(), adherence_rate=followed / slots,
            model_version=TAG, generated_at=instant(first - timedelta(days=1), 18)))
        weeks.append({"from": first.isoformat(), "to": (first + timedelta(days=6)).isoformat(),
                      "followed": followed, "different": slots - followed, "total": slots})

    for i in range(57):
        day = date(2026, 9, 28) + timedelta(days=i)
        phase = (day - start).days // 7
        wobble = (0, 2, -1, 1, -2, 0, 1)[i % 7]
        bp = 120 + wobble if phase == 0 else 128 + wobble if phase == 1 else 123 + wobble if phase == 2 else 121 + wobble
        dia = 78 + i % 3 if phase == 0 else 83 + i % 4 if phase == 1 else 80 + i % 3
        observations = [("BLOOD_PRESSURE", bp, dia, None, 7, 5, 47),
                        ("BLOOD_GLUCOSE", number(5.0 + (i % 5) * .1 + (.5 if phase == 1 else 0)), None, "FASTING", 7, 10, 43),
                        ("BODY_WEIGHT", number(67 - 2 * i / 56 + (i % 3 - 1) * .04), None, None, 7, 15, 49)]
        if 0 <= phase <= 2:
            for hour, offset in [(10, 0), (15, .2), (21, .1)]:
                observations.append(("BLOOD_GLUCOSE", number((5.8 if phase == 0 else 8.1 if phase == 1 else 6.7) + offset + (i % 4) * .15), None, "POST_MEAL", hour, 0, 17))
        for metric, value, secondary, context, hour, minute, second in observations:
            rows["biometric_reading"].append(dict(reading_id=uid(f"reading-{day}-{metric}-{hour}"),
                account_id=account, metric_type=metric, primary_value=value, secondary_value=secondary,
                measurement_context=context, source="IMPORT", source_device="Presentation demo (synthetic)",
                imported_at="2026-11-24T00:00:00+08:00", recorded_at=instant(day, hour, minute, second)))

    plans = {p["plan_name"]: p for p in source["treatments"]}
    historical = plans["Early Knee Recovery"]
    for week in range(7):
        first = start + timedelta(days=7 * week)
        pp = uid(f"treatment-{week}")
        rows["patient_plan"].append(dict(patient_plan_id=pp, account_id=account,
            plan_id=historical["plan_id"], suitability_score=None, progress_percentage=100,
            status="COMPLETED", selected_at=instant(first - timedelta(days=1), 18)))
        for stage, ex in enumerate(historical["exercises"]):
            day = first + timedelta(days=stage * 2)
            rows["exercise_session"].append(dict(session_id=uid(f"session-{week}-{stage}"),
                account_id=account, patient_plan_id=pp, exercise_id=ex["exercise"]["exercise_id"],
                completed_at=instant(day, 18), duration_sec=ex["prescribed_duration_sec"] + week * 3,
                repetitions_completed=ex["prescribed_repetitions"], completion_status="COMPLETED",
                posture_accuracy=number(82 + week * 1.5 + stage),
                posture_feedback="Presentation demo: synthetic completed exercise; not a measured posture result.",
                model_version=TAG))
    active = plans["Hip Stability"]
    pp = uid("treatment-active")
    rows["patient_plan"].append(dict(patient_plan_id=pp, account_id=account,
        plan_id=active["plan_id"], suitability_score=None, progress_percentage=66.67,
        status="ACTIVE", selected_at=instant(date(2026, 11, 21), 8)))
    for stage, day in enumerate([date(2026, 11, 21), date(2026, 11, 23)]):
        ex = active["exercises"][stage]
        rows["exercise_session"].append(dict(session_id=uid(f"session-active-{stage}"), account_id=account,
            patient_plan_id=pp, exercise_id=ex["exercise"]["exercise_id"], completed_at=instant(day, 18),
            duration_sec=ex["prescribed_duration_sec"], repetitions_completed=ex["prescribed_repetitions"],
            completion_status="COMPLETED", posture_accuracy=95 + stage,
            posture_feedback="Presentation demo: synthetic completed exercise; not a measured posture result.",
            model_version=TAG))

    output.mkdir(parents=True, exist_ok=True)
    data = dict(dataset=TAG, profile=profile, safety_limit=safety, rows=rows, weeks=weeks,
                days=day_summaries, planner_version=base_plan["model_version"])
    (output / "dataset.json").write_text(json.dumps(data, indent=2), encoding="utf-8")
    (output / "planner-result.json").write_text(json.dumps(base_plan, indent=2), encoding="utf-8")
    before = ctx["profile"]
    guard = f"""begin;
do $guard$ begin
  if (select count(*) from public.account where account_id={sql_literal(account)}::uuid and lower(email)=lower({sql_literal(ctx['account']['email'])})) <> 1 then raise exception 'Target account mismatch'; end if;
  if not exists(select 1 from public.safety_limit where safety_limit_id={sql_literal(limit_id)}::uuid) then
    if not exists(select 1 from public.health_profile where profile_id={sql_literal(before['profile_id'])}::uuid and account_id={sql_literal(account)}::uuid and version={before['version']} and weight_kg={before['weight_kg']}) then raise exception 'Profile changed; refresh the backup first'; end if;
    if exists(select 1 from public.diet_plan where account_id={sql_literal(account)}::uuid and start_date<=date '2026-10-25' and end_date>=date '2026-10-05' and model_version<>{sql_literal(TAG)}) then raise exception 'Existing plans overlap demo weeks'; end if;
    if exists(select 1 from public.meal_log where account_id={sql_literal(account)}::uuid and consumed_at>=timestamptz '2026-10-05 00:00:00+08' and consumed_at<timestamptz '2026-10-26 00:00:00+08' and coalesce(model_version,'')<>{sql_literal(TAG)}) then raise exception 'Existing meals overlap demo weeks'; end if;
    update public.health_profile set weight_kg=65,bmi=20.1,risk_level='Medium',is_complete=true,version={profile['version']},updated_at=now() where profile_id={sql_literal(before['profile_id'])}::uuid;
    update public.safety_limit set is_current=false where profile_id={sql_literal(before['profile_id'])}::uuid and is_current;
  elsif not exists(select 1 from public.health_profile where profile_id={sql_literal(before['profile_id'])}::uuid and version={profile['version']} and weight_kg=65) then raise exception 'Demo already seeded; profile changed since then';
  end if;
end $guard$;
"""
    sql = guard + insert_sql("safety_limit", [safety], "safety_limit_id")
    for table in ("diet_plan", "planned_meal", "meal_log", "meal_item", "biometric_reading", "patient_plan", "exercise_session"):
        sql += insert_sql(table, rows[table], next(iter(rows[table][0])))
    sql += "commit;\n"
    (output / "seed.sql").write_text(sql, encoding="utf-8")
    manifest = {"dataset": TAG, "weeks": weeks, "row_counts": {k: len(v) for k, v in rows.items()},
                "demo_weight_kg": 65, "daily_calorie_target": calories,
                "sql_bytes": len(sql.encode("utf-8")), "generated_ids": {t: [r[next(iter(r))] for r in v] for t, v in rows.items()}}
    (output / "manifest.json").write_text(json.dumps(manifest, indent=2), encoding="utf-8")
    # Prepared for a later explicit removal request; never executed by this tool.
    def ids(table):
        return "array[" + ",".join(sql_literal(x) for x in manifest["generated_ids"][table]) + "]::uuid[]"
    cleanup = f"""-- Removes only this generated history. Keeps the approved 65 kg profile.
-- Review before running; refresh Health Report afterwards to replace cached analysis.
begin;
do $guard$ begin
 if exists(select 1 from public.meal_log where planned_meal_id=any({ids('planned_meal')}) and not(meal_id=any({ids('meal_log')}))) then raise exception 'A later meal uses a demo plan; review before removal'; end if;
 if exists(select 1 from public.exercise_session where patient_plan_id=any({ids('patient_plan')}) and not(session_id=any({ids('exercise_session')}))) then raise exception 'A later exercise uses a demo plan; review before removal'; end if;
end $guard$;
"""
    for table in ("meal_item", "meal_log", "planned_meal", "diet_plan", "exercise_session", "patient_plan", "biometric_reading"):
        key = next(iter(rows[table][0]))
        cleanup += f"delete from public.{table} where {key}=any({ids(table)});\n"
    cleanup += "commit;\n"
    (output / "remove-demo-history.sql").write_text(cleanup, encoding="utf-8")
    print(json.dumps({k:v for k,v in manifest.items() if k != "generated_ids"}, indent=2))


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--context", type=Path, required=True)
    parser.add_argument("--server-root", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    build(args.context, args.server_root, args.output)
