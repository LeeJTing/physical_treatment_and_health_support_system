# Current workflow requirements and design review

Reviewed on 25 November 2026 against application JT `293dc96` and the separate
AI-server checkout `e27e8eb`. This is a documentation update. No application,
server, watch or database behaviour is changed.

The report's original convention is retained: functional requirements begin
**The system shall**, existing FR and UC identifiers remain stable, and the
new IDs continue the relevant module sequence. Use cases use the same
Description, Pre-condition, Post-condition, Patient/System basic flow,
Alternative flow, Exception flow, Message and Constraints/Notes structure.
Basic steps use explicit BF identifiers; alternatives/exceptions/constraints
retain A, E and C labels. Message examples come from current application
constants or the corresponding ViewModel.

The update changes the actual Chapters 3 and 4, rather than adding only another
appendix. It revises 35 existing functional clauses, adds 56 workflow clauses,
updates eight existing use cases and adds six related cases:

| Use case | Workflow | Main implementation evidence |
| --- | --- | --- |
| UC100 | Registration, verification/provider setup and required consent before personalisation | AuthViewModel, IAuthRepository, TermsAcceptance |
| UC200 | Login/restored session, current terms and profile routing | AuthViewModel, SessionPolicy |
| UC300 | Profile, food exclusions, condition status and optional diet refresh | ProfileViewModel, HealthProfile, ProfileView |
| UC600 | Health score/risk/forecast explanations and available/stale states | AnalysisViewModel, HealthReportView, ForecastService |
| UC700 | Manual readings, Health Connect, compatible watch import and interactive exercise/biometric graphs | MonitoringViewModel, VeepooWatchSource, HealthConnectService, TrendChart |
| UC800 | Multiple-food photo/manual review, quantities, duplicate merge and explicit save | MealLogViewModel, FoodRecognitionService, FoodRecognitionDetails |
| UC900 | Strict AI generation versus advisory patient choices; saved/future dates | DietPlanViewModel, DietPlannerService |
| UC1000 | Account-scoped profile/status retrieval and conservative fallback | RiskAssessmentService |
| UC610 | Interactive health timeline | HealthTimeline, HealthInsightsService |
| UC620 | Weekly review and matching offline PDF | HealthInsightsViewModel, WeeklyReportService |
| UC630 | Source/import counts, gaps and data quality | HealthInsightsService, HealthInsightsView |
| UC640 | Owned assignment/date symptom diary | RecoveryCheckIn, IRecoveryRepository and existing migration |
| UC810 | Isolated meal proposal and explicit return to draft | MealSimulationService, MealSimulationViewModel |
| UC910 | Fair meal comparison and specific daily/weekly food options | PlanComparisonService, DietFoodGuidanceService, DietInsightsService |

`specification.json` contains the revised/additional clauses and implemented
constraints. `use_cases.json` supplies the matched use-case content.
`class_specifications.json` covers the added logical-design classes.
`draw_diagrams.py` renders reproducible figures; `figures/` contains design
artefacts, not execution screenshots.

The diagrams update profile, recognition, saved/future plans, source imports,
tracking and profile retrieval activities/sequences. Cross-module insight,
recovery, comparison and simulation flows, current class relationships,
deployment/privacy boundaries and recovery/provenance storage are included.
Existing chapter-local figure/table numbers and textual references are
renumbered together; FR and UC IDs are not renumbered.

Important implementation boundaries are explicit:

- AI-generated plans must pass current portion suitability, lower nutrition
  needs and upper budgets before persistence, with at most three attempts.
  Valid patient-selected foods, including manual plans, can be saved with red
  warnings; malformed amounts/dates still block saving.
- Future plans cover 1–31 inclusive days starting after today. All requested
  blocks must succeed before the assembled period is saved. Older dates open
  saved plans without generating replacements.
- Active-app checks run about once per minute for Health Connect and every
  15 seconds for supported saved watch history. Continuous background delivery,
  universal watch compatibility and immediate screen-to-phone values are not
  promised. Original measurement time, first import time and successful-check
  time are separate. A five-minute read overlap does not shift timestamps.
- Online vision proposes identities/counts/weights; local fallback uses standard
  portions. Nutrition comes from the catalogue and reviewed grams. The owned
  server does not forward health-profile fields or session credentials to the
  optional online image provider.
- Missing logs remain unknown. Later-created plans are reference-only. Weekly
  food totals describe observed occurrences; conditional swaps are explicit.
- Diary symptoms remain separate from posture scores and treatment progress.
  The demo filter changes Health insights and its PDF, not existing forecast
  inputs or stored rows.

Schema descriptions were checked against the existing repository contracts and
migration/deployment SQL, notably terms_acceptance, recognition_details,
imported_at and recovery_check_in. No live patient records
were queried or changed. The Supabase changelog and official
[row-level security documentation](https://supabase.com/docs/guides/database/postgres/row-level-security)
were consulted for ownership terminology; no SDK upgrade or schema migration is
part of this revision.

Historical tests, model results, screenshots and appendices are retained as
dated evidence. The existing 15-versus-17 app/server posture-catalogue mismatch
is not treated as resolved by a documentation change. Validation for this task
checks identifiers, use-case structure, traceability, preserved evidence,
caption references, contents/page numbering and rendered document layouts.

Final report verification

Report v34 contains 511 rendered pages. All 252 functional requirements
use the existing shall convention, and all 14 reviewed use cases pass the
required-section and Patient/System flow checks. The chapter captions and
references were renumbered together and Word refreshed the contents and page
numbers. All 44 updated figure captions share a page with an image.
The earlier implementation/testing/appendix text is preserved apart from
updated Chapter 3/4 caption references; 54 historical evidence images match
the source report by SHA-256. Rendered pages and the revised diagrams were
visually reviewed. The packaged renderer lacked LibreOffice; the installed
Microsoft Word exporter and bundled Poppler supplied the verified rendering.

The versioned report is delivered in Downloads as `RSW Lee Jun Ting-FYP Report (full v34).docx`; v33 is
retained. `report-validation.json` records hashes, counts and validation scope.
No Flutter, API, phone or clinical tests were rerun for this documentation-only
revision. Existing dated test outcomes retain their original scope.
