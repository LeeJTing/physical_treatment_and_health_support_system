"""Tests for the hybrid recommender, run against the real seed catalogue."""
import copy
import json
from pathlib import Path

import pytest
from fastapi.testclient import TestClient

from app.main import app
from app.recommend.engine import conflicts, cosine, recommend
from app.recommend.schemas import RecommendRequest

client = TestClient(app)
DEV = {"Authorization": "Bearer dev-token"}
CATALOGUE = json.loads((Path(__file__).parents[2] / "assets" / "seed" / "catalogue.json").read_text(encoding="utf-8"))
NAME = {p["plan_id"]: p["plan_name"] for p in CATALOGUE["plans"]}


def body(area="BOTH_LEGS", stage="EARLY", mobility="LOW", goal="MOBILITY",
         intensity="MODERATE", minutes=30, limitations=(), plans=None):
    return {
        "rehab": {"affected_body_area": area, "recovery_stage": stage, "mobility_level": mobility, "goal": goal},
        "safety_limit": {"max_exercise_intensity": intensity, "max_session_duration_min": minutes},
        "limitations": list(limitations),
        "plans": CATALOGUE["plans"] if plans is None else plans,
    }


def names(res):
    return [NAME[r["plan_id"]] for r in res["ranked"]]


def post(**kw):
    r = client.post("/recommend", json=body(**kw), headers=DEV)
    assert r.status_code == 200, r.text
    return r.json()


# ---- building blocks -------------------------------------------------------

def test_cosine_basics():
    assert cosine((1, 0), (1, 0)) == pytest.approx(1)
    assert cosine((1, 0), (0, 1)) == 0
    assert cosine((0, 0), (1, 1)) == 0  # empty vector is not a match


def test_conflicts_mirrors_dart_rule():
    assert conflicts("LEFT_ARM", "LEFT_ARM")
    assert conflicts("BOTH_ARMS", "RIGHT_ARM")
    assert not conflicts("BOTH_LEGS", "LEFT_ARM")
    assert conflicts("BOTH_LEGS", "LEFT_LEG") and conflicts("FULL_BODY", "RIGHT_LEG")
    assert not conflicts("FULL_BODY", "LEFT_ARM")  # same as the Dart code: arm limits do not block FULL_BODY


# ---- FR500_05 to FR500_07 --------------------------------------------------

def test_early_knee_patient_gets_knee_plan_first():
    res = post(area="BOTH_LEGS", stage="EARLY", mobility="LOW", goal="MOBILITY")
    assert res["status"] == "OK"
    assert names(res)[0] == "Early Knee Recovery"
    assert res["ranked"][0]["suitability_score"] == pytest.approx(1.0)
    assert len(res["ranked"]) == 3


def test_scores_are_sorted_and_in_range():
    res = post(area="FULL_BODY", stage="ADVANCED", mobility="HIGH", goal="ENDURANCE", minutes=45)
    scores = [r["suitability_score"] for r in res["ranked"]]
    assert scores == sorted(scores, reverse=True)
    assert all(0 <= s <= 1 for s in scores)
    assert names(res)[0] == "Active Recovery Circuit"


def test_never_more_than_three():
    res = post(area="FULL_BODY", stage="ADVANCED", mobility="HIGH", goal="STRENGTH", minutes=60)
    assert res["suitable_count"] > 3 and len(res["ranked"]) == 3


def test_same_input_same_order():
    assert post(area="BOTH_ARMS", goal="STRENGTH", stage="INTERMEDIATE", mobility="MODERATE") == \
        post(area="BOTH_ARMS", goal="STRENGTH", stage="INTERMEDIATE", mobility="MODERATE")


# ---- knowledge-based filter ------------------------------------------------

def test_low_intensity_cap_drops_moderate_exercises():
    res = post(area="FULL_BODY", stage="ADVANCED", mobility="HIGH", goal="STRENGTH", intensity="LOW", minutes=60)
    reasons = {NAME[e["plan_id"]]: e["reasons"] for e in res["excluded"]}
    assert "Lower Limb Strength Builder" not in names(res)
    assert any("intensity above LOW" in r for r in reasons["Lower Limb Strength Builder"])


def test_session_duration_cap():
    # One exercise of a plan a day (as PlanRules in the app, Elwin 23 Oct): the day's time is the
    # longest exercise. Active Recovery Circuit: 2 + 2 + 1.5 + 1.5 min, so 7 min in all, 2 min a day.
    res = post(area="FULL_BODY", stage="ADVANCED", mobility="HIGH", goal="ENDURANCE", minutes=5)
    assert "Active Recovery Circuit" in names(res)  # within 5 min a day, though 7 min in all
    res = post(area="FULL_BODY", stage="ADVANCED", mobility="HIGH", goal="ENDURANCE", minutes=1)
    assert "Active Recovery Circuit" not in names(res)
    reasons = {NAME[e["plan_id"]]: e["reasons"] for e in res["excluded"]}
    assert any(r.startswith("session 2 min exceeds 1 min") for r in reasons["Active Recovery Circuit"])


def test_leg_limitation_blocks_leg_plans():
    res = post(area="FULL_BODY", stage="ADVANCED", mobility="HIGH", goal="STRENGTH", minutes=60,
               limitations=["LEFT_LEG_MOBILITY"])
    for r in res["ranked"]:
        plan = next(p for p in CATALOGUE["plans"] if p["plan_id"] == r["plan_id"])
        assert all(pe["exercise"]["target_body_area"] not in ("BOTH_LEGS", "FULL_BODY", "LEFT_LEG")
                   for pe in plan["plan_exercise"])


def test_balance_limitation_blocks_no_area():
    with_balance = post(limitations=["BALANCE_IMPAIRMENT"])
    assert names(with_balance) == names(post())


def test_later_stage_and_higher_mobility_plans_are_dropped():
    res = post(area="BOTH_LEGS", stage="EARLY", mobility="LOW", goal="STRENGTH")
    assert "Advanced Leg Function" not in names(res)
    assert "Lower Limb Strength Builder" not in names(res)


def test_plans_for_other_body_areas_are_dropped():
    res = post(area="LEFT_ARM", stage="EARLY", mobility="LOW", goal="MOBILITY")
    assert "Early Knee Recovery" not in names(res)
    assert names(res)[0] in ARM_TWINS


# ---- FR500_14 / FR500_15 ---------------------------------------------------

def test_none_suitable():
    # The plans with an exercise over a 1-minute day (the 1-minute-exercise plans fit one since
    # the day counts one exercise, 23 Oct).
    longer = [p for p in CATALOGUE["plans"]
              if max(pe["prescribed_duration_sec"] for pe in p["plan_exercise"]) > 60]
    res = post(area="LEFT_ARM", stage="EARLY", mobility="LOW", limitations=["LEFT_ARM_MOBILITY"],
               intensity="LOW", minutes=1, plans=longer)
    assert res["status"] == "NONE" and res["ranked"] == [] and res["suitable_count"] == 0
    assert len(res["excluded"]) == len(longer)


