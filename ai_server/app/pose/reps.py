"""Repetition detection on one signal that rises during the movement.

A repetition starts when the signal leaves the rest zone (<= rest), is
confirmed when it passes `active`, and ends when it returns to the rest
zone. The gap between `rest` and `active` (hysteresis) stops jitter from
being counted as extra repetitions.
"""
from dataclasses import dataclass

import numpy as np


@dataclass
class Rep:
    start: int
    peak: int
    end: int
    side: str = ""

    def slice(self) -> slice:
        return slice(self.start, self.end + 1)


def find_reps(signal: np.ndarray, t: np.ndarray, rest: float, active: float,
              min_duration: float = 0.4, side: str = "") -> list[Rep]:
    reps: list[Rep] = []
    n = len(signal)
    i = 0
    last_rest = 0
    seen_rest = False
    while i < n:
        if signal[i] <= rest:
            last_rest = i
            seen_rest = True
            i += 1
            continue
        if signal[i] >= active:
            j = i
            while j < n and signal[j] > rest:
                j += 1
            if not seen_rest:
                # Already past the start level before any start position was seen (8 Oct: a person
                # standing still, scored as sit-to-stand, counted as one repetition and passed).
                i = j
                continue
            end = min(j, n - 1)
            seg = signal[last_rest:end + 1]
            peak = last_rest + int(np.argmax(seg))
            if t[end] - t[last_rest] >= min_duration:
                reps.append(Rep(start=last_rest, peak=peak, end=end, side=side))
            last_rest = end
            i = j + 1
            continue
        i += 1
    return reps


def merge_sides(*per_side: list[Rep]) -> list[Rep]:
    """Alternating exercises (marching, bird dog): each side's lifts are reps."""
    return sorted((r for reps in per_side for r in reps), key=lambda r: r.start)


def hold_seconds(signal: np.ndarray, t: np.ndarray, rep: Rep, tolerance: float) -> float:
    """How long the signal stays within `tolerance` of its peak during the rep."""
    s = slice(rep.start, rep.end + 1)
    seg, ts = signal[s], t[s]
    near = seg >= seg.max() - tolerance
    if not near.any() or len(ts) < 2:
        return 0.0
    # Longest run of consecutive frames near the peak.
    best = cur = 0.0
    dt = float(np.median(np.diff(ts))) if len(ts) > 1 else 0.0
    for flag in near:
        cur = cur + dt if flag else 0.0
        best = max(best, cur)
    return best


def phase_seconds(t: np.ndarray, rep: Rep) -> tuple[float, float]:
    """(time going up to the peak, time coming back down)."""
    return float(t[rep.peak] - t[rep.start]), float(t[rep.end] - t[rep.peak])
