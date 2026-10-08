"""Tests for the hybrid recommender, run against the real seed catalogue."""
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
    res = post(area="FULL_BODY", stage="ADVANCED", mobility="HIGH", goal="ENDURANCE", minutes=5)
    assert "Active Recovery Circuit" not in names(res)  # 7 min of exercises


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
    res = post(area="LEFT_ARM", stage="EARLY", mobility="LOW", limitations=["LEFT_ARM_MOBILITY"],
               intensity="LOW", minutes=1)
    assert res["status"] == "NONE" and res["ranked"] == [] and res["suitable_count"] == 0
    assert len(res["excluded"]) == len(CATALOGUE["plans"])


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
TWIN_PAIRS = [TWINS, ARM_TWINS]


def hybrid_1(req):
    """hybrid-1.0 as it was: rules, content score, best three by score then name."""
    ranked = [(E.weighted(E.score(req, p)), p.plan_name, p.plan_id) for p in req.plans
              if not E.exclusion_reasons(req, p)]
    ranked.sort(key=lambda t: (-t[0], t[1]))
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
    assert res["model_version"] == "hybrid-2.0"
    top = next(x for x in res["ranked"] if NAME[x["plan_id"]] == "Early Knee Recovery")
    assert top["evidence_patients"] == 30 and 0 < top["alpha"] <= 0.3
    assert top["breakdown"]["collaborative"] is not None