def test_only_one_suitable():
    knee = [p for p in CATALOGUE["plans"] if p["plan_name"] == "Early Knee Recovery"]
    shoulder = [p for p in CATALOGUE["plans"] if p["plan_name"] == "Shoulder Mobility Starter"]
    res = post(area="BOTH_LEGS", plans=knee + shoulder)
    assert res["status"] == "ONLY_ONE" and names(res) == ["Early Knee Recovery"]


# ---- request contract ------------------------------------------------------

def test_empty_catalogue_is_invalid_request():
    r = client.post("/recommend", json=body(plans=[]), headers=DEV)
    assert r.status_code == 422 and r.json()["error"]["code"] == "invalid_request"


def test_unknown_body_area_is_invalid_request():
    r = client.post("/recommend", json=body(area="HEAD"), headers=DEV)
    assert r.status_code == 422


def test_engine_accepts_app_json_directly():
    # TreatmentPlan.toJson() sends extra keys (aim, frequency_per_week, ...); they are ignored.
    req = RecommendRequest.model_validate(body())
    assert recommend(req).status == "OK"


# ---- hybrid-2.0: collaborative part and diversity re-rank ------------------------------------

import itertools  # noqa: E402

from app.recommend import engine as E  # noqa: E402

ID = {p["plan_name"]: p["plan_id"] for p in CATALOGUE["plans"]}
TWINS = {"Lower Limb Strength Builder", "Advanced Leg Function"}    # the only pair above DUPLICATE_SIM
# 9 Oct: the new Hand and Wrist Recovery plan has the same area, stage, mobility and goal as Shoulder
# Mobility Starter, so the content score cannot tell them apart (a body-part focus block is planned).
ARM_TWINS = {"Shoulder Mobility Starter", "Hand and Wrist Recovery"}
# hybrid-3.1 (area from the exercises): both balance plans are leg exercises with Tandem Stance.
BALANCE_TWINS = {"Hip Stability", "Balance and Fall Prevention"}
TWIN_PAIRS = [TWINS, ARM_TWINS, BALANCE_TWINS]


def hybrid_1(req):
    """hybrid-1.0: rules, content score, best three by score then name; since hybrid-3.1 without weak
    fillers (at least MIN_MATCH and RELATIVE_MATCH of the best, else only the closest plan)."""
    ranked = [(E.weighted(E.score(req, p)), p.plan_name, p.plan_id) for p in req.plans
              if not E.exclusion_reasons(req, p)]
    ranked.sort(key=lambda t: (-t[0], t[1]))
    if ranked:
        best = ranked[0][0]
        ranked = [t for t in ranked if t[0] >= E.MIN_MATCH and t[0] >= E.RELATIVE_MATCH * best] or ranked[:1]
    return [(t[2], round(t[0], 3)) for t in ranked[:3]]


def grid():
    for area, stage, mob, goal, inten, mins in itertools.product(
            E._PARTS, E.STAGES, E.MOBILITY, E.GOALS, E.INTENSITY, (10, 30, 60)):
        yield RecommendRequest.model_validate(body(area, stage, mob, goal, inten, mins))


def cell(plan, risk="High", age="75+", patients=40, completion=0.9, accuracy=85.0, progress=60.0):
    return {"plan_id": ID[plan], "risk_level": risk, "age_band": age, "patients": patients,
            "completion_rate": completion, "mean_accuracy": accuracy, "mean_progress": progress}


def with_evidence(outcomes, cohort=None, **kw):
    b = body(**kw)
    b["cohort"] = cohort or {"risk_level": "High", "age_band": "75+"}
    b["plan_outcomes"] = outcomes
    return RecommendRequest.model_validate(b)


def test_cold_start_equals_hybrid_1_on_every_request():
    # Main guard: without evidence the collaborative part changes nothing (diversity off).
    for req in grid():
        assert [(r.plan_id, r.suitability_score) for r in recommend(req, lam=1.0).ranked] == hybrid_1(req)
        assert all(r.alpha == 0 and r.breakdown.collaborative is None for r in recommend(req, lam=1.0).ranked)


def test_cohort_without_outcomes_is_still_cold_start():
    req = with_evidence([])
    assert [(r.plan_id, r.suitability_score) for r in recommend(req, lam=1.0).ranked] == hybrid_1(req)


def test_diversity_only_ever_splits_the_near_twin_plans():
    changed = 0
    for req in grid():
        before = [NAME[r.plan_id] for r in recommend(req, lam=1.0).ranked]
        after = [NAME[r.plan_id] for r in recommend(req).ranked]
        if before != after:
            changed += 1
            split = any(pair <= set(before) and len(pair & set(after)) == 1 for pair in TWIN_PAIRS)
            # With only three suitable plans (e.g. all three arm plans) the twin just moves to third place.
            reordered = set(after) == set(before) and any(pair <= set(before) for pair in TWIN_PAIRS)
            assert split or reordered
            if split:
                assert set(after) - set(before)       # a different kind of plan took the twin's place
    # 42 of 3240 on the 10-plan catalogue; 981 with the Hand and Wrist plan, mostly arm patients where
    # the twins are content-identical. A body-part focus block (planned) should bring this back down.
    assert 0 < changed < 1100


def test_diversity_never_returns_an_excluded_plan():
    for req in grid():
        res = recommend(req)
        excluded = {e.plan_id for e in res.excluded}
        assert not excluded & {r.plan_id for r in res.ranked}


def test_diversity_keeps_order_when_plans_are_already_diverse():
    plans = [p for p in RecommendRequest.model_validate(body()).plans if p.plan_name not in TWINS | ARM_TWINS]
    scored = [(1 - i * 0.01, p) for i, p in enumerate(plans)]
    assert [p.plan_id for _, p in E.diversify(scored)] == [p.plan_id for _, p in scored[:3]]


def test_redundancy_is_zero_below_threshold_and_one_for_identical():
    p = RecommendRequest.model_validate(body()).plans
    assert E.redundancy(p[0], p[0]) == pytest.approx(1.0)
    assert all(E.redundancy(a, b) == 0 for a, b in itertools.combinations(p, 2)
               if {a.plan_name, b.plan_name} not in TWIN_PAIRS)


def test_cell_outcome_clamped_and_missing_values_neutral():
    from app.recommend.schemas import PlanOutcomeIn
    full = PlanOutcomeIn(**cell("Hip Stability", completion=1.0, accuracy=100, progress=100))
    none = PlanOutcomeIn(**cell("Hip Stability", completion=0.0, accuracy=None, progress=None))
    assert E.cell_outcome(full) == pytest.approx(1.0)
    assert E.cell_outcome(none) == pytest.approx(0.3 * 0.5 + 0.2 * 0.5)


def test_small_cells_are_ignored():
    req = with_evidence([cell("Early Knee Recovery", patients=4)])
    res = recommend(req, lam=1.0)
    assert all(r.alpha == 0 for r in res.ranked)
    assert [(r.plan_id, r.suitability_score) for r in res.ranked] == hybrid_1(req)


