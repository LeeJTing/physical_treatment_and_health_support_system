"""Builds the treatment catalogue seed from one source.

Outputs
  ../../assets/seed/catalogue.json       used by the app's fake repositories
  seed_catalogue.sql                     hand to whoever sets up Supabase

Run:  python build_seed.py
IDs are uuid5 of the name, so re-running gives the same IDs.
"""
import json
import uuid
from pathlib import Path

NS = uuid.UUID("6f1c2a52-4b7e-4f0e-9c1a-0a5e7d3b2c11")


def uid(kind, name):
    return str(uuid.uuid5(NS, f"{kind}:{name}"))


# name, body area, intensity, reps, duration_sec, pose_key, instructions
EXERCISES = [
    ("Sit-to-Stand", "BOTH_LEGS", "LOW", 10, 90, "sit_to_stand",
     "Camera: side view, whole body in frame. Sit on a firm chair with feet flat and hip-width apart. Lean slightly forward and stand up fully "
     "without using your hands, then sit back down slowly. Safety: keep a stable chair against a wall; "
     "stop if you feel dizzy or knee pain."),
    ("Shoulder Abduction", "BOTH_ARMS", "LOW", 10, 60, "shoulder_abduction",
     "Camera: facing you, whole body in frame. Stand tall with arms by your sides. Raise both arms out to the side up to shoulder height with "
     "elbows straight, hold for one second, and lower slowly. Safety: do not raise above a pain-free range."),
    ("Shoulder Flexion", "BOTH_ARMS", "LOW", 10, 60, "shoulder_flexion",
     "Camera: side view, whole body in frame. Stand with arms by your sides. Raise both arms forward and up to shoulder height "
     "with elbows straight and thumbs up, hold for one second, and lower slowly. Safety: do not arch the back."),
    ("Standing Hip Abduction", "BOTH_LEGS", "LOW", 10, 90, "hip_abduction",
     "Camera: facing you, whole body in frame. Stand beside a chair and hold it for support. Lift one leg out to the side keeping the toes "
     "forward and the body upright, then lower it. Repeat on the other side. Safety: do not lean the trunk."),
    ("Seated Knee Extension", "BOTH_LEGS", "LOW", 12, 90, "knee_extension",
     "Camera: side view, whole body in frame. Sit upright on a chair. Straighten one knee until the leg is level with the hip, hold for two "
     "seconds, and lower slowly. Alternate legs. Safety: keep the back against the chair."),
    ("Elbow Flexion", "BOTH_ARMS", "LOW", 12, 60, None,
     "Stand or sit with arms by your sides, palms forward. Bend the elbows to bring the hands toward the "
     "shoulders, then lower slowly. Use a light bottle of water if comfortable."),
    ("Wall Push-Up", "BOTH_ARMS", "MODERATE", 10, 90, None,
     "Stand an arm's length from a wall with palms on the wall at shoulder height. Bend the elbows to bring "
     "the chest toward the wall, then push back. Safety: keep the body straight."),
    ("Heel Raise", "BOTH_LEGS", "LOW", 12, 60, None,
     "Stand behind a chair holding the back of it. Rise onto your toes, hold for one second, and lower "
     "slowly. Safety: keep holding the chair throughout."),
    ("Mini Squat", "BOTH_LEGS", "MODERATE", 10, 90, None,
     "Stand with feet shoulder-width apart holding a support. Bend the knees about 30 degrees keeping the "
     "heels down, then stand up. Safety: knees must not pass the toes."),
    ("Seated Marching", "BOTH_LEGS", "LOW", 20, 90, None,
     "Sit upright on a chair. Lift one knee toward the chest, lower it, and alternate legs at a steady pace."),
    ("Shoulder Pendulum", "BOTH_ARMS", "LOW", 10, 60, None,
     "Lean forward supporting yourself on a table with one hand. Let the other arm hang and swing it gently "
     "in small circles. Change arms halfway."),
    ("Glute Bridge", "CORE", "MODERATE", 10, 90, None,
     "Lie on your back with knees bent and feet flat. Squeeze the buttocks and lift the hips until the body "
     "is straight from shoulders to knees, then lower slowly."),
    ("Tandem Stance", "BOTH_LEGS", "LOW", 4, 120, None,
     "Stand next to a counter. Place one foot directly in front of the other, heel touching toe, and hold "
     "for 30 seconds. Switch feet. Safety: always keep one hand near the support."),
    ("Pelvic Tilt", "CORE", "LOW", 10, 60, None,
     "Lie on your back with knees bent. Tighten the stomach and flatten the lower back into the floor, "
     "hold for five seconds, then relax."),
    ("Step-Up", "BOTH_LEGS", "MODERATE", 10, 120, None,
     "Stand facing a low step holding a rail. Step up with one foot, bring the other up, then step down. "
     "Alternate the leading leg. Safety: use a step no higher than 15 cm."),
    ("March in Place", "FULL_BODY", "MODERATE", 30, 120, None,
     "Stand tall and march on the spot, lifting the knees and swinging the arms at a comfortable pace."),
]

