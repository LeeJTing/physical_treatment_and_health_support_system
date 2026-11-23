# Health insights and meal simulation

Implemented all five selected extensions on 24 November 2026. Open **Health insights**
from Diet or Health Report; Treatment also opens its Recovery tab. In the meal review,
choose **What if I change this meal?** before saving.

| Feature | Behaviour | Evidence |
| --- | --- | --- |
| A Timeline | Local-day lanes for planned food, logged meals, readings, exercise and symptom check-ins; selection line, record details, nearby readings, filters and horizontal zoom. Suggested plan times and diary noon markers are explicitly display positions. | [Timeline](evidence/timeline.png) |
| B Meal simulator | Isolated food/portion proposal, six nutrient changes, suitability warnings and daily totals counted once. Suitable catalogue search, duplicate merging, reset and explicit return to the unsaved meal draft. | [Simulator](evidence/meal-simulator.png) |
| C Weekly report | Saved-plan matching, previous-period comparison, recorded-day nutrition, exercise activity and health changes with supporting dates. Daily mean comparisons avoid overweighting dense watch bursts and keep glucose contexts separate. Offline PDF with the same facts and energy diagram. | [Weekly screen](evidence/weekly-report.png), [PDF fixture](evidence/weekly-report-fixture.pdf) |
| D Data quality | Current saved sync time, import counts/time groups, per-metric coverage, unrecorded days, latest reading, source counts and forecast minimum information. Presentation-data switch affects the new insights and PDF without deleting records. | [Data quality](evidence/data-quality.png) |
| E Recovery | Daily pain and stiffness 0–10 and difficulty 1–5, optional notes, plan/date selection, edit/delete, symptom changes and separate posture charts per exercise. Increased symptoms are highlighted; diary saves never advance a treatment plan. | [Recovery](evidence/recovery.png), [Check-in](evidence/recovery-check-in.png) |

These screenshots are **host-rendered Flutter widget captures with synthetic fixture
data**, not Android screenshots or real patient evidence. No phone was connected.

## Verification

- Full regression suite: **703 tests passed**, with `AI_SERVER_ROOT` pointing to the
  separate server checkout. The first full run lacked this environment setting;
  three source-contract checks failed, then passed in the complete configured rerun.
- New coverage: seven calculation/ViewModel checks, two repository transport/error
  checks and four shared UI journeys, including a 320×640 viewport with 1.3 text scale.
- Dialog lifecycle testing found premature controller disposal; forms now own their
  text state through `TextFormField`. Zoom and supporting-record navigation passed.
- PDF bytes were generated offline by the production report service, rendered with
  Poppler and visually checked. Native print-dialog acceptance remains unverified.
- Debug Android APK built successfully. No app was installed or uninstalled.
- Recovery schema, authenticated ownership policies, numeric/date constraints and
  indexes were applied. Rollback-only database tests confirmed owner access,
  cross-account read/insert denial and invalid-pain rejection, leaving no test rows.
- Supabase advisors identified the new plan foreign-key index; it was added. Existing
  `patient_plan_active_cap` search-path and leaked-password-protection notices remain
  outside this change. The new table has RLS, explicit authenticated grants and an
  invoker trigger with a fixed empty search path.
- The architecture checker has 22 pre-existing findings; no new feature files are
  implicated. Existing integration files retain their original formatting.

```powershell
$env:AI_SERVER_ROOT='C:/Users/User/Documents/GitHub/fyp-fastapi/ai_server'
flutter analyze --no-pub
flutter test --no-pub
flutter test test/health_insights_widget_test.dart --no-pub --dart-define=CAPTURE_INSIGHTS_EVIDENCE=true
```

For an authorized Android device, the prepared runner retains both the isolated APK
manifest check and `--no-uninstall`:

```powershell
powershell -ExecutionPolicy Bypass -File tool/run_jt_e2e.ps1 -DeviceId <adb-id> -FeatureSet HealthInsights -Suite Both
```

`integration_test/health_insights_test.dart` shares the four UI journeys with host
tests; the narrow-screen check is host-only. Maestro flow 15 covers timeline entry,
weekly summary, data quality and a recovery save in the disposable fixture. These
native journeys are **prepared, not executed** this session. Numeric meal quantities
do not depend on a Chinese/English keyboard setting; future native login/search tests
must still use English as previously agreed.

## Storage and interpretation

`recovery_check_in` is account-owned and unique by account, treatment assignment and
local date. RLS also checks that the assignment belongs to the authenticated user
and that the check-in is not before its selection date. Dates after today in
Asia/Kuala_Lumpur are rejected. The database supplies update times. The client treats
profile/read/history failures explicitly and guards delayed responses across account
changes, including PDF preparation.

Missing meals and readings remain unknown. Adherence uses the existing comparison
service and its applicable-plan precedence. Health changes are descriptive, with
coverage stated; no causal diet/exercise effect, diagnosis or clinical recovery score
is inferred. Symptoms remain separate from measured posture results. No new external
AI upload, API key or AI server change is needed for these features.

The presentation switch only changes these insights and their PDF. Existing Health
Report forecasts keep their own input history. Demo records are identified by the
presentation model/source tags, and recovery check-ins have an explicit `is_demo`
field. Ordinary user check-ins default to real self-reports. No synthetic symptom
scores were added to the user's live account as part of this implementation.

Implementation references: [Supabase RLS](https://supabase.com/docs/guides/database/postgres/row-level-security),
[PDF package](https://pub.dev/packages/pdf/versions/3.11.3),
[printing package](https://pub.dev/packages/printing/versions/5.14.2),
[NHS physiotherapy symptom guidance](https://www.nhft.nhs.uk/physiotherapy/).
PDF versions are pinned for compatibility with the app's current notification dependencies.