def test_alpha_grows_with_evidence_and_never_exceeds_cap():
    alphas = []
    for n in (5, 20, 200, 100000):
        res = recommend(with_evidence([cell("Early Knee Recovery", patients=n)]), lam=1.0)
        alphas.append(next(r.alpha for r in res.ranked if NAME[r.plan_id] == "Early Knee Recovery"))
    assert alphas == sorted(alphas) and alphas[0] > 0 and max(alphas) <= E.ALPHA_MAX


def test_good_evidence_can_reorder_safe_plans_but_not_bring_back_excluded_ones():
    # EARLY knee patient: Early Knee Recovery first on content alone.
    base = [NAME[r.plan_id] for r in recommend(with_evidence([]), lam=1.0).ranked]
    second = base[1]
    strong = [cell(second, patients=5000, completion=1.0, accuracy=100, progress=100),
              cell(base[0], patients=5000, completion=0.0, accuracy=0, progress=0),
              cell("Advanced Leg Function", patients=5000, completion=1.0, accuracy=100, progress=100)]
    res = recommend(with_evidence(strong), lam=1.0)
    got = [NAME[r.plan_id] for r in res.ranked]
    assert got[0] == second                           # evidence re-ordered two safe plans
    assert "Advanced Leg Function" not in got         # ADVANCED plan stays excluded for an EARLY patient


def test_dissimilar_cohort_counts_less():
    me = {"risk_level": "High", "age_band": "75+"}
    near = recommend(with_evidence([cell("Early Knee Recovery", "High", "75+")], cohort=me), lam=1.0)
    far = recommend(with_evidence([cell("Early Knee Recovery", "Low", "<60")], cohort=me), lam=1.0)
    ev = lambda res: next(r.evidence_patients for r in res.ranked if NAME[r.plan_id] == "Early Knee Recovery")
    assert ev(near) > ev(far) > 0


def test_evidence_result_is_deterministic():
    req = with_evidence([cell("Hip Stability"), cell("Early Knee Recovery", patients=8)])
    assert recommend(req).model_dump() == recommend(req).model_dump()


def test_endpoint_accepts_evidence_and_reports_it():
    b = body()
    b["cohort"] = {"risk_level": "Medium", "age_band": "60-74"}
    b["plan_outcomes"] = [cell("Early Knee Recovery", "Medium", "60-74", patients=30)]
    r = client.post("/recommend", json=b, headers=DEV)
    assert r.status_code == 200, r.text
    res = r.json()
    assert res["model_version"] == "hybrid-3.1"
    top = next(x for x in res["ranked"] if NAME[x["plan_id"]] == "Early Knee Recovery")
    assert top["evidence_patients"] == 30 and 0 < top["alpha"] <= 0.3
    assert top["breakdown"]["collaborative"] is not None


# ---- hybrid-2.1: body-part focus from the body map ---------------------------------------------

def focused(parts, **kw):
    b = body(**kw)
    b["focus_parts"] = list(parts)
    return RecommendRequest.model_validate(b)


ARM_EARLY = dict(area="BOTH_ARMS", stage="EARLY", mobility="LOW", goal="MOBILITY")


def test_every_catalogue_pose_key_has_body_parts():
    keys = {e["pose_key"] for e in CATALOGUE["exercises"] if e.get("pose_key")}
    assert keys <= set(E.POSE_PARTS)
    assert all(set(v) <= set(E.FOCUS_PARTS) for v in E.POSE_PARTS.values())


def test_no_focus_parts_is_exactly_hybrid_2_0():
    # The focus block and its MMR term only exist when the request has focus parts.
    for req in grid():
        assert all(r.breakdown.focus is None for r in recommend(req).ranked)
        assert [(r.plan_id, r.suitability_score) for r in recommend(req, lam=1.0).ranked] == hybrid_1(req)


def test_tapping_a_wrist_ranks_the_hand_plan_first():
    res = recommend(focused(["wrist_hand"], **ARM_EARLY))
    assert NAME[res.ranked[0].plan_id] == "Hand and Wrist Recovery"
    assert res.ranked[0].breakdown.focus == pytest.approx(0.894, abs=1e-3)


def test_tapping_a_shoulder_ranks_the_shoulder_plan_first():
    res = recommend(focused(["shoulder"], **ARM_EARLY))
    assert NAME[res.ranked[0].plan_id] == "Shoulder Mobility Starter"
    hand = next(r for r in res.ranked if NAME[r.plan_id] == "Hand and Wrist Recovery")
    assert hand.breakdown.focus == 0


def test_an_elbow_matches_both_arm_plans_equally():
    res = recommend(focused(["elbow"], **ARM_EARLY))
    by_name = {NAME[r.plan_id]: r.breakdown.focus for r in res.ranked}
    assert by_name["Hand and Wrist Recovery"] == pytest.approx(by_name["Shoulder Mobility Starter"])


def test_focus_is_modest_and_never_brings_back_an_excluded_plan():
    # Wrist focus for a leg patient: arm plans stay excluded, the leg ranking keeps its order.
    req = focused(["wrist_hand"], area="BOTH_LEGS")
    res = recommend(req)
    assert "Hand and Wrist Recovery" not in names(res.model_dump())
    assert names(res.model_dump())[0] == "Early Knee Recovery"
    # A full block mismatch costs at most FOCUS_WEIGHT / 1.2 of the score.
    assert res.ranked[0].suitability_score >= round(1 - E.FOCUS_WEIGHT / (1 + E.FOCUS_WEIGHT), 3)


def test_knee_focus_prefers_the_plans_that_train_the_knee():
    res = recommend(focused(["knee"], area="BOTH_LEGS", stage="ADVANCED", mobility="HIGH", goal="STRENGTH",
                            minutes=60))
    assert all(r.breakdown.focus > 0 for r in res.ranked)


def test_plan_parts_counts_exercises():
    plan = next(p for p in RecommendRequest.model_validate(body()).plans if p.plan_name == "Hand and Wrist Recovery")
    parts = dict(zip(E.FOCUS_PARTS, E.plan_parts(plan)))
    assert parts["wrist_hand"] == 2 and parts["elbow"] == 1 and parts["shoulder"] == 0


def test_plans_without_pose_keys_get_no_focus_match():
    b = copy.deepcopy(body(**ARM_EARLY))   # body() shares the catalogue between tests
    for p in b["plans"]:
        for pe in p["plan_exercise"]:
            pe["exercise"] = {k: v for k, v in pe["exercise"].items() if k != "pose_key"}
    b["focus_parts"] = ["wrist_hand"]
    res = recommend(RecommendRequest.model_validate(b))
    assert all(r.breakdown.focus == 0 for r in res.ranked)


def test_unknown_focus_part_is_an_invalid_request():
    b = body()
    b["focus_parts"] = ["neck"]
    r = client.post("/recommend", json=b, headers=DEV)
    assert r.status_code == 422