# name, aim, body area, stage, mobility, freq/week, goal, [(exercise, reps, duration_sec)]
PLANS = [
    ("Early Knee Recovery", "Restore knee range of motion and reduce stiffness in the early stage of recovery.",
     "BOTH_LEGS", "EARLY", "LOW", 3, "MOBILITY",
     [("Seated Knee Extension", 10, 90), ("Seated Marching", 16, 90), ("Heel Raise", 10, 60)]),
    ("Lower Limb Strength Builder", "Build thigh and hip strength for standing up, walking and climbing stairs.",
     "BOTH_LEGS", "INTERMEDIATE", "MODERATE", 3, "STRENGTH",
     [("Sit-to-Stand", 10, 90), ("Mini Squat", 10, 90), ("Step-Up", 8, 120)]),
    ("Shoulder Mobility Starter", "Regain gentle shoulder movement after a period of reduced arm use.",
     "BOTH_ARMS", "EARLY", "LOW", 5, "MOBILITY",
     [("Shoulder Pendulum", 10, 60), ("Shoulder Flexion", 8, 60), ("Shoulder Abduction", 8, 60)]),
    ("Upper Limb Strength", "Strengthen the arms and shoulders for daily tasks such as lifting and reaching.",
     "BOTH_ARMS", "INTERMEDIATE", "MODERATE", 3, "STRENGTH",
     [("Elbow Flexion", 12, 60), ("Shoulder Flexion", 10, 60), ("Shoulder Abduction", 10, 60), ("Wall Push-Up", 10, 90)]),
    ("Hip Stability", "Improve hip control and single-leg stability to support safer walking.",
     "BOTH_LEGS", "INTERMEDIATE", "MODERATE", 3, "BALANCE",
     [("Standing Hip Abduction", 10, 90), ("Tandem Stance", 4, 120), ("Glute Bridge", 10, 90)]),
    ("Balance and Fall Prevention", "Reduce the risk of falls by training balance and lower-limb control.",
     "FULL_BODY", "EARLY", "LOW", 3, "BALANCE",
     [("Tandem Stance", 4, 120), ("Heel Raise", 10, 60), ("Sit-to-Stand", 8, 90)]),
    ("Core and Back Care", "Relieve lower back discomfort and activate the core muscles.",
     "CORE", "EARLY", "LOW", 4, "PAIN_RELIEF",
     [("Pelvic Tilt", 10, 60), ("Glute Bridge", 8, 90)]),
    ("Disuse Atrophy Reconditioning", "Rebuild general muscle activity after a long period of inactivity.",
     "FULL_BODY", "EARLY", "LOW", 3, "ENDURANCE",
     [("Seated Marching", 20, 90), ("Sit-to-Stand", 8, 90), ("Shoulder Abduction", 8, 60)]),
    ("Active Recovery Circuit", "Increase endurance and whole-body fitness in the late stage of recovery.",
     "FULL_BODY", "ADVANCED", "HIGH", 4, "ENDURANCE",
     [("March in Place", 30, 120), ("Step-Up", 10, 120), ("Mini Squat", 10, 90), ("Wall Push-Up", 10, 90)]),
    ("Advanced Leg Function", "Restore full leg strength and control for an active daily routine.",
     "BOTH_LEGS", "ADVANCED", "HIGH", 3, "STRENGTH",
     [("Mini Squat", 12, 90), ("Step-Up", 12, 120), ("Standing Hip Abduction", 12, 90)]),
]


