"""Compares a fixed plan list (an exact database query), the questionnaire recommender without
history (hybrid-2.2) and the progress-driven recommender (hybrid-3.0) on every questionnaire answer.

    cd ai_server
    .venv\\Scripts\\python evaluate_recommender.py          (summary; writes docs/recommender_eval.json)

Answers: 8 body areas x 3 recovery stages x 3 mobility levels x 5 goals x 2 intensity limits (LOW,
MODERATE), 30-minute sessions, no physical limitation: 720 combinations.

For each combination with a recommendation, the patient takes the top plan, then:
  completed  every exercise passed twice (accuracy 88): "Find my next plan" asks again with the
             completed plan's attributes. Without history the same plan comes back; with history
             the next step is PROGRESS.
  struggling the plan's first exercise did not pass 3 times (accuracy 55): "See gentler plans".
             Without history the same plan comes back; with history the next step is EASE.
  doing well the first exercise passed 3 times (accuracy 92) on a plan still being followed: STAY,
             and whether the personal score changes the order of the plans.
The safety rules are checked on every plan returned (intensity, session time).
"""
import itertools
import json
from pathlib import Path

from app.recommend import engine as E
from app.recommend.schemas import RecommendRequest

ROOT = Path(__file__).resolve().parents[1]
CATALOGUE = json.loads((ROOT / "assets" / "seed" / "catalogue.json").read_text(encoding="utf-8"))
PLANS = {p["plan_id"]: p for p in CATALOGUE["plans"]}
OUT = Path(__file__).with_name("docs") / "recommender_eval.json"
INTENSITY = ("LOW", "MODERATE", "VIGOROUS")
MINUTES = 30


def request(rehab, cap, progress=None):
    b = {"rehab": rehab, "safety_limit": {"max_exercise_intensity": cap, "max_session_duration_min": MINUTES},
         "plans": CATALOGUE["plans"]}
    if progress is not None:
        b["progress"] = progress
    return RecommendRequest.model_validate(b)


def exact_query(rehab, cap):
    """Plans matching every answer, within the intensity limit (what a plain database query returns)."""
    return [p for p in CATALOGUE["plans"]
            if p["target_body_area"] == rehab["affected_body_area"] and p["recovery_stage"] == rehab["recovery_stage"]
            and p["mobility_level"] == rehab["mobility_level"] and p["goal"] == rehab["goal"]
            and all(INTENSITY.index(pe["exercise"]["intensity_level"]) <= INTENSITY.index(cap)
                    for pe in p["plan_exercise"])]


def plan_rehab(p):
    return {"affected_body_area": p["target_body_area"], "recovery_stage": p["recovery_stage"],
            "mobility_level": p["mobility_level"], "goal": p["goal"]}


def safe(res, cap):
    for r in res.ranked:
        p = PLANS[r.plan_id]
        if any(INTENSITY.index(pe["exercise"]["intensity_level"]) > INTENSITY.index(cap) for pe in p["plan_exercise"]):
            return False
        if sum(pe["prescribed_duration_sec"] for pe in p["plan_exercise"]) > MINUTES * 60:
            return False
    return True


def level(p):
    return E.STAGES.index(p["recovery_stage"]), E.MOBILITY.index(p["mobility_level"])


