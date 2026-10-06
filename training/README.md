# Posture model training (Phase 6, run on the RTX 3050 PC)

Five exercises, each chosen because one large joint moves in one plane that a single
phone camera can see clearly.

| pose_key | Exercise | Camera | Main angle checked |
|---|---|---|---|
| `sit_to_stand` | Sit-to-Stand (chair squat) | side | knee (hip–knee–ankle), hip, trunk lean |
| `shoulder_abduction` | Lateral arm raise | front | shoulder (hip–shoulder–elbow), elbow straight, left/right symmetry |
| `shoulder_flexion` | Front arm raise | side | shoulder (hip–shoulder–elbow), elbow straight, no back arch |
| `hip_abduction` | Standing side leg raise | front | hip (opposite hip–hip–ankle), trunk upright |
| `knee_extension` | Seated knee extension | side | knee (hip–knee–ankle), back upright |

Planned files:

- `extract_landmarks.py` — video → per-frame landmarks → joint angles (`.npz`)
- `train.py` — small GRU / 1D-CNN per exercise (correct / incorrect + error type)
- `evaluate.py` — accuracy and confusion matrix for Chapter 5

Data: `training/data/<pose_key>/{correct,incorrect}/*.mp4` (git-ignored).
