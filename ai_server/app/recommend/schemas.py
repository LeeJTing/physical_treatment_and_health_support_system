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
    plan_exercise: list[PlanExerciseIn] = Field(min_length=1)


class RecommendRequest(_In):
    rehab: RehabInfo
    safety_limit: SafetyLimitIn
    # PhysicalLimitation.limitationCode values, e.g. LEFT_ARM_MOBILITY, BALANCE_IMPAIRMENT.
    limitations: list[str] = []
    plans: list[PlanIn] = Field(min_length=1)


class ScoreBreakdown(BaseModel):
    body_area: float
    goal: float
    recovery_stage: float
    mobility_level: float


class RankedPlan(BaseModel):
    plan_id: str
    suitability_score: float
    breakdown: ScoreBreakdown


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
