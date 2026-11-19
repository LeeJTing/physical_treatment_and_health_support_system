# Jun Ting's app journey tests

These suites exercise the production `MainApp`, routes, Views, ViewModels and business services with disposable repositories and scripted AI/device inputs. They cover Jun Ting's M100 shared profile/account flows, M200, M400, M600.2 and M700. Elwin's exercise, treatment-planning and chatbot behavior is outside this suite.

The Android test package ends in **`.e2e`**. Default journey suites use synthetic records and photos; they do not contact Supabase, call the external AI server, read personal Health Connect records or schedule real patient notifications. Explicit live-watch targets below read an authorised physical watch and verify imports in disposable repositories. Closing/relaunching a demo resets its in-memory data. A normal `flutter run` uses the production setup. Always retain the device-test cleanup guard described below.

## Run both suites on Windows

Connect an Android phone with USB debugging authorized, or start a working Android emulator. Java 17+ and the official [Maestro CLI](https://docs.maestro.dev/maestro-cli/how-to-install-maestro-cli) are required. Flutter Integration Test comes from the installed Flutter SDK.

```powershell
& "$env:LOCALAPPDATA\Android\sdk\platform-tools\adb.exe" devices -l
.\tool\run_jt_e2e.ps1 -DeviceId '<device serial>' -MaestroPath 'C:\path\to\maestro\bin\maestro.bat'
```

Use `-Suite Flutter` or `-Suite Maestro` to run one framework. The runner stops on a failed command and writes logs, Maestro JUnit XML and failure artifacts beneath `build/e2e/<timestamp>/`. It verifies the APK package ID before installing it. Maestro's `clearState` applies only to the separate `.e2e` package. Local Maestro analytics are disabled by the runner; no cloud upload is requested.

The runner sets the Android SDK path, allows 60 seconds for Maestro driver startup and uses driver port 7001. The fixed port avoids the reported [host/device ephemeral-port collision](https://github.com/mobile-dev-inc/Maestro/issues/3684). Run only one controller against the phone at a time, keep it unlocked and stop stale offline emulator instances before discovery. Select an English/ASCII keyboard (the final login run used installed Microsoft SwiftKey) for native text-entry tests; a Chinese IME may translate food searches.

Always pass `--no-uninstall` for device tests. This Flutter SDK can infer the
normal package ID during cleanup despite installing the suffixed APK. The flag
prevents cleanup from uninstalling the normal application and its local state.
The runner includes it; do not remove it.

Individual commands:

```powershell
flutter test integration_test/jt_flows_test.dart -d '<device serial>' --no-uninstall --dart-define=E2E_TESTING=true --reporter expanded
flutter build apk --debug -t tool/e2e_app.dart --dart-define=E2E_TESTING=true
# Install only the verified .e2e APK, then:
maestro --device '<device serial>' test .maestro --driver-host-port 7001 --format JUNIT --output build/e2e/maestro.xml
```

`tool/e2e_app.dart` is the Maestro target. Do not use the normal `lib/main.dart` target for these flows. `E2E_TESTING=true` is required by both the demo composition and the Gradle package suffix. The ordinary 616-test suite remains `flutter test test`; device cases are counted separately.

## Coverage

| Area | Flutter Integration Test journeys | Maestro flows |
|---|---|---|
| M100 shared account/profile | Wrong-password recovery and login; invalid/valid profile age; decline and accept diet refresh; invalid/valid AI server address and readiness | `01_profile`, `08_login` |
| M200 tracking | Invalid reading cannot save; valid weight save/delete; Health Connect adapter connection/import and duplicate rejection | `02_tracking` |
| M400 analysis | Score and seven-day forecasts; retained score/stale forecast after scripted failure; declared-condition risk and contributing factors | `03_health_report` |
| M600.2 health/diet notifications | Health-note history/read state; health and meal reminder scheduling; high alert acknowledgement and deduplication | `04_health_diet_alerts` |
| M700 diet | Manual meal and combined duplicates/history; synthetic gallery photo/recognition/review; adequate daily/weekly plans and food information; three inadequate replies preserve saved plan; manual builder duplicates and saving advisory red warnings | `05_meal_logging`, `06_diet_plans`, `07_photo_review`, `09_manual_plan` |

There are **15 Flutter integration cases** and **9 independent Maestro flows**. The shared journey implementation is in `scenarios/jt_flows.dart`; the device entry point uses `IntegrationTestWidgetsFlutterBinding`. Stable Semantics identifiers expose authentication fields, profile numeric fields, reading fields, food search, the home notification bell and individual notification entries to Maestro. Flutter Keys alone are not accessible to Maestro ([official Flutter support guide](https://docs.maestro.dev/get-started/supported-platform/flutter)).

See [recorded results and screenshot evidence](RESULTS.md) for completed runs. The flows capture named PNG checkpoints beneath the selected test output directory.

## What a passing run establishes

Flutter integration tests assert both the displayed behavior and resulting disposable repository state, with a controlled text-input binding to avoid delayed native keyboard edits overwriting `enterText` values. Maestro drives the compiled APK through Android accessibility, the real keyboard, navigation and back actions. The native weight flow uses a whole-kilogram value; the phone's Chinese IME converted a decimal point into ideographic punctuation during setup. Decimal input remains covered by the Flutter journeys. The flows avoid `hideKeyboard`, which sent Back and closed forms on this phone, and wait for enabled Save controls where validation matters. The two frameworks are complementary ([Flutter integration test documentation](https://docs.flutter.dev/testing/integration-tests)).

The demo HTTP transport uses the API's response shapes and sends successful, underfilled and failed responses through the real API client and decoders. Unscripted endpoints return 501 and cannot escape to the network. These scripts do not establish real server reachability, model accuracy, clinical validity, real Google/email verification, physical camera/gallery permission handling, Health Connect OS grants, background alarm delivery or real database persistence. Keep those separate from isolated automation results; the earlier server regression suite and real server-to-Flutter contract fixtures provide additional evidence.

The notification scheduler and Health Connect/photo inputs are stand-ins, so permission dialogs and actual background notification delivery still require a separate device acceptance pass with dedicated test records. No real phone test should be reported as passing merely because this project builds or a host smoke check passes.

## Additional diet feature suite

`diet_features_test.dart` runs shared screen journeys for quantity correction, recorded-week
summaries, meal-reading associations, saved diet plans and photo review. They also run in
`test/diet_features_widget_test.dart`. The host suite passed; new Android execution is pending the
user's phone availability. Run `tool/run_jt_e2e.ps1 -DeviceId YOUR_DEVICE -FeatureSet DietFeatures`
for the new Integration Test target and Maestro flows 10/11. Its synthetic multi-food fixture is
selected by `E2E_MULTI_FOOD=true`. Existing JT flows use the legacy fixture.
See `../docs/testing/jt-diet-insights-2026-11-10/README.md` for evidence scope and commands.

### Try the preloaded diet demo

Build the separate debug app with the two flags below, then install its `.e2e` APK.

```powershell
flutter build apk --debug -t tool/e2e_app.dart --dart-define=E2E_TESTING=true --dart-define=E2E_MULTI_FOOD=true
```

The demo opens already signed in. Its in-memory records are recreated relative to
the device date on each new launch.

- **Diet → Log Meal → Choose from gallery** supplies an illustrated test plate
  and a scripted reply for two boiled eggs (100 g total) and four pieces of tofu
  (120 g total). Change the egg count to three to check the revised 150 g total.
- **Diet → Diet review → Weekly review** shows the preloaded meals and nutrient
  contributors. **Previous week** has six recorded days and one gap.
- **Diet → Diet review → Meal & readings** shows the post-meal glucose and
  next-morning blood pressure scatter plots. Scroll down for the second plot.

All readings, meals and photo results in this APK are synthetic. The sample photo
exercises the review and save flow with a scripted response.

### Test a compatible wearable watch

Disconnect the watch from its companion app first, then keep Bluetooth on and the
watch close to the phone. The isolated test app can read
the watch over Bluetooth and save reviewed records in its disposable repositories.
The watch import screen requests Nearby devices access on Android 12 and later.
In Tracking, choose **Import from watch**, **Find my watch**, then your watch.
Review the saved dates and values, then tap **Connect and sync automatically**.
HealthGuide remembers the connection for the signed-in account, checks every
15 seconds while the app is open and checks again when the app returns to the
foreground. The watch PIN is kept in an encrypted Android Keystore connection
store. **Disconnect watch** stops future automatic checks for that account.
The record list identifies the source watch and labels its values as watch estimates.

The adapter reads blood pressure and numerical glucose records when supported
by the firmware. Zero or absent glucose values remain absent. Weight readings
come from Health Connect or manual entry. The watch's profile weight is a setup
value and is excluded from measured history.

Bluetooth discovery uses the Veepoo SDK's compatible-device scanner without a
KS02/K202 name filter. KS02 Pro is the physically tested model; other compatible
models require their own acceptance pass. For wearables using another protocol,
use Tracking's Health Connect connection when their companion app shares the
supported records. Bluetooth pairing alone does not expose every vendor's health data.

```powershell
flutter test integration_test/watch_device_test.dart -d YOUR_DEVICE --no-uninstall --dart-define=E2E_TESTING=true --reporter expanded
# For another authorised test watch, also pass --dart-define=WATCH_TEST_NAME="Exact watch name".
```

This acceptance test requires at least one valid stored watch reading.
It verifies direct SDK communication, restoration of the saved connection,
scheduled automatic reconnection and duplicate rejection. A synthetic weight
record checks the Health Connect path in the same test. The native screen journey is in `12_watch_import.yaml` and
should be run explicitly with the physical watch available.

### Tracking graph inspection and zoom

The graph acceptance target uses the production Tracking view with disposable
blood pressure, glucose and weight records. Each metric has three dated readings,
two imported with a known import time and one manual entry. It checks the value
popup, clearing it in a gap, switching metrics, pinch zoom/reset, legacy unknown
import times and an empty date range. It does not read the real watch or cloud.

```powershell
flutter test integration_test/tracking_graph_test.dart -d YOUR_DEVICE --no-uninstall --dart-define=E2E_TESTING=true
flutter build apk --debug -t tool/e2e_tracking_graph_app.dart --dart-define=E2E_TESTING=true
# Install only the verified .e2e APK, then run this explicit flow:
maestro --device YOUR_DEVICE test .maestro/flows/13_tracking_graph.yaml --driver-host-port 7001
```

The Maestro flow records pressure/glucose/weight detail popups, a cleared gap and
the zoomed graph. It is excluded from the default flows because it needs this
separate graph fixture target. New-record polling, serialization and preserving
the first import time on duplicate checks are covered by `watch_import_test.dart`.
The app checks saved watch history every 15 seconds while foregrounded, serializes
reads and saves new returned records immediately. This is polling, without an
instant blood-pressure/glucose push notification or closed-app background service.

### Planned and logged meal comparison

The comparison fixture uses the production Diet review with disposable plans and
meal logs for 9–22 November 2026. Its current week has 14 comparable meal slots:
four close matches, five portion changes and five food changes. One missing log,
six future slots and an extra snack remain separate. The previous week has 21
compared meals. The report does not infer intake from missing records.

```powershell
flutter test test/plan_comparison_test.dart test/plan_comparison_repository_test.dart test/plan_comparison_widget_test.dart
flutter test integration_test/plan_comparison_test.dart -d YOUR_DEVICE --no-uninstall --dart-define=E2E_TESTING=true
flutter build apk --debug -t tool/e2e_plan_comparison_app.dart --dart-define=E2E_TESTING=true
# Verify the built package ends in .e2e before installing it.
maestro --device YOUR_DEVICE test .maestro/flows/14_plan_comparison.yaml --driver-host-port 7001
```

Flow 14 needs its own fixture target and is excluded from the default suite.
It captures the matching diagram, nutrient bars, selected-day graph, repeated
changes, meal details and previous week. Core comparison values use saved
snapshots; planned macros use current catalogue estimates. Plans saved after
any log in a slot are reference only. Existing plan edits are not versioned.
The queries reuse existing authenticated Supabase access; there is no new
analysis provider or database migration.

### Diagnose a missing saved watch record

`watch_history_diagnostic_test.dart` reports firmware history capabilities and
checks that returned records survive import into disposable storage. Distinct
nearby timestamps are kept, and importing the same history twice adds zero on
the second attempt. It does not save readings in a real account or modify watch
settings. Detailed raw-value output is off unless explicitly requested.

```powershell
flutter test integration_test/watch_history_diagnostic_test.dart -d YOUR_DEVICE --no-uninstall --dart-define=E2E_TESTING=true
```

Keep other watch clients disconnected during a live test. The exact-timestamp
rule replaces the older five-minute suppression rule: consecutive genuine
measurements must not disappear. The existing database unique key and conflict
ignore preserve the first stored record and its import time on retries.