def build():
    ex = {}
    for name, area, intensity, reps, dur, pose, text in EXERCISES:
        ex[name] = {
            "exercise_id": uid("exercise", name), "exercise_name": name, "instruction_text": text,
            "target_body_area": area, "intensity_level": intensity,
            "default_repetitions": reps, "default_duration_sec": dur, "pose_key": pose,
        }
    plans = []
    for name, aim, area, stage, mob, freq, goal, items in PLANS:
        pid = uid("plan", name)
        plans.append({
            "plan_id": pid, "plan_name": name, "aim": aim, "target_body_area": area,
            "recovery_stage": stage, "mobility_level": mob, "frequency_per_week": freq, "goal": goal,
            "plan_exercise": [
                {"plan_id": pid, "exercise_id": ex[e]["exercise_id"], "sequence_order": i + 1,
                 "prescribed_repetitions": r, "prescribed_duration_sec": d, "exercise": ex[e]}
                for i, (e, r, d) in enumerate(items)
            ],
        })
    return list(ex.values()), plans


def q(v):
    if v is None:
        return "NULL"
    if isinstance(v, (int, float)):
        return str(v)
    return "'" + str(v).replace("'", "''") + "'"


def main():
    here = Path(__file__).parent
    exercises, plans = build()
    out = here.parent.parent / "assets" / "seed" / "catalogue.json"
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(json.dumps({"exercises": exercises, "plans": plans}, indent=2), encoding="utf-8")

    sql = ["-- Generated by build_seed.py. Do not edit by hand.",
           "-- Needs: exercise.pose_key VARCHAR(30) NULL and treatment_plan.goal VARCHAR(15) NULL",
           "-- (two columns not in Tables 4.91/4.92; see IMPLEMENTATION_PLAN.md).", "BEGIN;"]
    for e in exercises:
        cols = list(e.keys())
        sql.append(f"INSERT INTO exercise ({', '.join(cols)}) VALUES ({', '.join(q(e[c]) for c in cols)}) "
                   "ON CONFLICT (exercise_id) DO NOTHING;")
    for p in plans:
        cols = ["plan_id", "plan_name", "aim", "target_body_area", "recovery_stage",
                "mobility_level", "frequency_per_week", "goal"]
        sql.append(f"INSERT INTO treatment_plan ({', '.join(cols)}) VALUES ({', '.join(q(p[c]) for c in cols)}) "
                   "ON CONFLICT (plan_id) DO NOTHING;")
        for pe in p["plan_exercise"]:
            cols = ["plan_id", "exercise_id", "sequence_order", "prescribed_repetitions", "prescribed_duration_sec"]
            sql.append(f"INSERT INTO plan_exercise ({', '.join(cols)}) VALUES ({', '.join(q(pe[c]) for c in cols)}) "
                       "ON CONFLICT DO NOTHING;")
    sql.append("COMMIT;")
    (here / "seed_catalogue.sql").write_text("\n".join(sql) + "\n", encoding="utf-8")
    print(f"{len(exercises)} exercises, {len(plans)} plans written")


if __name__ == "__main__":
    main()
