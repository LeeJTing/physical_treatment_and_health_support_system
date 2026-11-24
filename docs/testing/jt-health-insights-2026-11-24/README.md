# Health insights and meal simulation

## Food guidance and consistent UI follow-up

Diet review → Plan comparison and Health insights → Weekly report now share
daily food guidance and weekly priorities. Each option names the food and meal,
recorded grams, the portion to review and a nutrient reason. Weekly priorities
show affected dates, occurrence counts and the sum across those occurrences.
These totals are not extra weekly allowances. The exported PDF uses the same
guidance objects, including daily coverage and supporting dates.

Examples in the synthetic fixture: five dinners contain 250 g teh tarik with
30 g free sugars each. The report flags replacement against the current 25 g
daily limit and identifies the missing planned 100 g tofu portion, providing
approximately 5 g protein. Restoring tofu is explicitly conditional on replacing
the teh tarik when the logged day is over a limit. It is not extra food on top.
The weekly totals are 1,250 g to review for replacement and 500 g planned tofu
across the five recorded occurrences, rather than a seven-day prescription.

Current restrictions and portion suitability gate increases. Daily energy,
sodium, sugar and applicable protein/saturated-fat/caffeine budgets are checked
together. Kidney-sensitive increases are withheld. Missing or incomplete
profiles withhold personalised amounts. Reference-only/later-created plans
cannot generate restorative adherence advice. Missing logs remain unknown;
partial days prompt completion before increasing intake. No logs or plans are
automatically changed and no clinical deficiency is inferred.

The new insights and simulator reuse the established green headers, white
bordered cards, background, spacing, typography, orange primary actions and
red warning surfaces. Daily cards have independent page-storage identifiers
and Material surfaces so scrolling state and touch feedback work correctly.

Evidence: [weekly food priorities](evidence/weekly-food-priorities.png),
[expanded daily guidance](evidence/daily-food-guidance.png),
[updated PDF](evidence/weekly-report-fixture.pdf). These are synthetic host
captures, not phone or patient evidence. The shared host UI journeys pass,
including 320 × 640 at 1.3 text scale. Seven new guidance calculation tests
pass; final Flutter analysis has no issues. The full suite reports **733 passed
and one existing app/server contract failure**: the current app expects 15
posture exercise mappings while the separate local AI server still supplies
17 (wrist/hand included). Neither catalogue was altered by this change.
The final five-page fixture PDF was rendered and visually reviewed. Each daily
review and weekly priority stays together, and the energy chart retains its
heading and legend. The normal Android debug APK builds successfully. The
architecture check retains 19 existing findings, with no new feature-layer
violations.

The guidance uses existing profile limits and suitability rules. General food
principles were checked against [WHO healthy diet guidance](https://www.who.int/news-room/fact-sheets/detail/healthy-diet).
No external AI provider, API key or meal-data upload is needed.

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

## Report explanations (24 November follow-up)

Health Report now explains its score, each condition risk and each metric forecast
with a **Conclusion**, **Analysis** and **Suggested next step**. The weekly report
uses the same structure for its overview, saved-plan comparison, nutrition,
exercise and reading changes. Data quality and each recovery plan also provide
record-based interpretations. The exported PDF shares the weekly explanation
service, keeps each explanation with its supporting dates, and reserves footer
spacing. The earlier explanation-only sample PDF had four pages; the current
fixture also includes the daily and weekly food guidance above.

Explanations are generated locally from existing calculations, through the
ViewModels for screens. They require no online AI provider or new upload. Missing
data never becomes evidence of adherence or normal health; forecast direction
is not labelled improvement; recovery includes difficulty as well as pain and
stiffness and gives recent symptom increases precedence over longer-term change.
Presentation data remains explicitly labelled.

Earlier explanation follow-up verification: **32 focused tests passed**, including seven new
interpretation tests, the existing insight screen journeys (including narrow
screen and larger text), PDF generation and monitoring/analysis tests.
`flutter analyze --no-pub` found no issues. Four final PDF pages and refreshed
weekly/data-quality/recovery screen captures were visually inspected. The
architecture checker reports 19 existing findings; the added explanation code
introduces no new layer dependencies in Views. Phone installation and native
print-dialog acceptance were not performed in this follow-up.

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
