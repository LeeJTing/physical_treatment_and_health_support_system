"""Round 4 of the continuous chatbot improvement (7 Oct, rules 3.8 -> 3.9): plan-specific questions.

Different treatment plans, exercise names with typos and nicknames, repetitions, order, and
exercises that are not in the patient's plan. Written before looking at the rules; the first
run is the honest score.
"""
SHOULDER = "1d7600d4-5fa4-538d-9f92-df663915233e"  # Shoulder Mobility Starter: flexion, abduction, elbow flexion
LEGS = "1e9ec416-4c4b-52bc-a070-1dc4a614a807"      # Lower Limb Strength Builder: sit-to-stand, mini squat, step-up
CORE = "1aba07fd-cf5b-5d4c-a948-24e4c0d9fd90"      # Core and Back Care: bird dog, glute bridge
HIP = "93ddd21e"                                   # Hip Stability (prefix, resolved below)
CIRCUIT = "2d9ac62b"                               # Active Recovery Circuit (prefix)

import json
from pathlib import Path

_PLANS = [p["plan_id"] for p in json.loads(
    (Path(__file__).resolve().parents[2] / "assets" / "seed" / "catalogue.json").read_text(encoding="utf-8"))["plans"]]
HIP = next(p for p in _PLANS if p.startswith(HIP))
CIRCUIT = next(p for p in _PLANS if p.startswith(CIRCUIT))

ROUND4 = [
    # exercise how-to, nicknames and typos
    (SHOULDER, "how to do arm raise to the front", "exercise:shoulder_flexion"),
    (SHOULDER, "side arm raise how", "exercise:shoulder_abduction"),
    (SHOULDER, "bicep curl steps", "exercise:elbow_flexion"),
    (SHOULDER, "how to do sholder flexion", "exercise:shoulder_flexion"),
    (LEGS, "how to do the chair stand", "exercise:sit_to_stand"),
    (LEGS, "mini sqaut how deep", "exercise:mini_squat"),
    (LEGS, "step up use what height step", "exercise:step_up"),
    (CORE, "how to do bird dog", "exercise:bird_dog"),
    (CORE, "bridge exercise lying down how", "exercise:glute_bridge"),
    (HIP, "how to stand heel to toe", "exercise:tandem_stance"),
    (HIP, "leg out to the side exercise", "exercise:hip_abduction"),
    (CIRCUIT, "marching on the spot how long", "exercise:march_in_place"),
    (CIRCUIT, "push up against the wall", "exercise:wall_push_up"),
    # plan contents, reps, order
    (SHOULDER, "how many reps for each exercise", "plan_exercises"),
    (LEGS, "which exercise first", "plan_exercises"),
    (CORE, "what exercises do i have", "plan_exercises"),
    (CIRCUIT, "how many exercises in my plan", "plan_exercises"),
    (HIP, "what is the order of my exercises", "plan_exercises"),
    # exercises not in the plan
    (SHOULDER, "how to do sit to stand", "exercise:sit_to_stand"),
    (CORE, "can i do heel raise too", "exercise:heel_raise"),
    # progress and goal
    (LEGS, "what is this plan for", "plan_progress"),
    (CORE, "will this help my back pain", ("plan_progress", "pain_or_discomfort")),
    (SHOULDER, "when can i lift my arm normally again", "plan_progress"),
    # how often / duration per plan
    (CORE, "how many days a week", "how_often"),
    (HIP, "how long should each session be", "how_often"),
    # equipment
    (LEGS, "do i need a chair", "equipment"),
    (CIRCUIT, "need any weights?", "equipment"),
    # posture
    (SHOULDER, "why my shoulder score only 60", "posture_result"),
    (LEGS, "the app said my knees go too far forward", ("posture_result", "exercise:mini_squat")),
    (CORE, "what does 80 percent mean", "posture_result"),
]