def test_endpoint_reports_the_focus_score():
    b = body(**ARM_EARLY)
    b["focus_parts"] = ["wrist_hand"]
    r = client.post("/recommend", json=b, headers=DEV)
    assert r.status_code == 200
    assert names(r.json())[0] == "Hand and Wrist Recovery"
    assert r.json()["ranked"][0]["breakdown"]["focus"] == pytest.approx(0.894, abs=1e-3)


# ---- hybrid-2.2: optional pace ---------------------------------------------------------------

def paced(pace, **kw):
    b = body(**kw)
    b["pace"] = pace
    return RecommendRequest.model_validate(b)


def test_no_pace_changes_nothing():
    for req in grid():
        assert all(r.breakdown.pace is None for r in recommend(req).ranked)


def test_plan_pace_buckets():
    plans = {p.plan_name: p for p in RecommendRequest.model_validate(body()).plans}
    assert E.plan_pace(plans["Early Knee Recovery"]) == 0          # 3 days
    assert E.plan_pace(plans["Core and Back Care"]) == 1           # 4 days
    assert E.plan_pace(plans["Hand and Wrist Recovery"]) == 2      # 5 days


def test_pace_prefers_plans_with_that_many_days():
    # Arm, early, low, mobility: Shoulder Mobility Starter and Hand and Wrist are 5 days a week.
    fast = recommend(paced("FAST", **ARM_EARLY))
    slow = recommend(paced("SLOW", **ARM_EARLY))
    top_fast = {NAME[r.plan_id]: r.suitability_score for r in fast.ranked}
    top_slow = {NAME[r.plan_id]: r.suitability_score for r in slow.ranked}
    hand = "Hand and Wrist Recovery"
    assert top_fast[hand] > top_slow[hand]
    assert fast.ranked[0].breakdown.pace == pytest.approx(1.0)


def test_pace_never_brings_back_an_excluded_plan():
    for pace in ("SLOW", "MEDIUM", "FAST"):
        res = recommend(paced(pace, area="BOTH_LEGS"))
        assert not {"Hand and Wrist Recovery", "Shoulder Mobility Starter"} & set(names(res.model_dump()))


def test_pace_weight_is_modest():
    # A full pace mismatch costs at most PACE_WEIGHT / 1.1 of a perfect score.
    res = recommend(paced("FAST", area="BOTH_LEGS"))          # Early Knee Recovery is 3 days a week
    assert NAME[res.ranked[0].plan_id] == "Early Knee Recovery"
    assert res.ranked[0].suitability_score >= round(1 - E.PACE_WEIGHT / (1 + E.PACE_WEIGHT), 3)


def test_unknown_frequency_is_neutral():
    b = copy.deepcopy(body(**ARM_EARLY))
    for p in b["plans"]:
        p.pop("frequency_per_week", None)
    b["pace"] = "FAST"
    res = recommend(RecommendRequest.model_validate(b))
    assert all(r.breakdown.pace == E.NEUTRAL_PACE for r in res.ranked)


def test_unknown_pace_is_an_invalid_request():
    b = body()
    b["pace"] = "VERY_FAST"
    assert client.post("/recommend", json=b, headers=DEV).status_code == 422


# ---- hybrid-3.0: the patient's own progress ------------------------------------------------------

PLAN = {p["plan_name"]: p for p in CATALOGUE["plans"]}
EXERCISE = {e["exercise_name"]: e for e in CATALOGUE["exercises"]}
INTENSITY_ORDER = ("LOW", "MODERATE", "VIGOROUS")


def result(name, attempts, passes, accuracy=None):
    return {"exercise_id": EXERCISE[name]["exercise_id"], "attempts": attempts, "passes": passes,
            "mean_accuracy": accuracy}


def history(name, status="ACTIVE", progress=0.0, fails=0, falls=0):
    return {"plan_id": PLAN[name]["plan_id"], "status": status, "progress_percentage": progress,
            "consecutive_fails": fails, "fall_alerts": falls}


def from_plan(name, intensity="MODERATE", plans=(), exercises=(), limitations=()):
    """Next-step request ("Find my next plan" / "See gentler plans"): the answers are the attributes of
    the plan the patient moves on from, which the request names."""
    p = PLAN[name]
    b = body(area=p["target_body_area"], stage=p["recovery_stage"], mobility=p["mobility_level"], goal=p["goal"],
             intensity=intensity, limitations=limitations)
    b["progress"] = {"plans": list(plans), "exercises": list(exercises), "from_plan_id": p["plan_id"]}
    return RecommendRequest.model_validate(b)


KNEE_DONE = [result("Seated Knee Extension", 3, 2, 86), result("Seated Marching", 2, 2, 90),
             result("Heel Raise", 2, 1, 82)]


def test_without_history_the_result_equals_hybrid_2_2():
    plain = recommend(RecommendRequest.model_validate(body(**ARM_EARLY)))
    empty = body(**ARM_EARLY)
    empty["progress"] = {"plans": [], "exercises": []}
    res = recommend(RecommendRequest.model_validate(empty))
    assert res.next_step == plain.next_step == "START" and res.next_step_reason == ""
    assert [(r.plan_id, r.suitability_score) for r in res.ranked] == \
           [(r.plan_id, r.suitability_score) for r in plain.ranked]
    assert all(r.beta == 0 and r.breakdown.personal is None for r in res.ranked)


def test_completed_plan_moves_up_one_stage():
    res = recommend(from_plan("Early Knee Recovery", plans=[history("Early Knee Recovery", "COMPLETED", 100)],
                              exercises=KNEE_DONE))
    assert res.next_step == "PROGRESS"
    assert (res.effective_stage, res.effective_mobility) == ("INTERMEDIATE", "MODERATE")
    assert "Early Knee Recovery" in res.next_step_reason
    got = names(res.model_dump())
    assert "Early Knee Recovery" not in got
    assert {"Lower Limb Strength Builder", "Hip Stability"} <= set(got[:2])
    left = next(e for e in res.excluded if NAME[e.plan_id] == "Early Knee Recovery")
    assert left.reasons[0] == "already completed"


def test_progress_is_learnt_from_similar_exercises():
    # Knee extension and marching went well, so the strength plan (sit-to-stand, mini squat, step-up:
    # knee and hip) is predicted to suit better than Hip Stability, whose content score is close.
    res = recommend(from_plan("Early Knee Recovery", plans=[history("Early Knee Recovery", "COMPLETED", 100)],
                              exercises=KNEE_DONE))
    by = {NAME[r.plan_id]: r for r in res.ranked}
    strength, hip = by["Lower Limb Strength Builder"], by["Hip Stability"]
    assert abs(strength.content_score - hip.content_score) < 0.05
    assert strength.breakdown.personal > hip.breakdown.personal > 0.5
    assert names(res.model_dump())[0] == "Lower Limb Strength Builder"


