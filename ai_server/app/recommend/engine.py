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

Stage 3, collaborative score (hybrid-2.0, report 2.7 and Table 2.7): how patients with a similar
risk level and age band did on the plan, from anonymised cohort cells the app reads through the
plan_outcome_stats() RPC (the server never reads Supabase). User-based neighbourhood filtering:
  cell outcome    o  = clamp(0.5 * completion_rate + 0.3 * accuracy/100 + 0.2 * progress/100),
                       a missing accuracy or progress counting as the neutral 0.5
  cell similarity s  = mean of the cosines of the risk and age-band soft one-hot vectors
  evidence        n  = sum(s * patients)        raw cf = sum(s * patients * o) / n
  shrinkage       cf = (n * cf + K * 0.5) / (n + K)          (sparse data, report para 936)
  blend       final  = (1 - alpha) * content + alpha * cf,   alpha = ALPHA_MAX * n / (n + K)
With no evidence alpha is 0 and the result equals the content + rules ranking (cold start). The
rules always run first, so evidence can only re-order plans that are already safe. alpha stays
small on purpose: plans given to healthier patients look better (confounding), and the risk and
age cells only partly control for that.

Stage 4, rank by score and keep the best three, with a light MMR diversity re-rank (report para
944, 950): a plan that nearly duplicates one already picked (plan similarity above DUPLICATE_SIM)
is penalised, so the three picks are not the same plan three times. Below that similarity the
order is unchanged.
"""
import math

from .schemas import (PlanIn, PlanOutcomeIn, RankedPlan, RecommendRequest, RecommendResponse, ExcludedPlan,
                      ScoreBreakdown)

MODEL_VERSION = "hybrid-2.0"
TOP_N = 3

# Collaborative part.
MIN_PATIENTS = 5          # k-anonymity: smaller cells are ignored (the RPC already drops them)
K = 20.0                  # shrinkage strength and alpha half-saturation, in similar patients
ALPHA_MAX = 0.3           # the collaborative score never decides more than 30 % of the result
NEUTRAL = 0.5
OUTCOME_WEIGHTS = {"completion": 0.5, "accuracy": 0.3, "progress": 0.2}
RISKS = ("Low", "Medium", "High")
AGE_BANDS = ("<60", "60-74", "75+")

# Diversity re-rank (maximal marginal relevance).
MMR_LAMBDA = 0.8
DUPLICATE_SIM = 0.80      # only near-twins (same area and goal, neighbouring level: 0.906 in the seed) are penalised

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


# ---- collaborative part ---------------------------------------------------------------------

def cell_outcome(c: PlanOutcomeIn) -> float:
    """How well the patients in one cell did, 0..1. Missing accuracy or progress is neutral."""
    acc = NEUTRAL if c.mean_accuracy is None else c.mean_accuracy / 100
    prog = NEUTRAL if c.mean_progress is None else c.mean_progress / 100
    o = (OUTCOME_WEIGHTS["completion"] * c.completion_rate + OUTCOME_WEIGHTS["accuracy"] * acc
         + OUTCOME_WEIGHTS["progress"] * prog)
    return min(1.0, max(0.0, o))


def cohort_similarity(req: RecommendRequest, c: PlanOutcomeIn) -> float:
    me = req.cohort
    risk = cosine(_ORDINAL[RISKS.index(me.risk_level)], _ORDINAL[RISKS.index(c.risk_level)])
    age = cosine(_ORDINAL[AGE_BANDS.index(me.age_band)], _ORDINAL[AGE_BANDS.index(c.age_band)])
    return (risk + age) / 2


def collaborative(req: RecommendRequest, plan_id: str) -> tuple[float | None, float]:
    """(shrunk collaborative score or None, evidence n) for one plan."""
    if req.cohort is None:
        return None, 0.0
    n = acc = 0.0
    for c in req.plan_outcomes:
        if c.plan_id != plan_id or c.patients < MIN_PATIENTS:
            continue
        w = cohort_similarity(req, c) * c.patients
        n += w
        acc += w * cell_outcome(c)
    if n == 0:
        return None, 0.0
    return (acc + K * NEUTRAL) / (n + K), n


def blend(content: float, cf: float | None, n: float) -> tuple[float, float]:
    """(final score, alpha). alpha = 0 without evidence, so the content score passes unchanged."""
    if cf is None:
        return content, 0.0
    alpha = ALPHA_MAX * n / (n + K)
    return (1 - alpha) * content + alpha * cf, alpha


# ---- diversity re-rank ----------------------------------------------------------------------

def plan_similarity(a: PlanIn, b: PlanIn) -> float:
    """Content similarity between two plans, same blocks and weights as the patient score."""
    blocks = {
        "body_area": cosine(_PARTS[a.target_body_area], _PARTS[b.target_body_area]),
        "goal": cosine(_goal_vec(a.goal), _goal_vec(b.goal)),
        "recovery_stage": cosine(_ORDINAL[STAGES.index(a.recovery_stage)], _ORDINAL[STAGES.index(b.recovery_stage)]),
        "mobility_level": cosine(_ORDINAL[MOBILITY.index(a.mobility_level)],
                                 _ORDINAL[MOBILITY.index(b.mobility_level)]),
    }
    return sum(WEIGHTS[k] * v for k, v in blocks.items()) / sum(WEIGHTS.values())


def redundancy(a: PlanIn, b: PlanIn) -> float:
    """0 up to DUPLICATE_SIM, rising to 1 for an identical plan."""
    return max(0.0, (plan_similarity(a, b) - DUPLICATE_SIM) / (1 - DUPLICATE_SIM))


def diversify(scored: list[tuple[float, PlanIn]], k: int = TOP_N,
              lam: float = MMR_LAMBDA) -> list[tuple[float, PlanIn]]:
    """Greedy MMR over plans that already passed the rules, best first. Only re-orders the
    candidates it is given, so an excluded plan can never come back."""
    remaining, picked = list(scored), []
    while remaining and len(picked) < k:
        def mmr(item):
            return lam * item[0] - (1 - lam) * max((redundancy(item[1], p) for _, p in picked), default=0.0)
        best = max(range(len(remaining)), key=lambda i: (mmr(remaining[i]), -i))   # ties keep score order
        picked.append(remaining.pop(best))
    return picked


def recommend(req: RecommendRequest, lam: float = MMR_LAMBDA) -> RecommendResponse:
    scored, excluded, details = [], [], {}
    for plan in req.plans:
        reasons = exclusion_reasons(req, plan)
        if reasons:
            excluded.append(ExcludedPlan(plan_id=plan.plan_id, reasons=reasons))
            continue
        b = score(req, plan)
        content = weighted(b)
        cf, n = collaborative(req, plan.plan_id)
        final, alpha = blend(content, cf, n)
        b.collaborative = cf
        details[plan.plan_id] = (b, content, alpha, n)
        scored.append((final, plan))

    # Highest score first; plan name breaks ties so the same input always gives the same order.
    scored.sort(key=lambda t: (-t[0], t[1].plan_name))
    top = []
    for final, plan in diversify(scored, TOP_N, lam):
        b, content, alpha, n = details[plan.plan_id]
        rounded = ScoreBreakdown(**{k: (None if v is None else round(v, 3)) for k, v in b.model_dump().items()})
        top.append(RankedPlan(plan_id=plan.plan_id, suitability_score=round(final, 3), breakdown=rounded,
                              content_score=round(content, 3), alpha=round(alpha, 3), evidence_patients=round(n)))
    status = "NONE" if not top else "ONLY_ONE" if len(top) == 1 else "OK"
    return RecommendResponse(status=status, ranked=top, excluded=excluded,
                             suitable_count=len(scored), model_version=MODEL_VERSION)
