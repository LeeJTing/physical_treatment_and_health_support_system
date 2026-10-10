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

Body-part focus (hybrid-2.1, optional): the body map gives finer parts than the eight body areas
(shoulder, elbow, wrist_hand, hip, knee, ankle_foot, back). A plan's parts come from its
exercises' pose keys (POSE_PARTS), summed over the exercises. When the request has focus parts,
a fifth block, the cosine of the two part vectors, joins the weighted mean with FOCUS_WEIGHT and
the same block joins the plan similarity used by the diversity re-rank. Without focus parts
neither changes, so the result equals hybrid-2.0. This separates plans the four blocks cannot,
e.g. Shoulder Mobility Starter and Hand and Wrist Recovery (both BOTH_ARMS, EARLY, LOW, MOBILITY).

Pace (hybrid-2.2, optional): the questionnaire's optional "How fast would you like to go?" (SLOW,
MEDIUM, FAST = about 3, 4, 5 days a week) is compared with the plan's frequency_per_week as soft
one-hot ordinals, weight PACE_WEIGHT, only when the request has a pace. It only re-orders plans
that passed the rules; it is not part of the diversity similarity.

Stage 4, rank by score and keep the best three, with a light MMR diversity re-rank (report para
944, 950): a plan that nearly duplicates one already picked (plan similarity above DUPLICATE_SIM)
is penalised, so the three picks are not the same plan three times. Below that similarity the
order is unchanged.

