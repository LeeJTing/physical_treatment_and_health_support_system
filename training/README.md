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

**Angle-rule exercises (no trained model, 6 clips each to tune and test the rules):**
`elbow_flexion`, `wall_push_up`, `heel_raise`, `mini_squat`, `seated_marching`, `glute_bridge`,
`tandem_stance` (hold, scored on time steady), `bird_dog`, `step_up`, `march_in_place`.
Shoulder Pendulum and Pelvic Tilt were removed from the catalogue (a camera cannot judge them);
Bird Dog replaced Pelvic Tilt. Recording instructions: `fyp-notes/Recording_Guide.pdf`.

Planned files:

- `extract_landmarks.py` — video → per-frame landmarks → joint angles (`.npz`)
- `train.py` — small GRU / 1D-CNN per exercise (correct / incorrect + error type)
- `evaluate.py` — accuracy and confusion matrix for Chapter 5

Data: `training/data/<pose_key>/{correct,incorrect}/*.mp4` (git-ignored).
