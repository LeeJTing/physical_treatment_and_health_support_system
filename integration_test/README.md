# Jun Ting's app journey tests

These suites exercise the production `MainApp`, routes, Views, ViewModels and business services with disposable repositories and scripted AI/device inputs. They cover Jun Ting's M100 shared profile/account flows, M200, M400, M600.2 and M700. Elwin's exercise, treatment-planning and chatbot behavior is outside this suite.

The Android test package ends in **`.e2e`**. It does not replace the ordinary app, contact Supabase, call the external AI server, read personal Health Connect records or schedule real patient notifications. All health readings and photos are synthetic. Closing/relaunching the demo resets its in-memory data. A normal `flutter run` still uses the existing production setup.

## Run both suites on Windows

Connect an Android phone with USB debugging authorized, or start a working Android emulator. Java 17+ and the official [Maestro CLI](https://docs.maestro.dev/maestro-cli/how-to-install-maestro-cli) are required. Flutter Integration Test comes from the installed Flutter SDK.

```powershell
& "$env:LOCALAPPDATA\Android\sdk\platform-tools\adb.exe" devices -l
.\tool\run_jt_e2e.ps1 -DeviceId '<device serial>' -MaestroPath 'C:\path\to\maestro\bin\maestro.bat'
```

Use `-Suite Flutter` or `-Suite Maestro` to run one framework. The runner stops on a failed command and writes logs, Maestro JUnit XML and failure artifacts beneath `build/e2e/<timestamp>/`. It verifies the APK package ID before installing it. Maestro's `clearState` applies only to the separate `.e2e` package. Local Maestro analytics are disabled by the runner; no cloud upload is requested.

The runner sets the Android SDK path, allows 60 seconds for Maestro driver startup and uses driver port 7001. The fixed port avoids the reported [host/device ephemeral-port collision](https://github.com/mobile-dev-inc/Maestro/issues/3684). Run only one controller against the phone at a time, keep it unlocked and stop stale offline emulator instances before discovery. Select an English/ASCII keyboard (the final login run used installed Microsoft SwiftKey) for native text-entry tests; a Chinese IME may translate food searches.

Individual commands:

```powershell
flutter test integration_test/jt_flows_test.dart -d '<device serial>' --dart-define=E2E_TESTING=true --reporter expanded
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