Progress (hybrid-3.0, optional; report 2.7: the plan changes with the patient's situation instead
of staying static). The request may carry the patient's own history: their plans (status, progress,
failed attempts in a row at the current exercise, fall alerts) and their results per exercise
(attempts, passes, mean accuracy). Two things follow from it.
  Next step, decided before the rules run:
    EASE      a plan being followed has a possible fall, or EASE_FAILS attempts in a row that did
              not pass and trains the requested body area: the stage and mobility the rules allow
              go one level below that plan's (never above the patient's answers), and that plan is
              left out.
    PROGRESS  a plan that trains the requested body area was completed: the rules allow one level
              above the highest such plan (never below the patient's answers), and completed plans
              are left out.
    STAY      history without either: the patient's answers are used as they are.
    START     no history: same as hybrid-2.2.
  Only the stage and mobility move. Intensity, session time and physical limitations are checked
  exactly as before, so a step up can never bring in an exercise above the safety limit.
  Personal score, item-to-item over the patient's own results: an exercise the patient has not
  done is predicted from the ones they have, weighted by exercise similarity (body parts trained,
  body area, intensity) and by attempts, and shrunk towards neutral when evidence is thin:
      performance(j) = 0.6 * passes/attempts + 0.4 * mean_accuracy/100
      predicted(e)   = (sum w_j * performance(j) + K_PERSONAL * 0.5) / (sum w_j + K_PERSONAL),
                       w_j = similarity(e, j) ** AMPLIFY * attempts_j for similarity >= SIM_FLOOR
                       (case amplification, Breese et al., 1998: the exercise itself counts most)
      personal(plan) = mean predicted(e) over the plan's exercises; after PROGRESS, multiplied by
                       1 - NOVELTY * share of exercises already mastered (passed PASS_MASTERED times)
      final          = hybrid-2.2 score + beta * (personal - 0.5)   (reported clamped to 0..1),
                       beta = BETA_MAX * evidence / (evidence + K_PERSONAL)
  Centred on 0.5, so a plan the history says nothing about keeps its score and good or poor
  results move a plan up or down from there. Like the collaborative score, it only re-orders
  plans that passed the rules.
"""
import math

from .schemas import (ExerciseIn, ExerciseResultIn, PlanIn, PlanOutcomeIn, RankedPlan, RecommendRequest,
                      RecommendResponse, ExcludedPlan, ScoreBreakdown)

MODEL_VERSION = "hybrid-3.0"
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

# Body-part focus block: modest, so it separates otherwise equal plans more than it overrides
# the area, goal, stage and mobility match.
FOCUS_WEIGHT = 0.20
# Pace block: lighter than focus, a preference rather than a need.
PACE_WEIGHT = 0.10
PACES = ("SLOW", "MEDIUM", "FAST")
NEUTRAL_PACE = 0.5        # a plan without frequency_per_week

FOCUS_PARTS = ("shoulder", "elbow", "wrist_hand", "hip", "knee", "ankle_foot", "back")
POSE_PARTS = {
    "shoulder_abduction": ("shoulder",),
    "shoulder_flexion": ("shoulder",),
    "elbow_flexion": ("elbow",),
    "wall_push_up": ("elbow",),
    "wrist_extension": ("wrist_hand",),
    "hand_open_close": ("wrist_hand",),
    "hip_abduction": ("hip",),
    "seated_marching": ("hip",),
    "march_in_place": ("hip",),
    "glute_bridge": ("hip", "back"),
    "bird_dog": ("back",),
    "knee_extension": ("knee",),
    "sit_to_stand": ("knee", "hip"),
    "mini_squat": ("knee", "hip"),
    "step_up": ("knee", "hip"),
    "heel_raise": ("ankle_foot",),
    "tandem_stance": ("ankle_foot",),
}

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


# Personal part (hybrid-3.0).
EASE_FAILS = 3            # attempts in a row that did not pass before an easier plan is suggested
PASS_MASTERED = 2         # an exercise passed this many times counts as mastered
K_PERSONAL = 3.0          # shrinkage and beta half-saturation, in similarity-weighted attempts
AMPLIFY = 2.5             # case amplification of the exercise similarity (Breese et al., 1998)
BETA_MAX = 0.3            # the personal score never decides more than 30 % of the result
SIM_FLOOR = 0.5           # exercises less similar than this say nothing about each other
EXERCISE_WEIGHTS = {"parts": 0.6, "area": 0.25, "intensity": 0.15}
NOVELTY = 0.5             # after PROGRESS a plan of only mastered exercises keeps half its personal score
PERFORMANCE_WEIGHTS = {"pass_rate": 0.6, "accuracy": 0.4}


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


def plan_parts(plan: PlanIn) -> tuple[float, ...]:
    """How many of the plan's exercises train each FOCUS_PARTS part (unknown pose keys add nothing)."""
    counts = dict.fromkeys(FOCUS_PARTS, 0.0)
    for pe in plan.plan_exercise:
        for part in POSE_PARTS.get(pe.exercise.pose_key or "", ()):
            counts[part] += 1
    return tuple(counts.values())


def focus_vec(parts) -> tuple[float, ...]:
    return tuple(1.0 if p in parts else 0.0 for p in FOCUS_PARTS)


def plan_pace(plan: PlanIn) -> int | None:
    """0, 1 or 2 for about 3 (or fewer), 4, or 5+ days a week; None when unknown."""
    f = plan.frequency_per_week
    if f is None:
        return None
    return 0 if f <= 3 else 1 if f == 4 else 2


def pace_score(req: RecommendRequest, plan: PlanIn) -> float | None:
    if req.pace is None:
        return None
    i = plan_pace(plan)
    if i is None:
        return NEUTRAL_PACE
    return cosine(_ORDINAL[PACES.index(req.pace)], _ORDINAL[i])


def score(req: RecommendRequest, plan: PlanIn) -> ScoreBreakdown:
    r = req.rehab
    return ScoreBreakdown(
        body_area=cosine(_PARTS[r.affected_body_area], _PARTS[plan.target_body_area]),
        goal=cosine(_goal_vec(r.goal), _goal_vec(plan.goal)),
        recovery_stage=cosine(_ORDINAL[STAGES.index(r.recovery_stage)], _ORDINAL[STAGES.index(plan.recovery_stage)]),
        mobility_level=cosine(_ORDINAL[MOBILITY.index(r.mobility_level)], _ORDINAL[MOBILITY.index(plan.mobility_level)]),
        focus=cosine(focus_vec(req.focus_parts), plan_parts(plan)) if req.focus_parts else None,
        pace=pace_score(req, plan),
    )


def weighted(b: ScoreBreakdown) -> float:
    """Weighted mean of the blocks; the focus and pace blocks only count when the request has them."""
    total, weight = sum(WEIGHTS[k] * getattr(b, k) for k in WEIGHTS), sum(WEIGHTS.values())
    for value, w in ((b.focus, FOCUS_WEIGHT), (b.pace, PACE_WEIGHT)):
        if value is not None:
            total += w * value
            weight += w
    return total / weight


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


# ---- personal part (hybrid-3.0) ---------------------------------------------------------------

def exercise_similarity(a: ExerciseIn, b: ExerciseIn) -> float:
    """1 for the same exercise; otherwise a weighted mean of the cosines of the body parts trained
    (POSE_PARTS), the body area and the intensity. Parts count only when both exercises have them."""
    if a.exercise_id == b.exercise_id:
        return 1.0
    blocks = {
        "area": cosine(_PARTS[a.target_body_area], _PARTS[b.target_body_area]),
        "intensity": cosine(_ORDINAL[INTENSITY.index(a.intensity_level)], _ORDINAL[INTENSITY.index(b.intensity_level)]),
    }
    pa, pb = POSE_PARTS.get(a.pose_key or ""), POSE_PARTS.get(b.pose_key or "")
    if pa and pb:
        blocks["parts"] = cosine(focus_vec(pa), focus_vec(pb))
    return sum(EXERCISE_WEIGHTS[k] * v for k, v in blocks.items()) / sum(EXERCISE_WEIGHTS[k] for k in blocks)


def performance(r: ExerciseResultIn) -> float:
    """How well the patient did on one exercise, 0..1. Without an accuracy the pass rate alone."""
    rate = min(1.0, r.passes / r.attempts)
    if r.mean_accuracy is None:
        return rate
    return PERFORMANCE_WEIGHTS["pass_rate"] * rate + PERFORMANCE_WEIGHTS["accuracy"] * r.mean_accuracy / 100


def catalogue_exercises(req: RecommendRequest) -> dict[str, ExerciseIn]:
    return {pe.exercise.exercise_id: pe.exercise for plan in req.plans for pe in plan.plan_exercise}


def personal(req: RecommendRequest, plan: PlanIn, step: str,
             exercises: dict[str, ExerciseIn]) -> tuple[float | None, float]:
    """(personal score or None, evidence per exercise) for one plan, item-to-item over the
    patient's own results. Results for exercises not in the catalogue are ignored."""
    if req.progress is None:
        return None, 0.0
    done = [(exercises[r.exercise_id], r) for r in req.progress.exercises if r.exercise_id in exercises]
    if not done:
        return None, 0.0
    own = {r.exercise_id: r for _, r in done}
    predicted, evidence, mastered = [], 0.0, 0
    for pe in plan.plan_exercise:
        n = acc = 0.0
        for ex, r in done:
            s = exercise_similarity(pe.exercise, ex)
            if s < SIM_FLOOR:
                continue
            w = s ** AMPLIFY * r.attempts
            n += w
            acc += w * performance(r)
        predicted.append((acc + K_PERSONAL * NEUTRAL) / (n + K_PERSONAL))
        evidence += n
        mine = own.get(pe.exercise.exercise_id)
        if mine is not None and mine.passes >= PASS_MASTERED:
            mastered += 1
    if evidence == 0:
        return None, 0.0
    score = sum(predicted) / len(predicted)
    if step == "PROGRESS":
        score *= 1 - NOVELTY * mastered / len(plan.plan_exercise)
    return score, evidence / len(plan.plan_exercise)


def blend_personal(base: float, p: float | None, evidence: float) -> tuple[float, float]:
    """(ranking score, beta). Centred on NEUTRAL: without evidence (beta = 0) or with neutral
    evidence the hybrid-2.2 score passes unchanged. Not clamped, so good results can still lift a
    plan that already matches fully above an equal plan without evidence; the reported
    suitability_score is clamped to 0..1."""
    if p is None:
        return base, 0.0
    beta = BETA_MAX * evidence / (evidence + K_PERSONAL)
    return base + beta * (p - NEUTRAL), beta


def next_step(req: RecommendRequest) -> tuple[str, str, int, int, set[str]]:
    """(step, reason for the patient, stage index, mobility index, plan ids to leave out).
    Easing is checked before progressing: safety first."""
    stage = STAGES.index(req.rehab.recovery_stage)
    mob = MOBILITY.index(req.rehab.mobility_level)
    p = req.progress
    if p is None or (not p.plans and not p.exercises):
        return "START", "", stage, mob, set()
    by_id = {plan.plan_id: plan for plan in req.plans}
    area = _PARTS[req.rehab.affected_body_area]

    def same_area(plan_id: str) -> bool:
        return cosine(_PARTS[by_id[plan_id].target_body_area], area) > 0

    # A possible fall counts whatever the body area; failed attempts only for the area asked about.
    hard = [h for h in p.plans if h.status == "ACTIVE" and h.plan_id in by_id
            and (h.fall_alerts > 0 or (h.consecutive_fails >= EASE_FAILS and same_area(h.plan_id)))]
    if hard:
        h = max(hard, key=lambda x: (x.fall_alerts, x.consecutive_fails))
        plan = by_id[h.plan_id]
        s = max(0, min(stage, STAGES.index(plan.recovery_stage) - 1))
        m = max(0, min(mob, MOBILITY.index(plan.mobility_level) - 1))
        why = (f"A possible fall was seen during {plan.plan_name}"
               if h.fall_alerts else
               f"The current exercise in {plan.plan_name} did not pass {h.consecutive_fails} times in a row")
        return ("EASE", f"{why}, so plans that should suit you better are shown.", s, m,
                {x.plan_id for x in hard})

    completed = [by_id[h.plan_id] for h in p.plans
                 if h.status == "COMPLETED" and h.plan_id in by_id and same_area(h.plan_id)]
    if completed:
        top = max(completed, key=lambda x: (STAGES.index(x.recovery_stage), MOBILITY.index(x.mobility_level),
                                            x.plan_name))
        s = max(stage, min(len(STAGES) - 1, STAGES.index(top.recovery_stage) + 1))
        m = max(mob, min(len(MOBILITY) - 1, MOBILITY.index(top.mobility_level) + 1))
        why = (f"You completed {top.plan_name}, so plans for the next stage are included."
               if (s, m) != (stage, mob) else
               f"You completed {top.plan_name}, so plans with new exercises come first.")
        return "PROGRESS", why, s, m, {x.plan_id for x in completed}

    return "STAY", "Your results so far are used to put the plans that suit you first.", stage, mob, set()


# ---- diversity re-rank ----------------------------------------------------------------------

def plan_similarity(a: PlanIn, b: PlanIn, focus: bool = False) -> float:
    """Content similarity between two plans, same blocks and weights as the patient score (the
    focus block too when the request has focus parts)."""
    blocks = {
        "body_area": cosine(_PARTS[a.target_body_area], _PARTS[b.target_body_area]),
        "goal": cosine(_goal_vec(a.goal), _goal_vec(b.goal)),
        "recovery_stage": cosine(_ORDINAL[STAGES.index(a.recovery_stage)], _ORDINAL[STAGES.index(b.recovery_stage)]),
        "mobility_level": cosine(_ORDINAL[MOBILITY.index(a.mobility_level)],
                                 _ORDINAL[MOBILITY.index(b.mobility_level)]),
    }
    total = sum(WEIGHTS[k] * v for k, v in blocks.items())
    if not focus:
        return total / sum(WEIGHTS.values())
    parts = cosine(plan_parts(a), plan_parts(b))
    return (total + FOCUS_WEIGHT * parts) / (sum(WEIGHTS.values()) + FOCUS_WEIGHT)


def redundancy(a: PlanIn, b: PlanIn, focus: bool = False) -> float:
    """0 up to DUPLICATE_SIM, rising to 1 for an identical plan."""
    return max(0.0, (plan_similarity(a, b, focus) - DUPLICATE_SIM) / (1 - DUPLICATE_SIM))


def diversify(scored: list[tuple[float, PlanIn]], k: int = TOP_N,
              lam: float = MMR_LAMBDA, focus: bool = False) -> list[tuple[float, PlanIn]]:
    """Greedy MMR over plans that already passed the rules, best first. Only re-orders the
    candidates it is given, so an excluded plan can never come back."""
    remaining, picked = list(scored), []
    while remaining and len(picked) < k:
        def mmr(item):
            return lam * item[0] - (1 - lam) * max((redundancy(item[1], p, focus) for _, p in picked),
                                                   default=0.0)
        best = max(range(len(remaining)), key=lambda i: (mmr(remaining[i]), -i))   # ties keep score order
        picked.append(remaining.pop(best))
    return picked


def recommend(req: RecommendRequest, lam: float = MMR_LAMBDA) -> RecommendResponse:
    step, why, s, m, left_out = next_step(req)
    asked = (STAGES.index(req.rehab.recovery_stage), MOBILITY.index(req.rehab.mobility_level))
    # The rules and the content score use the stage and mobility after the next step.
    req = req.model_copy(update={"rehab": req.rehab.model_copy(
        update={"recovery_stage": STAGES[s], "mobility_level": MOBILITY[m]})})
    exercises = catalogue_exercises(req)
    scored, excluded, details = [], [], {}
    for plan in req.plans:
        reasons = exclusion_reasons(req, plan)
        if plan.plan_id in left_out:
            reasons.insert(0, "already completed" if step == "PROGRESS" else "being eased: too hard at the moment")
        if reasons:
            excluded.append(ExcludedPlan(plan_id=plan.plan_id, reasons=reasons))
            continue
        b = score(req, plan)
        content = weighted(b)
        cf, n = collaborative(req, plan.plan_id)
        base, alpha = blend(content, cf, n)
        pers, ev = personal(req, plan, step, exercises)
        final, beta = blend_personal(base, pers, ev)
        b.collaborative = cf
        b.personal = pers
        details[plan.plan_id] = (b, content, alpha, n, beta)
        scored.append((final, plan))

    # Highest score first; plan name breaks ties so the same input always gives the same order.
    scored.sort(key=lambda t: (-t[0], t[1].plan_name))
    top = []
    for final, plan in diversify(scored, TOP_N, lam, focus=bool(req.focus_parts)):
        b, content, alpha, n, beta = details[plan.plan_id]
        rounded = ScoreBreakdown(**{k: (None if v is None else round(v, 3)) for k, v in b.model_dump().items()})
        top.append(RankedPlan(plan_id=plan.plan_id, suitability_score=round(min(1.0, max(0.0, final)), 3),
                              breakdown=rounded,
                              content_score=round(content, 3), alpha=round(alpha, 3), evidence_patients=round(n),
                              beta=round(beta, 3)))
    status = "NONE" if not top else "ONLY_ONE" if len(top) == 1 else "OK"
    if step == "PROGRESS" and (s, m) != asked:
        by_id = {plan.plan_id: plan for plan in req.plans}
        raised = [r for r in top if STAGES.index(by_id[r.plan_id].recovery_stage) > asked[0]
                  or MOBILITY.index(by_id[r.plan_id].mobility_level) > asked[1]]
        if not raised:
            name = why.removeprefix("You completed ").split(", so")[0]
            why = (f"You completed {name}. Plans for the next stage are not within your safety limits yet, "
                   "so plans at your current stage with new exercises are shown.")
    return RecommendResponse(status=status, ranked=top, excluded=excluded,
                             suitable_count=len(scored), model_version=MODEL_VERSION,
                             next_step=step, next_step_reason=why,
                             effective_stage=STAGES[s], effective_mobility=MOBILITY[m])
