"""Posture analysis for one clip (FR300_07 to FR300_10, FR300_17, FR300_19).

landmarks -> visibility check -> joint angles -> repetitions -> rule checks
(+ the trained classifier when its weights exist) -> accuracy and feedback.
"""
from collections import Counter

import numpy as np

from . import classifier
from .exercises import ExerciseSpec, get
from .geometry import Features
from .landmarks import PoseSequence
from .reps import Rep, find_reps, merge_sides

RULES_VERSION = "rules-1.0"
MISTAKE_PENALTY = 30          # points off a repetition per mistake found
MIN_DETECTED = 0.5            # share of frames with a person found
MIN_VISIBLE = 0.8             # share of frames with every required body part in the picture
GOOD_FORM = "Good form. Keep it up!"


class PoseError(Exception):
    """code: pose_not_detected | full_body_not_visible | no_repetitions"""

    def __init__(self, code: str, message: str):
        super().__init__(message)
        self.code = code
        self.message = message


def detect_reps(spec: ExerciseSpec, f: Features) -> list[Rep]:
    if spec.side_signals is not None:
        sig = spec.side_signals(f)
        return merge_sides(*(find_reps(s, f.t, spec.rest, spec.active, side=k) for k, s in sig.items()))
    return find_reps(spec.signal(f), f.t, spec.rest, spec.active)


def check_rep(spec: ExerciseSpec, f: Features, rep: Rep) -> list[str]:
    found = []
    for m in spec.mistakes:
        try:
            if m.check(f, rep):
                found.append(m.label)
        except (KeyError, IndexError, ValueError):
            continue
    return found


def longest_true_seconds(mask: np.ndarray, t: np.ndarray) -> float:
    if len(t) < 2:
        return 0.0
    dt = float(np.median(np.diff(t)))
    best = cur = 0.0
    for flag in mask:
        cur = cur + dt if flag else 0.0
        best = max(best, cur)
    return best


def analyse(pose_key: str, seq: PoseSequence, use_model: bool = True) -> dict:
    spec = get(pose_key)
    if seq.detected_ratio < MIN_DETECTED:
        raise PoseError("pose_not_detected", "No body posture was detected in the video.")
    f = Features(seq)
    visible = f.visible(spec.required, either_side=spec.view == "side")
    visible_ratio = float(np.mean(visible)) if len(visible) else 0.0
    if visible_ratio < MIN_VISIBLE:
        raise PoseError("full_body_not_visible", "The whole body was not visible for most of the video.")

    rep_details, all_mistakes = [], Counter()
    hold = None
    method = RULES_VERSION

    if spec.kind == "hold":
        whole = Rep(start=0, peak=len(f.t) // 2, end=len(f.t) - 1)
        mistakes = check_rep(spec, f, whole)
        hold = longest_true_seconds((f["feet_gap"] < 0.6) & visible, f.t)
        score = max(0.0, min(1.0, hold / spec.hold_target_sec) * 100 - MISTAKE_PENALTY * len(mistakes))
        all_mistakes.update(mistakes)
        rep_details.append({"start_sec": float(f.t[0]), "end_sec": float(f.t[-1]), "score": round(score, 1),
                            "mistakes": mistakes})
        reps: list[Rep] = []
    else:
        reps = detect_reps(spec, f)
        if not reps:
            raise PoseError("no_repetitions", "No complete repetition was found in the video.")
        model = classifier.predict(pose_key, f, reps) if use_model else None
        if model:
            method = f"{RULES_VERSION}+{model['version']}"
        for i, rep in enumerate(reps):
            mistakes = check_rep(spec, f, rep)
            score = max(0.0, 100.0 - MISTAKE_PENALTY * len(mistakes))
            detail = {"start_sec": round(float(f.t[rep.start]), 2), "end_sec": round(float(f.t[rep.end]), 2),
                      "side": rep.side or None, "rule_score": score, "mistakes": mistakes}
            if model:
                p = float(model["p_correct"][i])
                detail["p_correct"] = round(p, 3)
                if p < 0.5 and not mistakes and model["likely_mistake"][i]:
                    mistakes = [model["likely_mistake"][i]]
                    detail["mistakes"] = mistakes
                score = 0.5 * score + 0.5 * 100 * p
            detail["score"] = round(score, 1)
            all_mistakes.update(mistakes)
            rep_details.append(detail)

    accuracy = round(float(np.mean([d["score"] for d in rep_details])), 1)
    texts = {m.label: m.feedback for m in spec.mistakes}
    feedback = [texts[label] for label, _ in all_mistakes.most_common() if label in texts] or [GOOD_FORM]
    return {
        "exercise_key": pose_key,
        "accuracy": accuracy,
        "repetitions": len(reps),
        "hold_seconds": round(hold, 1) if hold is not None else None,
        "feedback": feedback,
        "mistakes": dict(all_mistakes),
        "full_body_visible": True,
        "visible_ratio": round(visible_ratio, 3),
        "rep_details": rep_details,
        "model_version": method,
    }