def main():
    n = 0
    stats = {"combinations": 0, "exact_query_empty": 0, "recommender_empty": 0, "recommender_three": 0,
             "completed": {"cases": 0, "static_same_plan_first": 0, "adaptive_same_plan_offered": 0,
                           "adaptive_higher_stage_offered": 0, "adaptive_no_plan": 0, "adaptive_progress_step": 0,
                           "higher_stage_exists_within_limits": 0},
             "struggling": {"cases": 0, "static_same_plan_first": 0, "adaptive_same_plan_offered": 0,
                            "adaptive_ease_step": 0, "adaptive_no_harder_plan": 0, "adaptive_no_plan": 0},
             "doing_well": {"cases": 0, "order_changed": 0, "top_changed": 0},
             "unsafe_plans_returned": 0}
    unique_cases = set()
    for area, stage, mob, goal, cap in itertools.product(list(E._PARTS), E.STAGES, E.MOBILITY, E.GOALS,
                                                         ("LOW", "MODERATE")):
        n += 1
        rehab = {"affected_body_area": area, "recovery_stage": stage, "mobility_level": mob, "goal": goal}
        stats["exact_query_empty"] += not exact_query(rehab, cap)
        first = E.recommend(request(rehab, cap))
        stats["unsafe_plans_returned"] += not safe(first, cap)
        if not first.ranked:
            stats["recommender_empty"] += 1
            continue
        stats["recommender_three"] += len(first.ranked) == 3
        top = PLANS[first.ranked[0].plan_id]
        ex_ids = [pe["exercise"]["exercise_id"] for pe in sorted(top["plan_exercise"],
                                                                 key=lambda pe: pe["sequence_order"])]

        # completed: every exercise passed twice
        c = stats["completed"]
        c["cases"] += 1
        progress = {"plans": [{"plan_id": top["plan_id"], "status": "COMPLETED", "progress_percentage": 100}],
                    "exercises": [{"exercise_id": e, "attempts": 2, "passes": 2, "mean_accuracy": 88} for e in ex_ids]}
        static = E.recommend(request(plan_rehab(top), cap))
        adaptive = E.recommend(request(plan_rehab(top), cap, progress))
        stats["unsafe_plans_returned"] += not safe(adaptive, cap)
        c["static_same_plan_first"] += bool(static.ranked) and static.ranked[0].plan_id == top["plan_id"]
        offered = [PLANS[r.plan_id] for r in adaptive.ranked]
        c["adaptive_same_plan_offered"] += any(p["plan_id"] == top["plan_id"] for p in offered)
        c["adaptive_progress_step"] += adaptive.next_step == "PROGRESS"
        c["adaptive_higher_stage_offered"] += any(level(p)[0] > level(top)[0] for p in offered)
        c["adaptive_no_plan"] += not offered
        # Could a higher-stage plan for an overlapping area have been offered at all within the limits?
        c["higher_stage_exists_within_limits"] += any(
            level(p)[0] == level(top)[0] + 1 and E.cosine(E._PARTS[p["target_body_area"]],
                                                          E._PARTS[top["target_body_area"]]) > 0
            and all(INTENSITY.index(pe["exercise"]["intensity_level"]) <= INTENSITY.index(cap)
                    for pe in p["plan_exercise"])
            for p in CATALOGUE["plans"])
        unique_cases.add((top["plan_id"], cap))

        # struggling: first exercise did not pass 3 times
        s = stats["struggling"]
        s["cases"] += 1
        progress = {"plans": [{"plan_id": top["plan_id"], "status": "ACTIVE", "progress_percentage": 0,
                               "consecutive_fails": 3}],
                    "exercises": [{"exercise_id": ex_ids[0], "attempts": 3, "passes": 0, "mean_accuracy": 55}]}
        adaptive = E.recommend(request(plan_rehab(top), cap, progress))
        stats["unsafe_plans_returned"] += not safe(adaptive, cap)
        s["static_same_plan_first"] += bool(static.ranked) and static.ranked[0].plan_id == top["plan_id"]
        offered = [PLANS[r.plan_id] for r in adaptive.ranked]
        s["adaptive_same_plan_offered"] += any(p["plan_id"] == top["plan_id"] for p in offered)
        s["adaptive_ease_step"] += adaptive.next_step == "EASE"
        s["adaptive_no_harder_plan"] += all(level(p) <= level(top) and level(p)[0] <= level(top)[0]
                                            and level(p)[1] <= level(top)[1] for p in offered)
        s["adaptive_no_plan"] += not offered

        # doing well on a plan still followed: the questionnaire again, with history
        d = stats["doing_well"]
        d["cases"] += 1
        progress = {"plans": [{"plan_id": top["plan_id"], "status": "ACTIVE", "progress_percentage": 33.33}],
                    "exercises": [{"exercise_id": ex_ids[0], "attempts": 3, "passes": 3, "mean_accuracy": 92}]}
        again = E.recommend(request(rehab, cap, progress))
        stats["unsafe_plans_returned"] += not safe(again, cap)
        d["order_changed"] += [r.plan_id for r in again.ranked] != [r.plan_id for r in first.ranked]
        d["top_changed"] += bool(again.ranked) and again.ranked[0].plan_id != first.ranked[0].plan_id

    stats["combinations"] = n
    stats["distinct_completed_plan_and_limit_pairs"] = len(unique_cases)
    stats["model_version"] = E.MODEL_VERSION
    OUT.write_text(json.dumps(stats, indent=1) + "\n", encoding="utf-8")
    print(json.dumps(stats, indent=1))


if __name__ == "__main__":
    main()
