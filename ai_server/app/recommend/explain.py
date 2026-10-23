"""Why a plan is shown or not, in the patient's words, with the sources behind each rule (11 Oct).

Every reason has a code, a sentence for the patient and the keys of its sources. The app holds the
full reference for each key (lib/core/constants/evidence_sources.dart). A rule that is our own design
choice, with no paper behind its number, has no source: the app labels it "App safety rule".
Sources: fyp-notes/Evidence_Plan_Tailoring.docx and Draft_Age_Explanations_Terms.docx.
"""
from . import conditions as C
from .schemas import PlanIn, Reason, RecommendRequest

# Plans are not generated from this age (Terms of Use, section 2): the programmes proven for older
# adults were set up and followed by health professionals, and this app has none.
PLAN_AGE_LIMIT = 65
AGE_SOURCES = ["otago2003", "vivifrail2019", "lacroix2017", "who2020", "acsm2009"]

# Every source key the server may send; the app's list (lib/core/constants/evidence_sources.dart) must
# hold each one (tests/test_recommend.py checks).
SOURCE_KEYS = {"acsm2009", "billinger2014", "colberg2016", "haff2016", "hk_doh", "icfsr2021", "lacroix2017",
               "martinez_velilla2019", "mehta2024", "otago2003", "sherrington2019", "vivifrail2019", "who2020",
               "williams2007",
               # 11 Oct: the conditions added to the profile (conditions.py)
               "acog2020", "campbell2019", "eular2018", "gina2024", "kalb2020", "kdigo2024", "nice2020",
               "osborne2022", "spruit2013",
               # 14 Oct: osteoporosis
               "brookewavell2022"}

AREA = {"LEFT_ARM": "left arm", "RIGHT_ARM": "right arm", "BOTH_ARMS": "arms", "LEFT_LEG": "left leg",
        "RIGHT_LEG": "right leg", "BOTH_LEGS": "legs", "CORE": "core and back", "FULL_BODY": "whole body"}
GOAL = {"STRENGTH": "strength", "MOBILITY": "mobility", "BALANCE": "balance", "PAIN_RELIEF": "pain relief",
        "ENDURANCE": "endurance"}
EFFORT = {"LOW": "light", "MODERATE": "moderate", "VIGOROUS": "vigorous"}
STAGE = {"EARLY": "early", "INTERMEDIATE": "intermediate", "ADVANCED": "advanced"}


def intensity_sources(conditions: list[str]) -> list[str]:
    """Condition-specific guidance first, the general older-adult position stand otherwise."""
    keys = list(dict.fromkeys(C.CONDITION_SOURCES[c] for c in conditions if c in C.CONDITION_SOURCES))
    return keys or ["acsm2009"]


def _names(exercises) -> str:
    names = [e.exercise_name or e.exercise_id for e in exercises]
    return names[0] if len(names) == 1 else ", ".join(names[:-1]) + " and " + names[-1]


def _verb(exercises, one: str, many: str) -> str:
    return one if len(exercises) == 1 else many


def age_limit(age: int) -> Reason:
    return Reason(code="AGE_LIMIT",
                  text=f"Exercise plans are for users under {PLAN_AGE_LIMIT} (you are {age}). The programmes proven "
                       "for older adults are set up and followed by a health professional, and this app has none, as "
                       "stated in our Terms of Use (section 2).",
                  sources=AGE_SOURCES)