def test_step_up_never_passes_the_safety_limit():
    res = recommend(from_plan("Early Knee Recovery", intensity="LOW",
                              plans=[history("Early Knee Recovery", "COMPLETED", 100)], exercises=KNEE_DONE))
    assert res.next_step == "PROGRESS"
    for r in res.ranked:
        plan = PLAN[NAME[r.plan_id]]
        assert plan["recovery_stage"] == "EARLY"
        assert all(pe["exercise"]["intensity_level"] == "LOW" for pe in plan["plan_exercise"])
    assert "not within your safety limits" in res.next_step_reason


def test_progress_never_lowers_the_answers():
    b = body(area="BOTH_LEGS", stage="ADVANCED", mobility="HIGH", goal="STRENGTH", intensity="VIGOROUS", minutes=60)
    b["progress"] = {"plans": [history("Early Knee Recovery", "COMPLETED", 100)], "exercises": [],
                     "from_plan_id": PLAN["Early Knee Recovery"]["plan_id"]}
    res = recommend(RecommendRequest.model_validate(b))
    assert (res.effective_stage, res.effective_mobility) == ("ADVANCED", "HIGH")
    assert names(res.model_dump())[0] == "Advanced Leg Function"


def test_the_questionnaire_never_moves_the_patients_answers():
    # History without a named plan (the questionnaire): no step up, no easing, no banner; it only ranks.
    for plans in ([history("Early Knee Recovery", "COMPLETED", 100)],
                  [history("Upper Limb Strength", fails=3)], [history("Hip Stability", falls=1)]):
        b = body(**ARM_EARLY)
        b["progress"] = {"plans": plans, "exercises": KNEE_DONE}
        res = recommend(RecommendRequest.model_validate(b))
        assert res.next_step == "STAY" and res.next_step_reason == ""
        assert (res.effective_stage, res.effective_mobility) == ("EARLY", "LOW")
        assert not any(r.startswith(("being eased", "already completed")) for e in res.excluded for r in e.reasons)


def test_repeated_failures_ease_the_plan():
    res = recommend(from_plan(
        "Lower Limb Strength Builder",
        plans=[history("Early Knee Recovery", "COMPLETED", 100),
               history("Lower Limb Strength Builder", progress=33.33, fails=3)],
        exercises=KNEE_DONE + [result("Sit-to-Stand", 2, 1, 81), result("Mini Squat", 3, 0, 58)]))
    assert res.next_step == "EASE"
    assert (res.effective_stage, res.effective_mobility) == ("EARLY", "LOW")
    assert "Lower Limb Strength Builder" in res.next_step_reason and "3 times" in res.next_step_reason
    assert "Lower Limb Strength Builder" not in names(res.model_dump())
    eased = next(e for e in res.excluded if NAME[e.plan_id] == "Lower Limb Strength Builder")
    assert eased.reasons[0].startswith("being eased")


def test_two_failures_are_not_enough_to_ease():
    res = recommend(from_plan("Lower Limb Strength Builder",
                              plans=[history("Lower Limb Strength Builder", fails=E.EASE_FAILS - 1)]))
    assert res.next_step == "STAY" and res.effective_stage == "INTERMEDIATE"


def test_a_possible_fall_eases_the_plan_it_happened_in():
    res = recommend(from_plan("Hip Stability", plans=[history("Hip Stability", falls=1)]))
    assert res.next_step == "EASE" and "fall" in res.next_step_reason
    assert (res.effective_stage, res.effective_mobility) == ("EARLY", "LOW")


def test_only_the_named_plan_decides_the_step():
    # Moving on from Early Knee Recovery (not hard): failures in another plan do not ease it.
    res = recommend(from_plan("Early Knee Recovery", plans=[history("Early Knee Recovery", progress=33.33),
                                                            history("Upper Limb Strength", fails=5)]))
    assert res.next_step == "STAY"


def test_good_results_lift_a_plan_above_an_equal_one():
    # Shoulder Mobility Starter and Hand and Wrist Recovery match equally (both 1.0). Passing
    # shoulder flexion puts the shoulder plan first; failing it puts it after the hand plan.
    def order(passes, accuracy):
        b = body(**ARM_EARLY)
        b["progress"] = {"plans": [history("Shoulder Mobility Starter", progress=33.33)],
                         "exercises": [result("Shoulder Flexion", 3, passes, accuracy)]}
        return names(recommend(RecommendRequest.model_validate(b)).model_dump())
    assert order(3, 92)[0] == "Shoulder Mobility Starter"
    poor = order(0, 45)
    assert poor.index("Shoulder Mobility Starter") > poor.index("Hand and Wrist Recovery")


def test_personal_score_is_bounded_and_reported_within_0_and_1():
    b = body(**ARM_EARLY)
    b["progress"] = {"plans": [], "exercises": [result(n, 20, 20, 100) for n in
                                                ("Shoulder Flexion", "Shoulder Abduction", "Elbow Flexion")]}
    res = recommend(RecommendRequest.model_validate(b))
    for r in res.ranked:
        assert 0 <= r.suitability_score <= 1
        assert r.beta <= E.BETA_MAX
        if r.breakdown.personal is not None:
            assert 0 <= r.breakdown.personal <= 1


def test_exercise_similarity():
    ex = {n: E.ExerciseIn.model_validate(e) for n, e in EXERCISE.items()}
    assert E.exercise_similarity(ex["Shoulder Flexion"], ex["Shoulder Flexion"]) == 1
    assert E.exercise_similarity(ex["Shoulder Flexion"], ex["Shoulder Abduction"]) == pytest.approx(1)
    assert E.exercise_similarity(ex["Shoulder Flexion"], ex["Seated Knee Extension"]) < E.SIM_FLOOR
    assert E.SIM_FLOOR < E.exercise_similarity(ex["Mini Squat"], ex["Sit-to-Stand"]) < 1


def test_own_result_counts_more_than_a_similar_exercise():
    # Case amplification: three good tries of the exercise itself outweigh three poor tries of a
    # similar one.
    plan = E.PlanIn.model_validate(PLAN["Early Knee Recovery"])
    b = body()
    b["progress"] = {"plans": [], "exercises": [result("Seated Knee Extension", 3, 3, 90),
                                                result("Mini Squat", 3, 0, 50)]}
    req = RecommendRequest.model_validate(b)
    score, _ = E.personal(req, plan, "STAY", E.catalogue_exercises(req))
    assert score > 0.5


def test_unknown_exercises_in_the_history_are_ignored():
    b = body(**ARM_EARLY)
    b["progress"] = {"plans": [{"plan_id": "gone", "status": "COMPLETED"}],
                     "exercises": [{"exercise_id": "gone", "attempts": 4, "passes": 4, "mean_accuracy": 95}]}
    res = recommend(RecommendRequest.model_validate(b))
    assert res.next_step == "STAY"
    assert all(r.breakdown.personal is None for r in res.ranked)


