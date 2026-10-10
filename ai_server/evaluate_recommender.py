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

Reasonableness (hybrid-3.1), over the same 720 answers with no limitation and with each profile
limitation (4,320 requests): plans shown that train none of the affected area, requests left with no
plan because of a limitation on the limb being rehabilitated, weak fillers (a plan shown beside a
better one with a content score under 0.5), and gentler plans that contain the exercise that failed.
hybrid-3.0 gave 1,550 / 630 / 2,992 / 185 of 720; see PROJECT_STATE. A failed exercise offered again at
an easier dose (fewer repetitions or less time) is counted separately: that is what easing should do.
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


LIMITS = [None, "LEFT_ARM_MOBILITY", "RIGHT_ARM_MOBILITY", "LEFT_LEG_MOBILITY", "RIGHT_LEG_MOBILITY",
          "BALANCE_IMPAIRMENT"]


def trains(plan, area):
    return any(E.cosine(E._PARTS[pe["exercise"]["target_body_area"]], E._PARTS[area]) > 0
               for pe in plan["plan_exercise"])


def reasonableness():
    out = {"requests": 0, "plans_not_training_area": 0, "no_plan_for_limited_treated_limb": 0,
           "weak_fillers": 0, "no_plan_at_all": 0, "easing_reoffers_failed_exercise": 0, "easing_cases": 0}
    for area, stage, mob, goal, cap, lim in itertools.product(list(E._PARTS), E.STAGES, E.MOBILITY, E.GOALS,
                                                              ("LOW", "MODERATE"), LIMITS):
        b = {"rehab": {"affected_body_area": area, "recovery_stage": stage, "mobility_level": mob, "goal": goal},
             "safety_limit": {"max_exercise_intensity": cap, "max_session_duration_min": MINUTES},
             "limitations": [lim] if lim else [], "plans": CATALOGUE["plans"]}
        res = E.recommend(RecommendRequest.model_validate(b))
        out["requests"] += 1
        out["plans_not_training_area"] += sum(not trains(PLANS[r.plan_id], area) for r in res.ranked)
        if len(res.ranked) > 1:
            out["weak_fillers"] += sum(r.content_score < 0.5 for r in res.ranked)
        blocked = E.blocked_area(lim) if lim else None
        if not res.ranked:
            out["no_plan_at_all"] += 1
            if blocked and area != "FULL_BODY" and E.cosine(E._PARTS[blocked], E._PARTS[area]) > 0:
                out["no_plan_for_limited_treated_limb"] += 1
        if lim is None and res.ranked:
            top = PLANS[res.ranked[0].plan_id]
            failed = sorted(top["plan_exercise"], key=lambda pe: pe["sequence_order"])[0]["exercise"]["exercise_id"]
            prog = {"plans": [{"plan_id": top["plan_id"], "status": "ACTIVE", "consecutive_fails": 3,
                               "current_exercise_id": failed}],
                    "exercises": [{"exercise_id": failed, "attempts": 3, "passes": 0, "mean_accuracy": 55}],
                    "from_plan_id": top["plan_id"]}
            eased = E.recommend(request(plan_rehab(top), cap, prog))
            out["easing_cases"] += 1
            src = {pe["exercise"]["exercise_id"]: pe for pe in top["plan_exercise"]}[failed]
            for r in eased.ranked:
                for pe in PLANS[r.plan_id]["plan_exercise"]:
                    if pe["exercise"]["exercise_id"] != failed:
                        continue
                    gentler = (pe["prescribed_repetitions"] <= src["prescribed_repetitions"]
                               and pe["prescribed_duration_sec"] <= src["prescribed_duration_sec"]
                               and (pe["prescribed_repetitions"], pe["prescribed_duration_sec"])
                               != (src["prescribed_repetitions"], src["prescribed_duration_sec"]))
                    key = "easing_keeps_failed_exercise_at_easier_dose" if gentler else "easing_reoffers_failed_exercise"
                    out[key] = out.get(key, 0) + 1
    return out


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
                    "exercises": [{"exercise_id": e, "attempts": 2, "passes": 2, "mean_accuracy": 88} for e in ex_ids],
                    "from_plan_id": top["plan_id"]}
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
            level(p)[0] == level(top)[0] + 1 and trains(p, top["target_body_area"])
            and all(INTENSITY.index(pe["exercise"]["intensity_level"]) <= INTENSITY.index(cap)
                    for pe in p["plan_exercise"])
            for p in CATALOGUE["plans"])
        unique_cases.add((top["plan_id"], cap))

        # struggling: first exercise did not pass 3 times
        s = stats["struggling"]
        s["cases"] += 1
        progress = {"plans": [{"plan_id": top["plan_id"], "status": "ACTIVE", "progress_percentage": 0,
                               "consecutive_fails": 3, "current_exercise_id": ex_ids[0]}],
                    "exercises": [{"exercise_id": ex_ids[0], "attempts": 3, "passes": 0, "mean_accuracy": 55}],
                    "from_plan_id": top["plan_id"]}
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
    stats["reasonableness"] = reasonableness()
    stats["distinct_completed_plan_and_limit_pairs"] = len(unique_cases)
    stats["model_version"] = E.MODEL_VERSION
    OUT.write_text(json.dumps(stats, indent=1) + "\n", encoding="utf-8")
    print(json.dumps(stats, indent=1))


if __name__ == "__main__":
    main()