def why_excluded(req: RecommendRequest, plan: PlanIn, reasons: list[str]) -> list[Reason]:
    """One patient reason per technical reason (in the same order), for the "Why not" list."""
    from .engine import INTENSITY, blocked_area, conflicts, exercise_trains     # avoid an import cycle

    out = []
    exercises = [pe.exercise for pe in plan.plan_exercise]
    for r in reasons:
        if r.startswith("intensity above"):
            cap = INTENSITY.index(req.safety_limit.max_exercise_intensity)
            hard = [e for e in exercises if INTENSITY.index(e.intensity_level) > cap]
            out.append(Reason(code="TOO_INTENSE",
                              text=f"It includes {_names(hard)}, which {_verb(hard, 'is', 'are')} harder than your "
                                   f"profile allows "
                                   f"({EFFORT[req.safety_limit.max_exercise_intensity]} effort).",
                              sources=intensity_sources(req.conditions)))
        elif r.startswith("session "):
            out.append(Reason(code="TOO_LONG",
                              text=f"One of its exercises takes longer than your daily limit of "
                                   f"{req.safety_limit.max_session_duration_min} minutes.",
                              sources=["otago2003", "martinez_velilla2019"]))
        elif r.startswith("conflicts with "):
            code = r.removeprefix("conflicts with ").split(":")[0]
            limb = AREA.get(blocked_area(code) or "", "limb")
            used = [e for e in exercises if conflicts(e.target_body_area, blocked_area(code) or "")
                    and not exercise_trains(e, req.rehab.affected_body_area)]
            subject = f"{_names(used)} {_verb(used, 'uses', 'use')}" if used else "It uses"
            out.append(Reason(code="LIMB_OTHER",
                              text=f"{subject} your {limb}, which your profile lists as limited.", sources=[]))
        elif ": the limited limb gets" in r:
            code = r.split(":")[0]
            limb = AREA.get(blocked_area(code) or "", "limb")
            out.append(Reason(code="LIMB_GENTLE",
                              text=f"Your {limb} is limited, so only gentle early-stage plans are offered for it.",
                              sources=["vivifrail2019", "mehta2024"]))
        elif r.startswith("avoided with "):
            code = r.removeprefix("avoided with ").split(":")[0]
            card = C.AVOID_POSITIONS.get(code, {})
            hit = [e for e in exercises if C.avoided([code], e.body_position)]
            how = card.get("why", "in a position your health profile rules out")
            out.append(Reason(code="CONDITION_AVOID", text=f"It includes {_names(hit)}, done {how}.",
                              sources=card.get("sources", [])))
        elif r.startswith("plan is for"):
            out.append(Reason(code="LATER_STAGE",
                              text=f"It is for the {STAGE[plan.recovery_stage]} stage of recovery, later than yours.",
                              sources=["icfsr2021"]))
        elif r.startswith("plan needs"):
            out.append(Reason(code="HIGHER_MOBILITY", text="It needs more mobility than you have now.",
                              sources=["icfsr2021"]))
        elif r.startswith("none of its exercises trains"):
            out.append(Reason(code="NOT_AREA",
                              text=f"None of its exercises trains your {AREA[req.rehab.affected_body_area]}.",
                              sources=[]))
        elif r == "already completed":
            out.append(Reason(code="DONE", text="You have already completed it.", sources=[]))
        elif r.startswith("being eased"):
            out.append(Reason(code="EASED", text="It is the plan that was too hard at the moment.", sources=[]))
        elif r.startswith("contains "):
            name = r.removeprefix("contains ").split(" at the same")[0]
            out.append(Reason(code="FAILED_EXERCISE",
                              text=f"It has {name} at the same or a higher dose, which did not pass several times.",
                              sources=[]))
        elif r.startswith("weaker match"):
            out.append(Reason(code="WEAK_MATCH", text="Other plans match your answers much better.", sources=[]))
        elif r.startswith("age "):
            out.append(age_limit(req.age or PLAN_AGE_LIMIT))
        else:
            out.append(Reason(code="OTHER", text=r, sources=[]))
    return out


def why_shown(req: RecommendRequest, plan: PlanIn, step: str, personal: float | None,
              easier: list[str], raised: bool) -> list[Reason]:
    """Up to four reasons for the "Why this plan" section, most specific first."""
    from .engine import exercise_trains, plan_area_vec, cosine, _PARTS, conflicts, blocked_area

    out = []
    if step == "PROGRESS" and raised:
        out.append(Reason(code="NEXT_STAGE", text="You completed your last plan, so this one is one step harder.",
                          sources=["otago2003", "haff2016"]))
    if step == "EASE":
        out.append(Reason(code="EASIER", text="Your last exercise did not pass several times, so this plan is gentler.",
                          sources=["billinger2014"]))
        for name in easier:
            out.append(Reason(code="EASIER_DOSE", text=f"{name} is still here, with fewer repetitions or less time.",
                              sources=["otago2003"]))
    area = req.rehab.affected_body_area
    share = cosine(_PARTS[area], plan_area_vec(plan))
    out.append(Reason(code="MATCH_AREA",
                      text=f"It trains your {AREA[area]}" + (" and the goal you chose" if plan.goal == req.rehab.goal
                                                             else "") + ".",
                      sources=[]))
    if plan.goal in ("STRENGTH", "ENDURANCE"):
        f = plan.frequency_per_week
        out.append(Reason(code="DOSE_STRENGTH",
                          text=(f"{f} days a week, " if f else "") + "with rest days between strength sessions, as "
                               "recommended for rebuilding muscle.", sources=["icfsr2021", "acsm2009"]))
    elif plan.goal == "BALANCE":
        out.append(Reason(code="DOSE_BALANCE", text="Balance practice on several days a week reduces falls.",
                          sources=["sherrington2019", "acsm2009"]))
    else:
        out.append(Reason(code="DOSE_MOBILITY", text="Gentle movement on most days helps recover range of motion.",
                          sources=["acsm2009", "mehta2024"]))
    # One exercise of the plan a day: the day's session is at most its longest exercise.
    minutes = max(1, round(max((pe.prescribed_duration_sec for pe in plan.plan_exercise), default=0) / 60))
    out.append(Reason(code="SAFE",
                      text=f"Every exercise stays within your effort limit "
                           f"({EFFORT[req.safety_limit.max_exercise_intensity]}), and each day's exercise takes up to about "
                           f"{minutes} minutes (your limit: {req.safety_limit.max_session_duration_min}).",
                      sources=intensity_sources(req.conditions) + ["otago2003"]))
    for code in req.limitations:
        b = blocked_area(code)
        if b and any(conflicts(pe.exercise.target_body_area, b) and exercise_trains(pe.exercise, area)
                     for pe in plan.plan_exercise):
            out.append(Reason(code="LIMB_GENTLE",
                              text=f"Your {AREA.get(b, 'limb')} is limited, so this plan keeps it gentle.",
                              sources=["vivifrail2019", "mehta2024"]))
            break
    if personal is not None and personal > 0.55 and share > 0:
        out.append(Reason(code="PERSONAL", text="You did well on similar exercises.", sources=[]))
    return out[:4] if step not in ("EASE", "PROGRESS") else out[:5]