def test_history_never_lets_an_unsafe_plan_through():
    """Whatever the history, every ranked plan keeps the intensity, session-time and limitation rules."""
    import random
    rng = random.Random(7)
    all_ex = list(EXERCISE)
    for _ in range(300):
        cap = rng.choice(INTENSITY_ORDER[:2])
        minutes = rng.choice((10, 15, 20, 30))
        limits = rng.sample(["LEFT_ARM_MOBILITY", "RIGHT_LEG_MOBILITY", "BALANCE_IMPAIRMENT"], rng.randint(0, 2))
        plans = [history(n, rng.choice(("ACTIVE", "COMPLETED", "ABANDONED")), fails=rng.randint(0, 4),
                         falls=rng.choice((0, 0, 0, 1)))
                 for n in rng.sample(list(PLAN), rng.randint(0, 4))]
        exercises = []
        for n in rng.sample(all_ex, rng.randint(0, 6)):
            attempts = rng.randint(1, 6)
            exercises.append(result(n, attempts, rng.randint(0, attempts), rng.choice((None, rng.uniform(30, 100)))))
        b = body(area=rng.choice(list(E._PARTS)), stage=rng.choice(E.STAGES), mobility=rng.choice(E.MOBILITY),
                 goal=rng.choice(E.GOALS), intensity=cap, minutes=minutes, limitations=limits)
        b["progress"] = {"plans": plans, "exercises": exercises}
        res = recommend(RecommendRequest.model_validate(b))
        for r in res.ranked:
            plan = PLAN[NAME[r.plan_id]]
            assert all(INTENSITY_ORDER.index(pe["exercise"]["intensity_level"]) <= INTENSITY_ORDER.index(cap)
                       for pe in plan["plan_exercise"])
            assert sum(pe["prescribed_duration_sec"] for pe in plan["plan_exercise"]) <= minutes * 60
            for code in limits:
                area = E.blocked_area(code)
                if area is None:
                    continue
                for pe in plan["plan_exercise"]:
                    ex = pe["exercise"]
                    if not conflicts(ex["target_body_area"], area):
                        continue
                    # a limited limb only in gentle plans, and only for the area being rehabilitated
                    assert E.cosine(E._PARTS[ex["target_body_area"]], E._PARTS[b["rehab"]["affected_body_area"]]) > 0
                    assert plan["recovery_stage"] == "EARLY" and plan["mobility_level"] == "LOW"
                    assert ex["intensity_level"] == "LOW"
            assert E.STAGES.index(plan["recovery_stage"]) <= E.STAGES.index(res.effective_stage)


def test_endpoint_reports_the_next_step():
    b = body()
    b["progress"] = {"plans": [history("Early Knee Recovery", "COMPLETED", 100)], "exercises": KNEE_DONE,
                     "from_plan_id": PLAN["Early Knee Recovery"]["plan_id"]}
    r = client.post("/recommend", json=b, headers=DEV)
    assert r.status_code == 200, r.text
    res = r.json()
    assert res["next_step"] == "PROGRESS" and res["effective_stage"] == "INTERMEDIATE"
    assert any(x["beta"] > 0 and x["breakdown"]["personal"] is not None for x in res["ranked"])


def test_impossible_history_is_an_invalid_request():
    b = body()
    b["progress"] = {"plans": [], "exercises": [{"exercise_id": "x", "attempts": 0, "passes": 0}]}
    assert client.post("/recommend", json=b, headers=DEV).status_code == 422
    b["progress"] = {"plans": [{"plan_id": "x", "status": "PAUSED"}], "exercises": []}
    assert client.post("/recommend", json=b, headers=DEV).status_code == 422


# ---- hybrid-3.1: reasonable answers ------------------------------------------------------------

def plan_trains(plan_name, area):
    return any(E.cosine(E._PARTS[pe["exercise"]["target_body_area"]], E._PARTS[area]) > 0
               for pe in PLAN[plan_name]["plan_exercise"])


def test_every_plan_shown_trains_the_affected_area():
    # "Balance and Fall Prevention" is labelled FULL_BODY but has only leg exercises: an arm patient
    # must never get it.
    for req in grid():
        res = recommend(req)
        for r in res.ranked:
            assert plan_trains(NAME[r.plan_id], req.rehab.affected_body_area)
    res = recommend(RecommendRequest.model_validate(body(**ARM_EARLY)))
    assert "Balance and Fall Prevention" not in names(res.model_dump())
    left = next(e for e in res.excluded if NAME[e.plan_id] == "Balance and Fall Prevention")
    assert "none of its exercises trains BOTH_ARMS" in left.reasons


def test_area_score_comes_from_the_exercises():
    legs = RecommendRequest.model_validate(body(area="BOTH_LEGS"))
    balance = E.PlanIn.model_validate(PLAN["Balance and Fall Prevention"])
    reconditioning = E.PlanIn.model_validate(PLAN["Disuse Atrophy Reconditioning"])   # 2 leg, 1 arm exercise
    assert E.score(legs, balance).body_area == pytest.approx(1.0)
    arms = RecommendRequest.model_validate(body(**ARM_EARLY))
    assert 0 < E.score(arms, reconditioning).body_area < E.score(legs, reconditioning).body_area


def test_a_limitation_on_the_treated_limb_gives_gentle_plans_not_none():
    for stage, mobility in (("EARLY", "LOW"), ("INTERMEDIATE", "MODERATE"), ("ADVANCED", "HIGH")):
        res = recommend(RecommendRequest.model_validate(body(
            area="BOTH_LEGS", stage=stage, mobility=mobility, goal="STRENGTH", intensity="MODERATE",
            limitations=["LEFT_LEG_MOBILITY"])))
        assert res.status != "NONE"
        for r in res.ranked:
            p = PLAN[NAME[r.plan_id]]
            assert (p["recovery_stage"], p["mobility_level"]) == ("EARLY", "LOW")
        assert "Lower Limb Strength Builder" not in names(res.model_dump())


def test_a_limitation_on_another_limb_still_excludes_its_exercises():
    # A leg patient whose left arm is limited: Disuse Atrophy Reconditioning has Shoulder Abduction.
    res = recommend(RecommendRequest.model_validate(body(area="BOTH_LEGS", goal="ENDURANCE",
                                                         limitations=["LEFT_ARM_MOBILITY"])))
    assert "Disuse Atrophy Reconditioning" not in names(res.model_dump())
    left = next(e for e in res.excluded if NAME[e.plan_id] == "Disuse Atrophy Reconditioning")
    assert any(r.startswith("conflicts with LEFT_ARM_MOBILITY") for r in left.reasons)


def test_right_arm_patient_with_a_limited_left_arm_gets_gentle_arm_plans():
    res = recommend(RecommendRequest.model_validate(body(area="RIGHT_ARM", stage="INTERMEDIATE",
                                                         mobility="MODERATE", goal="STRENGTH",
                                                         limitations=["LEFT_ARM_MOBILITY"])))
    got = names(res.model_dump())
    assert got and "Upper Limb Strength" not in got
    assert set(got) <= {"Shoulder Mobility Starter", "Hand and Wrist Recovery", "Disuse Atrophy Reconditioning"}


