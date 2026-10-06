"""Turns labelled clips into repetition samples for the classifier.

Sources
  own clips   training/data/<pose_key>/<correct|incorrect>/*.mp4; repetitions are cut by the
              angle rules' rep counter; every rep inherits the clip's label and mistake
  REHAB24-6   training/data/public/rehab24_6 (videos + Segmentation.csv); repetitions and
              correct/incorrect labels come from the dataset (no mistake type)

    ai_server\\.venv\\Scripts\\python training\\build_dataset.py shoulder_abduction [--no-public]

Own clips also contribute their colour/camera variants from augment.py (cached under
training/data/cache/<pose_key>/aug/), when present.

Writes training/data/datasets/<pose_key>.npz with X (N, SEQ_LEN, F), y_correct, y_mistake
(-1 = unknown or correct), groups (person, for a person-wise split), clip (the source video:
a clip and all its variants must stay on the same side of a split), aug (0 = original,
k = variant k; only originals are ever tested on) and source.
"""
import argparse
import csv
from pathlib import Path

import numpy as np

from common import CACHE, DATA, cached_sequence, own_clips
from app.pose import landmarks
from app.pose.analyse import detect_reps
from app.pose.classifier import rep_tensor
from app.pose.exercises import EXERCISES
from app.pose.geometry import Features
from app.pose.reps import Rep

REHAB = DATA / "public" / "rehab24_6"
# REHAB24-6 exercise id -> our pose_key, and the view our exercise needs.
REHAB_MAP = {1: "shoulder_abduction", 4: "hip_abduction", 3: "wall_push_up"}


def own_samples(key: str):
    spec = EXERCISES[key]
    mistakes = [m.label for m in spec.mistakes]
    X, yc, ym, groups, clips, aug, src = [], [], [], [], [], [], []
    for clip in own_clips([key]):
        if not clip.name_ok or clip.problems:
            print(f"  skip {clip.path.name}: {'; '.join(clip.problems) or 'bad name'}")
            continue
        seq = cached_sequence(clip)
        if seq.detected_ratio < 0.5:
            print(f"  skip {clip.path.name}: no person detected")
            continue
        versions = [(0, seq)] + [(int(p.stem.rsplit("__aug", 1)[1]), landmarks.load(p))
                                 for p in sorted((CACHE / key / "aug").glob(f"{clip.path.stem}__aug*.npz"))]
        for k, s in versions:
            if s.detected_ratio < 0.5:
                continue
            f = Features(s)
            for r in detect_reps(spec, f):
                X.append(rep_tensor(f, r))
                yc.append(1 if clip.is_correct else 0)
                ym.append(mistakes.index(clip.mistake) if (not clip.is_correct and clip.mistake in mistakes) else -1)
                groups.append(f"own-{clip.person}")
                clips.append(clip.path.stem)
                aug.append(k)
                src.append(f"{clip.path.name}{f'~aug{k}' if k else ''}#{r.start}")
    return X, yc, ym, groups, clips, aug, src


def find_video(video_id: str, camera: str) -> Path | None:
    for p in (REHAB / "videos").rglob(f"*{video_id}*"):
        if camera in p.name or camera in str(p.parent):
            return p
    return None


def rehab_samples(key: str):
    ids = [i for i, k in REHAB_MAP.items() if k == key]
    seg = REHAB / "Segmentation.csv"
    if not ids or not seg.exists() or not (REHAB / "videos").exists():
        return [], [], [], [], [], [], []
    view = EXERCISES[key].view
    rows = [r for r in csv.DictReader(seg.open(encoding="utf-8"), delimiter=";") if int(r["exercise_id"]) in ids]
    X, yc, ym, groups, clips, aug, src = [], [], [], [], [], [], []
    by_video: dict[tuple[str, str], list[dict]] = {}
    for r in rows:
        o = r["cam17_orientation"]
        if o == "half-profile":
            continue
        # cam18 is orthogonal to cam17: cam17 "front" means cam18 sees the side, and vice versa.
        cam = ("Camera17" if o == "front" else "Camera18") if view == "front" else ("Camera17" if o != "front" else "Camera18")
        by_video.setdefault((r["video_id"], cam), []).append(r)
    for (vid, cam), reps in sorted(by_video.items()):
        video = find_video(vid, cam)
        if video is None:
            print(f"  REHAB24-6 {vid} {cam}: video not found")
            continue
        cache = CACHE / "rehab24_6" / f"{vid}_{cam}.npz"
        if cache.exists():
            seq = landmarks.load(cache)
        else:
            print(f"  extracting {video.name} ...", flush=True)
            seq = landmarks.extract(video)
            cache.parent.mkdir(parents=True, exist_ok=True)
            landmarks.save(seq, cache)
        if seq.detected_ratio < 0.5:
            continue
        f = Features(seq)
        fps = seq.info.fps or 30.0
        for r in reps:
            t0, t1 = int(r["first_frame"]) / fps, int(r["last_frame"]) / fps
            idx = np.where((f.t >= t0) & (f.t <= t1))[0]
            if len(idx) < 4:
                continue
            rep = Rep(start=int(idx[0]), peak=int(idx[len(idx) // 2]), end=int(idx[-1]))
            X.append(rep_tensor(f, rep))
            yc.append(int(r["correctness"]))
            ym.append(-1)
            groups.append(f"rehab-{r['person_id']}")
            clips.append(f"rehab-{vid}-{cam}")
            aug.append(0)
            src.append(f"REHAB24-6/{vid}/{cam}#{r['repetition_number']}")
    return X, yc, ym, groups, clips, aug, src


def build(key: str, public: bool = True) -> Path:
    parts = [own_samples(key)] + ([rehab_samples(key)] if public else [])
    X, yc, ym, groups, clips, aug, src = (sum((list(p[i]) for p in parts), []) for i in range(7))
    out = DATA / "datasets" / f"{key}.npz"
    out.parent.mkdir(parents=True, exist_ok=True)
    if not X:
        print(f"{key}: no samples yet")
        return out
    np.savez_compressed(out, X=np.stack(X), y_correct=np.array(yc), y_mistake=np.array(ym),
                        groups=np.array(groups), clip=np.array(clips), aug=np.array(aug), source=np.array(src),
                        mistakes=np.array([m.label for m in EXERCISES[key].mistakes]))
    n_own = sum(g.startswith("own") for g in groups)
    n_aug = sum(k > 0 for k in aug)
    print(f"{key}: {len(X)} reps ({n_own} own of which {n_aug} augmented, {len(X) - n_own} public), "
          f"{sum(yc)} correct / {len(yc) - sum(yc)} incorrect, {len(set(groups))} people -> {out}")
    return out


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("keys", nargs="*", default=["sit_to_stand", "shoulder_abduction", "shoulder_flexion",
                                                 "hip_abduction", "knee_extension"])
    ap.add_argument("--no-public", action="store_true")
    a = ap.parse_args()
    for k in a.keys:
        build(k, public=not a.no_public)
