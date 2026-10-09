# APTHS AI Server API

The AI server of the FYP (report section 4.2, Table 4.2.4). FastAPI, stateless: it never reads or
writes Supabase; the app stores every result. The exact contract (every field and type) is
[`openapi.json`](openapi.json), generated from the code by `export_openapi.py`; a running server
shows the same at `/docs`.

## Endpoints (Table 4.2.4)

| Endpoint | Module | Component | Status |
|---|---|---|---|
| `POST /recommend` | M500.1 (Elwin) | Hybrid Plan Recommender | built (hybrid-2.2) |
| `GET /chat/categories`, `POST /chat` | M500.2 (Elwin) | Rule-Based Chatbot Engine | built (chat-rules-3.48) |
| `GET /pose/exercises`, `POST /pose` | M300.1 (Elwin) | Pose Estimation Model | built |
| `POST /forecast` | M400 (Jun Ting) | Time-Series Forecaster | **to build** |
| `POST /analyse` | M400 (Jun Ting) | Anomaly Detector and Health Scorer | **to build** |
| `POST /recognise` | M700 (Jun Ting) | Food Recognition Model (CV) | **to build** |
| `POST /plan` | M700 (Jun Ting) | Condition-Aware Diet Planner | **to build** |
| `GET /health` | - | up check, no token needed | built |

How to add one: [`../CONTRIBUTING.md`](../CONTRIBUTING.md).

## Every request

- **Token:** `Authorization: Bearer <Supabase access token>` (the signed-in patient's session token;
  `app/auth.py` checks it against the project's signing keys, `SUPABASE_JWKS_URL`). The account id
  is the token's `sub`; the server never sees an email or password. With `DEV_AUTH_BYPASS=true` the
  token `dev-token` is also accepted (fakes, tests, development only).
- **Errors:** missing or invalid token: `401`. A request that does not match the contract: `422`
  with FastAPI's `detail` list. `/pose` reports a video it cannot score as `422`
  `{"error": {"code": "...", "message": "..."}}` (codes below); the app maps each code to the
  report's message.
- **Versions:** answers carry the version of the rules or model that produced them
  (`model_version`, `rules_version`), so a stored result can be traced.

## `POST /recommend` (JSON)

Ranks the catalogue plans for the patient's questionnaire, within the safety limits.

```json
{
  "rehab": {"affected_body_area": "BOTH_LEGS", "recovery_stage": "EARLY",
            "mobility_level": "LOW", "goal": "MOBILITY"},
  "safety_limit": {"max_exercise_intensity": "LOW", "max_session_duration_min": 20},
  "limitations": ["BALANCE_IMPAIRMENT"],
  "plans": [ { "plan_id": "...", "target_body_area": "BOTH_LEGS", "recovery_stage": "EARLY",
               "mobility_level": "LOW", "goal": "MOBILITY", "frequency_per_week": 3,
               "plan_exercise": [ {"prescribed_duration_sec": 60,
                                   "exercise": {"exercise_id": "...", "target_body_area": "BOTH_LEGS",
                                                "intensity_level": "LOW", "pose_key": "knee_extension"}} ] } ],
  "focus_parts": ["knee"],
  "pace": "SLOW"
}
```

`cohort` and `plan_outcomes` (anonymised results of similar patients) are optional; without them
the ranking is content + rules only. Answer: `status` (`OK`, `ONLY_ONE`, `NONE`), `ranked` (best
first: `plan_id`, `suitability_score`, `breakdown` per block), `excluded` (with `reasons`),
`suitable_count`, `model_version`.

## `GET /chat/categories?plan_id=...` and `POST /chat` (JSON)

The question categories for the patient's plan, and the answer to a tapped category or a typed
question (FR500_17 to FR500_23).

```json
{"plan_id": "...", "text": "how do i change my password",
 "conditions": ["HYPERTENSION"], "limitations": [], "risk_level": "Medium",
 "local_hour": 21, "local_minute": 5, "previous_category": null}
```

Send `category` (a key from the categories) or `text`. Answer: `answer`, `category` (null = not
recognised, FR500_22), `is_matched`, `matched_by` (`red_flag`, `crisis`, `keyword`, ...),
`follow_ups`, `notes` (condition-specific safety lines), `categories`, `action` and `actions`
(buttons: `{"key": "open_profile", "label": "Open Profile"}`; the app maps each key to a screen),
`rules_version`. Urgent symptoms and crisis phrases are answered first, whatever else is asked.

## `GET /pose/exercises` and `POST /pose` (multipart)

The exercises that have a posture check, and the check of one recorded clip (FR300_06 to FR300_26).

Form fields: `file` (MP4 or MOV, 10 to 30 s, at most 100 MB, at least 720p), `exercise_key` (the
exercise's `pose_key`), optional `risk_level` (`Low`/`Medium`/`High`) and `age` (gentler targets
for frail patients), optional `upright_turn_deg` (phone tilt).

```
curl -H "Authorization: Bearer dev-token" -F file=@clip.mp4 -F exercise_key=sit_to_stand \
     -F risk_level=Medium -F age=68 http://localhost:8000/pose
```

Answer: `exercise_key`, `accuracy` (0 to 100; 80 or more passes), `repetitions`, `hold_seconds`,
`feedback` (what to correct, patient wording), `mistakes`, `rep_details` (per repetition),
`full_body_visible`, `visible_ratio`, `model_version`, and `safety_alert`
(`{"type": "possible_fall", "at_sec", "message"}`) when the clip looks like a fall.

Error codes (`422 {"error": ...}`): `invalid_video`, `unknown_exercise`, `pose_not_detected`,
`full_body_not_visible`, `hand_not_visible`, `wrong_exercise` (the clip shows another exercise),
`no_repetitions`.

The clip is deleted after the check. Only with `DEV_TOOLS=true` (development machine) is it kept
for the viewer (`devtools/`, `run_devtools.ps1`); never with real patients' videos.
