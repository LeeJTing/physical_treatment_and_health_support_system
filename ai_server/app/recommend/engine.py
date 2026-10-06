"""Hybrid Plan Recommender (M500.1, FR500_05 to FR500_07, FR500_14, FR500_15).

Stage 1, knowledge-based filter: a plan is dropped when it is unsafe or
irrelevant for the patient. Every reason is reported back so the decision
can be explained.
  - an exercise above SafetyLimit.max_exercise_intensity
  - the plan's total prescribed time above SafetyLimit.max_session_duration_min
  - an exercise on a body area blocked by a physical limitation
    (same rule as Exercise.conflictsWith in the app)
  - a plan for a later recovery stage, or a higher mobility level, than the patient's
  - a plan that does not train the affected body area at all

Stage 2, content-based score: the patient and each remaining plan are encoded
as feature vectors with four blocks (body area, goal, recovery stage, mobility
level). Each block is compared with cosine similarity and the four
similarities are combined as a weighted mean, which equals the cosine of the
concatenated vectors when every block is scaled to length sqrt(weight).

Stage 3, rank by score and keep the best three.
"""
import math

from .schemas import PlanIn, RankedPlan, RecommendRequest, RecommendResponse, ExcludedPlan, ScoreBreakdown

MODEL_VERSION = "hybrid-1.0"
TOP_N = 3

WEIGHTS = {"body_area": 0.40, "goal": 0.25, "recovery_stage": 0.20, "mobility_level": 0.15}

# Body areas as membership over five body parts: left arm, right arm, left leg, right leg, core.
# Overlapping areas (LEFT_ARM vs BOTH_ARMS, anything vs FULL_BODY) get partial similarity.
_PARTS = {
    "LEFT_ARM": (1, 0, 0, 0, 0),
    "RIGHT_ARM": (0, 1, 0, 0, 0),
    "BOTH_ARMS": (1, 1, 0, 0, 0),
    "LEFT_LEG": (0, 0, 1, 0, 0),
    "RIGHT_LEG": (0, 0, 0, 1, 0),
    "BOTH_LEGS": (0, 0, 1, 1, 0),
    "CORE": (0, 0, 0, 0, 1),
    "FULL_BODY": (1, 1, 1, 1, 1),
}

GOALS = ("STRENGTH", "MOBILITY", "BALANCE", "PAIN_RELIEF", "ENDURANCE")

# Ordinal levels as soft one-hot vectors, so a neighbouring level still scores partly.
_ORDINAL = ((1.0, 0.5, 0.0), (0.5, 1.0, 0.5), (0.0, 0.5, 1.0))
STAGES = ("EARLY", "INTERMEDIATE", "ADVANCED")
MOBILITY = ("LOW", "MODERATE", "HIGH")
INTENSITY = ("LOW", "MODERATE", "VIGOROUS")


def cosine(a, b) -> float:
    dot = sum(x * y for x, y in zip(a, b))
    na = math.sqrt(sum(x * x for x in a))
    nb = math.sqrt(sum(y * y for y in b))
    return 0.0 if na == 0 or nb == 0 else dot / (na * nb)


def _goal_vec(goal: str | None):
    return tuple(1.0 if g == goal else 0.0 for g in GOALS)


def blocked_area(limitation_code: str) -> str | None:
    """LEFT_ARM_MOBILITY -> LEFT_ARM. Balance limitations block no single area."""
    if not limitation_code.endswith("_MOBILITY"):
        return None
    return limitation_code.removesuffix("_MOBILITY")


def conflicts(exercise_area: str, blocked: str) -> bool:
    """Mirror of Exercise.conflictsWith in lib/data/models/exercise.dart."""
    if exercise_area == blocked:
        return True
    if blocked.endswith("_ARM"):
        return exercise_area == "BOTH_ARMS"
    return exercise_area in ("BOTH_LEGS", "FULL_BODY")


def exclusion_reasons(req: RecommendRequest, plan: PlanIn) -> list[str]:
    reasons = []
    cap = INTENSITY.index(req.safety_limit.max_exercise_intensity)
    too_hard = [pe.exercise for pe in plan.plan_exercise if INTENSITY.index(pe.exercise.intensity_level) > cap]
    if too_hard:
        names = ", ".join(e.exercise_name or e.exercise_id for e in too_hard)
        reasons.append(f"intensity above {req.safety_limit.max_exercise_intensity}: {names}")

    total_sec = sum(pe.prescribed_duration_sec for pe in plan.plan_exercise)
    if total_sec > req.safety_limit.max_session_duration_min * 60:
        reasons.append(f"session {total_sec // 60} min exceeds {req.safety_limit.max_session_duration_min} min")

    for code in req.limitations:
        area = blocked_area(code)
        if area is None:
            continue
        hit = [pe.exercise for pe in plan.plan_exercise if conflicts(pe.exercise.target_body_area, area)]
        if hit:
            names = ", ".join(e.exercise_name or e.exercise_id for e in hit)
            reasons.append(f"conflicts with {code}: {names}")

    if STAGES.index(plan.recovery_stage) > STAGES.index(req.rehab.recovery_stage):
        reasons.append(f"plan is for {plan.recovery_stage} stage, patient is {req.rehab.recovery_stage}")
    if MOBILITY.index(plan.mobility_level) > MOBILITY.index(req.rehab.mobility_level):
        reasons.append(f"plan needs {plan.mobility_level} mobility, patient has {req.rehab.mobility_level}")

    if cosine(_PARTS[plan.target_body_area], _PARTS[req.rehab.affected_body_area]) == 0:
        reasons.append(f"plan targets {plan.target_body_area}, not {req.rehab.affected_body_area}")
    return reasons


def score(req: RecommendRequest, plan: PlanIn) -> ScoreBreakdown:
    r = req.rehab
    return ScoreBreakdown(
        body_area=cosine(_PARTS[r.affected_body_area], _PARTS[plan.target_body_area]),
        goal=cosine(_goal_vec(r.goal), _goal_vec(plan.goal)),
        recovery_stage=cosine(_ORDINAL[STAGES.index(r.recovery_stage)], _ORDINAL[STAGES.index(plan.recovery_stage)]),
        mobility_level=cosine(_ORDINAL[MOBILITY.index(r.mobility_level)], _ORDINAL[MOBILITY.index(plan.mobility_level)]),
    )


def weighted(b: ScoreBreakdown) -> float:
    return sum(WEIGHTS[k] * getattr(b, k) for k in WEIGHTS) / sum(WEIGHTS.values())


def recommend(req: RecommendRequest) -> RecommendResponse:
    ranked, excluded = [], []
    for plan in req.plans:
        reasons = exclusion_reasons(req, plan)
        if reasons:
            excluded.append(ExcludedPlan(plan_id=plan.plan_id, reasons=reasons))
            continue
        b = score(req, plan)
        rounded = ScoreBreakdown(**{k: round(v, 3) for k, v in b.model_dump().items()})
        ranked.append((weighted(b), plan.plan_name, RankedPlan(plan_id=plan.plan_id, suitability_score=round(weighted(b), 3), breakdown=rounded)))

    # Highest score first; plan name breaks ties so the same input always gives the same order.
    ranked.sort(key=lambda t: (-t[0], t[1]))
    top = [t[2] for t in ranked[:TOP_N]]
    status = "NONE" if not top else "ONLY_ONE" if len(top) == 1 else "OK"
    return RecommendResponse(status=status, ranked=top, excluded=excluded,
                             suitable_count=len(ranked), model_version=MODEL_VERSION)
