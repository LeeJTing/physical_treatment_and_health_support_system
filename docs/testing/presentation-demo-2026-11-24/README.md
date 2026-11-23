# Presentation data verification

Three separate historical weeks demonstrate saved-plan comparisons: 5–11 October 2026
(28 of 28 meals close to plan), 12–18 October (0 of 28) and 19–25 October (14 of 28).
Each week has breakfast, lunch, dinner and snack records for every day. These are
synthetic scenarios, not an observed patient adherence study.

The account owner approved a 65 kg demonstration profile and separate weeks to keep
existing plans intact. The production planner generates the menus from the live food
catalogue and the approved profile's restrictions and physical limitations. The
different-food scenarios retain those restrictions but deliberately use larger,
energy-dense meals to exercise comparison charts and nutrition explanations.

The generated history includes 234 biometric readings (57 blood pressure, 120 glucose,
57 weight) and 23 completed exercise sessions. Seven completed treatment cycles and
one partially completed cycle provide history and progress examples. Readings are
labelled `Presentation demo (synthetic)`; sessions include explicit synthetic feedback.
Import times record the actual database insertion time. Existing real records remain.

## Reproduce the preparation and checks

`tool/build_presentation_demo.py` builds private JSON, a guarded SQL transaction and a
guarded removal script. It never executes SQL. This is a dated presentation fixture
with explicit profile and catalogue assumptions, not a general account seeder.
Supply a reviewed private `context.json` under ignored `build/`, with `context`
(account, profile, limits, restrictions, limitations), `foods` and `treatments`.
Treatment rows include their prescribed exercises. Do not commit that input or the
generated account IDs, raw health history or SQL.

```powershell
python tool/build_presentation_demo.py --context build/presentation-demo-2026-11-24/context.json --server-root C:/Users/User/Documents/GitHub/fyp-fastapi/ai_server --output build/presentation-demo-2026-11-24
flutter test tool/verify_presentation_demo_test.dart --no-pub --reporter expanded
flutter analyze --no-pub
```

Use a compatible Python runtime with the AI server's existing dependencies. Inspect
the manifest, overlap guards and profile version before applying the SQL to the
authorized account. Deterministic IDs and conflict handling prevent duplicate rows
when the same unchanged fixture is reapplied. The removal script is only prepared;
it has not been executed and retains the approved profile and current limits.

## Results on 24 November 2026

- All five explicit Flutter checks passed using the production nutrition gate and
  `PlanComparisonService`. All three generated weeks pass planner checks, and the
  comparison counts are exactly 28/0, 0/28 and 14/14.
- Flutter analyzer reported no issues. No application behavior changed.
- Live database checks confirmed 3 plans, 84 meal logs, 234 readings and 23 sessions;
  food restriction conflicts and meal-total snapshot errors were zero.
- Original row/hash checks found no missing or changed existing meal logs, meal items,
  readings, diet plans, planned-meal groups or patient plans. The approved profile and
  current safety-limit selection are the intentional updates.
- Direct calls to the production Python forecast and analysis functions, using only
  the generated input, returned seven-day forecasts for all three metrics and a
  non-withheld Health Score. The full account also contains existing real readings;
  its refreshed report can therefore differ from this fixture-only check.
- No phone was connected. This session does not claim Maestro, Integration Test,
  live AI endpoint acceptance or new phone screenshot evidence.

## Present the scenarios

Open **Diet → Diet review → Plan comparison**, then select each October week with
Previous week. The summary should show 28 meals compared for each week, with 28, 0,
and 14 close to plan respectively. Tap graph days and meal rows to explain food and
nutrient changes. View the saved menus through **Weekly Plan → View saved plan**.

In Tracking, use a custom period covering 28 September–23 November 2026 to show the
synthetic readings, or 5–25 October for the diet scenarios. Refresh Health Report with
the AI server online. Biometric history feeds the forecasts; exercise history feeds
activity analysis and the Health Score. This fixture does not establish that diet
or treatment caused a real physiological change.