def test_no_weak_fillers():
    for req in grid():
        res = recommend(req)
        if len(res.ranked) > 1:
            best = res.ranked[0].suitability_score
            for r in res.ranked:
                assert r.content_score >= E.MIN_MATCH - 1e-9
                assert r.suitability_score >= E.RELATIVE_MATCH * best - 1e-3


def test_closest_plan_is_shown_when_none_matches_well():
    # Arm strength at the intermediate stage under a low-intensity limit: Upper Limb Strength has the
    # moderate Wall Push-Up, so only early arm mobility plans are safe, none a good match.
    res = recommend(RecommendRequest.model_validate(body(area="LEFT_ARM", stage="INTERMEDIATE", mobility="HIGH",
                                                         goal="STRENGTH", intensity="LOW")))
    assert res.status == "ONLY_ONE" and res.suitable_count >= 2
    assert any("weaker match" in r for e in res.excluded for r in e.reasons)


def test_easing_leaves_out_the_failed_exercise_at_the_same_dose():
    # Elbow Flexion failed in Shoulder Mobility Starter (10 repetitions): Hand and Wrist Recovery has it
    # at 10 too, so it is left out.
    failed = EXERCISE["Elbow Flexion"]["exercise_id"]
    h = history("Shoulder Mobility Starter", fails=3)
    h["current_exercise_id"] = failed
    res = recommend(from_plan("Shoulder Mobility Starter", plans=[h], exercises=[result("Elbow Flexion", 3, 0, 60)]))
    assert res.next_step == "EASE"
    assert "Hand and Wrist Recovery" not in names(res.model_dump())
    hand = next(e for e in res.excluded if NAME[e.plan_id] == "Hand and Wrist Recovery")
    assert any("contains Elbow Flexion at the same or a higher dose" in r for r in hand.reasons)


def test_easing_keeps_an_easier_dose_of_the_failed_exercise():
    # Elbow Flexion failed in Upper Limb Strength (12 repetitions): the early arm plans have it at 10,
    # an easier dose, so they are offered (laptop, 10 Oct: only a full-body plan was left before).
    failed = EXERCISE["Elbow Flexion"]["exercise_id"]
    h = history("Upper Limb Strength", fails=3)
    h["current_exercise_id"] = failed
    res = recommend(from_plan("Upper Limb Strength", plans=[h], exercises=[result("Elbow Flexion", 3, 0, 75)]))
    got = names(res.model_dump())
    assert res.next_step == "EASE"
    # both early arm plans are offered and one leads (they are near-twins, so diversity puts
    # another plan between them)
    assert {"Shoulder Mobility Starter", "Hand and Wrist Recovery"} <= set(got)
    assert got[0] in {"Shoulder Mobility Starter", "Hand and Wrist Recovery"}
    assert "Elbow Flexion is still there, with fewer repetitions or less time" in res.next_step_reason


def test_easier_dose():
    from app.recommend.schemas import PlanExerciseIn
    pe = PlanExerciseIn.model_validate({"exercise": EXERCISE["Elbow Flexion"], "prescribed_duration_sec": 60,
                                          "prescribed_repetitions": 10})
    assert E.is_easier_dose(pe, (12, 60))
    assert not E.is_easier_dose(pe, (10, 60))
    assert not E.is_easier_dose(pe, (8, 90))          # fewer repetitions there, more time: not simply easier
    assert E.is_easier_dose(pe, (None, 90))
    assert not E.is_easier_dose(pe, None)


def test_easing_keeps_plans_with_the_failed_exercise_when_nothing_else_is_left():
    # A leg patient limited to EARLY/LOW whose only other leg plans also have Sit-to-Stand.
    failed = EXERCISE["Sit-to-Stand"]["exercise_id"]
    h = history("Balance and Fall Prevention", fails=3)
    h["current_exercise_id"] = failed
    b = body(area="BOTH_LEGS", goal="BALANCE", intensity="LOW")
    b["progress"] = {"plans": [h], "exercises": [], "from_plan_id": PLAN["Balance and Fall Prevention"]["plan_id"]}
    res = recommend(RecommendRequest.model_validate(b))
    assert res.next_step == "EASE" and res.ranked


def test_easing_with_no_gentler_plan_says_so():
    # The catalogue has one core plan: easing it leaves nothing, and the reason explains it.
    res = recommend(from_plan("Core and Back Care", plans=[history("Core and Back Care", fails=3)]))
    assert res.next_step == "EASE" and res.status == "NONE"
    assert "No gentler plan for this area fits your safety limits" in res.next_step_reason
    assert res.next_step_reason.startswith("The current exercise in Core and Back Care did not pass 3 times")


def test_completed_plans_left_out_only_when_they_train_the_area():
    # Moving on from Early Knee Recovery: the completed Hand and Wrist plan (arms) is not left out
    # for being completed, it is simply not a leg plan.
    res = recommend(from_plan("Early Knee Recovery", plans=[history("Early Knee Recovery", "COMPLETED", 100),
                                                            history("Hand and Wrist Recovery", "COMPLETED", 100)]))
    hand = next(e for e in res.excluded if NAME[e.plan_id] == "Hand and Wrist Recovery")
    assert hand.reasons[0] != "already completed"


def test_plans_are_listed_best_first():
    # Diversity picks which plans are shown, never their order.
    for req in grid():
        scores = [r.suitability_score for r in recommend(req).ranked]
        assert scores == sorted(scores, reverse=True)


# ---- 11 Oct: age limit and reasons for the patient ------------------------------------------------

from app.recommend import explain as X     # noqa: E402

KNOWN_CODES = {"TOO_INTENSE", "TOO_LONG", "LIMB_OTHER", "LIMB_GENTLE", "LATER_STAGE", "HIGHER_MOBILITY", "NOT_AREA",
               "DONE", "EASED", "FAILED_EXERCISE", "WEAK_MATCH", "AGE_LIMIT", "NEXT_STAGE", "EASIER", "EASIER_DOSE",
               "MATCH_AREA", "DOSE_STRENGTH", "DOSE_BALANCE", "DOSE_MOBILITY", "SAFE", "PERSONAL"}


def test_no_plan_from_age_65():
    b = body()
    b["age"] = 65
    res = recommend(RecommendRequest.model_validate(b))
    assert res.status == "NONE" and res.restriction == "AGE_65_PLUS" and not res.ranked
    assert len(res.excluded) == len(CATALOGUE["plans"])
    assert all([w.code for w in e.why] == ["AGE_LIMIT"] for e in res.excluded)
    assert "Terms of Use" in res.next_step_reason and "you are 65" in res.next_step_reason
    assert set(res.excluded[0].why[0].sources) == set(X.AGE_SOURCES)


def test_age_64_and_no_age_are_unchanged():
    plain = recommend(RecommendRequest.model_validate(body()))
    b = body()
    b["age"] = 64
    young = recommend(RecommendRequest.model_validate(b))
    assert young.restriction is None and plain.restriction is None
    assert [r.plan_id for r in young.ranked] == [r.plan_id for r in plain.ranked]


