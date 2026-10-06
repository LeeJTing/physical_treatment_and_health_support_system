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
    assert names(res)[0] == "Shoulder Mobility Starter"


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
