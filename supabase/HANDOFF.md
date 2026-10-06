# Supabase hand-off (for whoever sets up Supabase)

Elwin's code expects the Chapter 4 tables plus these small additions:

| Change | Why |
|---|---|
| `exercise.pose_key VARCHAR(30) NULL` | Tells the AI server which posture model to use for an exercise |
| `treatment_plan.goal VARCHAR(15) NULL` | Input to the recommender similarity (FR500_03/05) |
| `health_profile.version INTEGER NOT NULL DEFAULT 0` | FR100_053 asks for a profile version number; Table 4.82 has no column for it |

Also needed:

1. Seed: run `seed/seed_catalogue.sql` after the tables exist.
2. Auth: email confirmation with a 6-digit OTP (Auth → Email templates use `{{ .Token }}`), Google provider enabled, redirect URL `my.edu.tarumt.apths://login-callback`.
3. JWT: give Elwin the JWT secret (or JWKS URL) for `ai_server/.env`.
4. A Postgres function `complete_exercise_session(...)` so the session insert and the
   progress update run in one transaction (ASR_04). SQL will be supplied in Phase 6.