def test_age_limit_through_the_api_keeps_any_progress_out():
    b = body()
    b["age"] = 80
    b["progress"] = {"plans": [history("Early Knee Recovery", fails=3)], "exercises": [],
                     "from_plan_id": PLAN["Early Knee Recovery"]["plan_id"]}
    r = client.post("/recommend", json=b, headers=DEV)
    assert r.status_code == 200, r.text
    res = r.json()
    assert res["restriction"] == "AGE_65_PLUS" and res["ranked"] == [] and "Terms of Use" in res["next_step_reason"]


def test_every_decision_has_a_patient_reason_with_known_sources():
    # Over the 720 answer sets: one patient reason per rule, no fallback text, known codes and keys.
    for req in grid():
        res = recommend(req)
        for e in res.excluded:
            assert len(e.why) == len(e.reasons), (e.reasons, e.why)
        for r in res.ranked:
            assert 2 <= len(r.why) <= 4 and r.why[0].code == "MATCH_AREA"
        for w in [w for e in res.excluded for w in e.why] + [w for r in res.ranked for w in r.why]:
            assert w.code in KNOWN_CODES and w.text.endswith(".") and set(w.sources) <= X.SOURCE_KEYS


def test_safety_reasons_cite_the_patients_conditions():
    b = body(intensity="LOW")
    b["conditions"] = ["HYPERTENSION", "DIABETES"]
    res = recommend(RecommendRequest.model_validate(b))
    safe = next(w for w in res.ranked[0].why if w.code == "SAFE")
    assert safe.sources[:2] == ["hk_doh", "colberg2016"]
    hard = next(w for e in res.excluded for w in e.why if w.code == "TOO_INTENSE")
    assert hard.sources == ["hk_doh", "colberg2016"]
    assert X.intensity_sources([]) == ["acsm2009"]


def test_why_not_names_the_exercises_and_the_limb():
    res = recommend(RecommendRequest.model_validate(body(intensity="LOW", limitations=["LEFT_ARM_MOBILITY"])))
    why = {NAME[e.plan_id]: {w.code: w.text for w in e.why} for e in res.excluded}
    assert why["Lower Limb Strength Builder"]["TOO_INTENSE"].startswith("It includes Mini Squat and Step-Up, which "
                                                                        "are harder")
    assert "use your left arm, which your profile lists as limited" in why["Shoulder Mobility Starter"]["LIMB_OTHER"]


def test_easing_explains_the_easier_dose():
    failed = EXERCISE["Elbow Flexion"]["exercise_id"]
    h = history("Upper Limb Strength", fails=3)
    h["current_exercise_id"] = failed
    res = recommend(from_plan("Upper Limb Strength", plans=[h], exercises=[result("Elbow Flexion", 3, 0, 75)]))
    first = [w.code for w in res.ranked[0].why]
    assert first[:2] == ["EASIER", "EASIER_DOSE"] and "Elbow Flexion is still here" in res.ranked[0].why[1].text


def test_progress_explains_the_next_stage():
    res = recommend(from_plan("Early Knee Recovery", plans=[history("Early Knee Recovery", "COMPLETED", 100)],
                              exercises=KNEE_DONE))
    raised = [r for r in res.ranked if PLAN[NAME[r.plan_id]]["recovery_stage"] != "EARLY"]
    assert res.next_step == "PROGRESS" and raised
    assert all(r.why[0].code == "NEXT_STAGE" for r in raised)


def test_the_app_lists_every_source_key():
    path = Path(__file__).parents[2] / "lib" / "core" / "constants" / "evidence_sources.dart"
    if not path.exists():
        pytest.skip("the app is not next to the server (fyp-fastapi copy)")
    dart = path.read_text(encoding="utf-8")
    missing = [k for k in X.SOURCE_KEYS if f"'{k}'" not in dart]
    assert not missing, missing


# ---- 11 Oct: more health conditions --------------------------------------------------------------

from app.recommend import conditions as CONDS     # noqa: E402


def test_every_catalogue_exercise_has_a_body_position():
    assert all(e.get("body_position") in {"STANDING", "SEATED", "EITHER", "SUPINE", "ALL_FOURS", "TABLE"}
               for e in CATALOGUE["exercises"])


def test_pregnancy_leaves_out_exercises_on_the_back_with_the_reason():
    b = body(area="BOTH_LEGS", stage="INTERMEDIATE", mobility="MODERATE", goal="BALANCE")
    b["conditions"] = ["PREGNANCY"]
    res = recommend(RecommendRequest.model_validate(b))
    shown = names(res.model_dump())
    assert shown and not any(pe["exercise"]["body_position"] == "SUPINE"
                             for n in shown for pe in PLAN[n]["plan_exercise"])
    why = {NAME[e.plan_id]: e.why for e in res.excluded}
    hip = [w for w in why["Hip Stability"] if w.code == "CONDITION_AVOID"][0]
    assert "Glute Bridge" in hip.text and "lying on your back" in hip.text and hip.sources == ["acog2020"]


def test_a_foot_ulcer_leaves_out_standing_exercises_but_not_seated_ones():
    b = body(area="BOTH_ARMS", stage="EARLY", mobility="LOW", goal="MOBILITY")
    b["conditions"] = ["FOOT_ULCER"]
    res = recommend(RecommendRequest.model_validate(b))
    shown = names(res.model_dump())
    assert "Hand and Wrist Recovery" in shown               # elbow flexion can be done sitting
    assert "Shoulder Mobility Starter" not in shown          # standing arm raises
    for n in shown:
        assert all(pe["exercise"]["body_position"] != "STANDING" for pe in PLAN[n]["plan_exercise"])


def test_conditions_without_a_position_rule_change_only_the_sources():
    plain = recommend(RecommendRequest.model_validate(body()))
    b = body()
    b["conditions"] = ["COPD", "KIDNEY_DISEASE", "PARKINSONS"]
    res = recommend(RecommendRequest.model_validate(b))
    assert [r.plan_id for r in res.ranked] == [r.plan_id for r in plain.ranked]
    safe = next(w for w in res.ranked[0].why if w.code == "SAFE")
    assert safe.sources[:3] == ["spruit2013", "kdigo2024", "osborne2022"]


def test_every_condition_source_is_a_known_key():
    keys = set(CONDS.CONDITION_SOURCES.values()) | {s for c in CONDS.AVOID_POSITIONS.values() for s in c["sources"]}
    assert keys <= X.SOURCE_KEYS


def test_area_reason_reads_as_a_sentence():
    # "It trains your legs, for the goal you chose." (24 Oct: "... and the goal you chose" read as if
    # the goal were trained). Over the 720 answer sets, with and without the same goal.
    import re
    seen = set()
    for req in grid():
        for r in recommend(req).ranked:
            text = r.why[0].text
            assert re.fullmatch(r"It trains your [a-z ]+(, for the goal you chose)?\.", text), text
            seen.add(text.endswith("goal you chose."))
    assert seen == {True, False}
