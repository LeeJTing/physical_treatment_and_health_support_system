"""Health condition rules for the recommender (11 Oct). One card per condition the profile can hold.

The risk level (and with it the intensity and session-time limits) is worked out in the app from the
conditions and whether each is controlled; the app also holds back plans until a doctor clears a
condition that needs it. Here: which exercise positions a condition rules out, and which guideline
backs the safety reasons for it. Source keys are explained in lib/core/constants/evidence_sources.dart.
"""

# Positions a condition rules out (exercise.body_position).
AVOID_POSITIONS: dict[str, dict] = {
    # ACOG Committee Opinion 804 (2020): lying on the back after 20 weeks can lower blood pressure.
    "PREGNANCY": {"positions": {"SUPINE"}, "why": "lying on your back, which is not advised in pregnancy",
                  "sources": ["acog2020"]},
    # Colberg et al. (2016): with a foot ulcer or open wound, non-weight-bearing activity only.
    "FOOT_ULCER": {"positions": {"STANDING"}, "why": "standing, which puts weight on your feet; with a foot "
                                                     "ulcer, exercise without standing", "sources": ["colberg2016"]},
}

# The guideline behind the safety reasons for each condition (most specific first in the reason).
CONDITION_SOURCES: dict[str, str] = {
    "HEART_DISEASE": "williams2007", "HYPERTENSION": "hk_doh", "STROKE": "billinger2014", "DIABETES": "colberg2016",
    "ASTHMA": "gina2024", "ARTHRITIS": "eular2018", "RHEUMATOID_ARTHRITIS": "eular2018", "COPD": "spruit2013",
    "CANCER": "campbell2019", "KIDNEY_DISEASE": "kdigo2024", "PARKINSONS": "osborne2022",
    "MULTIPLE_SCLEROSIS": "kalb2020", "PREGNANCY": "acog2020", "JOINT_REPLACEMENT": "nice2020",
    "FOOT_ULCER": "colberg2016",
}


def avoided(conditions: list[str], position: str | None) -> list[str]:
    """The patient's conditions that rule out an exercise done in this position."""
    if position is None:
        return []
    return [c for c in conditions if position in AVOID_POSITIONS.get(c, {}).get("positions", set())]
