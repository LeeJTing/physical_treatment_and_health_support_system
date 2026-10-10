"""Request and response bodies for /recommend.

The request carries everything the recommender needs, because the server
never reads Supabase: the questionnaire answers (RehabInfo.toJson), the
patient's current safety limit and physical limitations, and the plan
catalogue exactly as TreatmentPlan.toJson() writes it.
"""
from typing import Literal

from pydantic import BaseModel, ConfigDict, Field

BodyArea = Literal["LEFT_ARM", "RIGHT_ARM", "BOTH_ARMS", "LEFT_LEG", "RIGHT_LEG", "BOTH_LEGS", "CORE", "FULL_BODY"]
Stage = Literal["EARLY", "INTERMEDIATE", "ADVANCED"]
Mobility = Literal["LOW", "MODERATE", "HIGH"]
Goal = Literal["STRENGTH", "MOBILITY", "BALANCE", "PAIN_RELIEF", "ENDURANCE"]
Intensity = Literal["LOW", "MODERATE", "VIGOROUS"]
# Finer body parts from the body map (BodyRegions.focusParts in the app).
# Optional pace from the questionnaire: about 3, 4 or 5 exercise days a week.
Pace = Literal["SLOW", "MEDIUM", "FAST"]
FocusPart = Literal["shoulder", "elbow", "wrist_hand", "hip", "knee", "ankle_foot", "back"]


class _In(BaseModel):
    model_config = ConfigDict(extra="ignore")


class RehabInfo(_In):
    affected_body_area: BodyArea
    recovery_stage: Stage
    mobility_level: Mobility
    goal: Goal


class SafetyLimitIn(_In):
    max_exercise_intensity: Intensity
    max_session_duration_min: int = Field(gt=0)


class ExerciseIn(_In):
    exercise_id: str
    exercise_name: str = ""
    target_body_area: BodyArea
    intensity_level: Intensity
    # Posture model key; tells which body parts the exercise trains (engine.POSE_PARTS).
    pose_key: str | None = None


class PlanExerciseIn(_In):
    exercise: ExerciseIn
    prescribed_duration_sec: int = Field(ge=0)


class PlanIn(_In):
    plan_id: str
    plan_name: str = ""
    target_body_area: BodyArea
    recovery_stage: Stage
    mobility_level: Mobility
    goal: Goal | None = None
    # Sessions a week (treatment_plan.frequency_per_week); used by the pace block.
    frequency_per_week: int | None = Field(default=None, ge=1, le=7)
    plan_exercise: list[PlanExerciseIn] = Field(min_length=1)


RiskLevel = Literal["Low", "Medium", "High"]          # health_profile.risk_level
AgeBand = Literal["<60", "60-74", "75+"]


class CohortIn(_In):
    """The patient's own cohort features, compared with the outcome cells."""
    risk_level: RiskLevel
    age_band: AgeBand


class PlanOutcomeIn(_In):
    """One anonymised cohort cell from the plan_outcome_stats() RPC: how patients with this risk
    level and age band did on a plan. Never contains account ids; cells under MIN_PATIENTS are
    dropped by the RPC and again by the engine."""
    plan_id: str
    risk_level: RiskLevel
    age_band: AgeBand
    patients: int = Field(ge=0)
    completion_rate: float = Field(ge=0, le=1)
    mean_accuracy: float | None = Field(default=None, ge=0, le=100)
    mean_progress: float | None = Field(default=None, ge=0, le=100)


PlanStatusIn = Literal["ACTIVE", "COMPLETED", "ABANDONED"]           # patient_plan.status


class PlanHistoryIn(_In):
    """One of the patient's own plans (patient_plan), for the next step (hybrid-3.0)."""
    plan_id: str
    status: PlanStatusIn
    progress_percentage: float = Field(default=0, ge=0, le=100)
    # Attempts in a row at the plan's current exercise that did not pass (below 80 %).
    consecutive_fails: int = Field(default=0, ge=0)
    # Recent attempts on the plan with a possible-fall alert.
    fall_alerts: int = Field(default=0, ge=0)


class ExerciseResultIn(_In):
    """The patient's own results on one exercise, over every plan (exercise_session)."""
    exercise_id: str
    attempts: int = Field(ge=1)
    passes: int = Field(ge=0)
    mean_accuracy: float | None = Field(default=None, ge=0, le=100)


class ProgressIn(_In):
    """What the patient has done so far. Built by the app from patient_plan and exercise_session;
    no schema change and no other patient's data."""
    plans: list[PlanHistoryIn] = []
    exercises: list[ExerciseResultIn] = []


class RecommendRequest(_In):
    rehab: RehabInfo
    safety_limit: SafetyLimitIn
    # PhysicalLimitation.limitationCode values, e.g. LEFT_ARM_MOBILITY, BALANCE_IMPAIRMENT.
    limitations: list[str] = []
    plans: list[PlanIn] = Field(min_length=1)
    # Collaborative evidence (hybrid-2.0). Both optional: without them the result equals the
    # content + rules ranking (cold start).
    cohort: CohortIn | None = None
    plan_outcomes: list[PlanOutcomeIn] = []
    # Body parts the patient tapped on the body map. Optional: empty means no focus block, and the
    # result equals hybrid-2.0.
    focus_parts: list[FocusPart] = []
    # How fast the patient wants to go (optional question). None: no pace block.
    pace: Pace | None = None
    # The patient's own history (hybrid-3.0). None or empty: no personal score and no next step,
    # so the result equals hybrid-2.2.
    progress: ProgressIn | None = None


class ScoreBreakdown(BaseModel):
    body_area: float
    goal: float
    recovery_stage: float
    mobility_level: float
    # Collaborative score after shrinkage, or None when there is no evidence for the plan.
    collaborative: float | None = None
    # Match between the tapped body parts and the parts the plan's exercises train, or None
    # when the request has no focus parts.
    focus: float | None = None
    # Match between the wanted pace and the plan's days a week, or None without a pace.
    pace: float | None = None
    # Predicted success from the patient's own results on similar exercises, or None without
    # history that says anything about the plan's exercises.
    personal: float | None = None


class RankedPlan(BaseModel):
    plan_id: str
    suitability_score: float           # final = (1 - alpha) * content + alpha * collaborative
    breakdown: ScoreBreakdown
    content_score: float = 0.0
    alpha: float = 0.0                 # weight given to the collaborative score (0 at cold start)
    evidence_patients: int = 0         # similarity-weighted number of similar patients behind it
    beta: float = 0.0                  # weight given to the personal score (0 without history)


class ExcludedPlan(BaseModel):
    plan_id: str
    reasons: list[str]


class RecommendResponse(BaseModel):
    # NONE -> FR500_14 message, ONLY_ONE -> FR500_15 message, OK -> two or three plans.
    status: Literal["OK", "ONLY_ONE", "NONE"]
    ranked: list[RankedPlan]
    excluded: list[ExcludedPlan]
    suitable_count: int
    model_version: str
    # What the patient's history says to do next (hybrid-3.0): START without history, PROGRESS
    # after a completed plan, EASE after repeated failed attempts or a possible fall, STAY otherwise.
    next_step: Literal["START", "PROGRESS", "STAY", "EASE"] = "START"
    # One plain sentence for the patient explaining next_step; empty for START.
    next_step_reason: str = ""
    # The recovery stage and mobility level the rules used after the next step.
    effective_stage: Stage | None = None
    effective_mobility: Mobility | None = None
