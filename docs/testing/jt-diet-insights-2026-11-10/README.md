# Diet photos and review evidence

Implemented on 10 November 2026: A multiple-food quantity review, C weekly nutrition review and
D exploratory meal/reading patterns. All screenshots here are actual Flutter host-rendered screens
with isolated synthetic records. They are **not phone screenshots** and do not prove model accuracy,
live database persistence or real-world health associations. Existing November device evidence is
preserved separately in `../jt-device-2026-11-10`.

| Evidence | Observed checkpoint and scope |
|---|---|
| A01 quantity review | Boiled-egg count and total grams are editable. The shared test changes 2 / 100 g to 3 / 150 g, recalculates energy to 214.5 kcal and asserts saved confirmed metadata. Capture precedes the edit. |
| C01 weekly review | One of two elapsed days has logs; future days and missing logs are explicit. Average energy is 897 kcal for the recorded day, not 448.5 kcal across elapsed days. |
| C02 contributors | Synthetic rice accounts for 1035 mg and 100% of recorded sodium. The screen includes current guidance and stored-plan matching context. |
| D01 populated pattern | Fourteen controlled meal/glucose pairs produce Spearman +1.00; 1.3x text renders without framework exceptions. This manufactured monotonic series tests presentation, not a patient finding. |
| D02 insufficient records | Zero pairs withhold both associations and display the 12-pair/7-day app quality thresholds. A subsequent simulated reading failure is asserted separately. |

The manifest records SHA-256 hashes and rendering scope. PNGs are unedited captures. The host harness
loads Roboto/Material fonts from the Flutter SDK only when CAPTURE_DIET_EVIDENCE is enabled.

```powershell
$env:AI_SERVER_ROOT='C:\Users\User\Documents\GitHub\fyp-fastapi\ai_server'
flutter analyze --no-pub
flutter test --no-pub --reporter expanded
flutter test test/diet_features_widget_test.dart --dart-define=CAPTURE_DIET_EVIDENCE=true
```

Observed: **633 Flutter tests passed**; final static analysis reported no issues. The architecture
script retains **18 pre-existing findings** (14 Future-return conventions, two existing service uses
and two existing layer imports); none names the new review service or ViewModel. Do not describe
that check as clean. The three older cross-repository source tests now locate the separate server
through AI_SERVER_ROOT instead of assuming an embedded ai_server folder.

The server's full regression run passed **2208 tests**, with 2 skips and two existing warnings. The
final adapter refinements were then checked by **59 food, vision, OpenAPI and connection tests**.
Five local Postman HTTP simulation cases passed through the real adapter. Gemini Flash Lite returned
a usable public-photo response in 3344 ms. This is a connectivity/parsing check, not count/weight
accuracy validation; a cut egg makes the public image's whole count ambiguous. See the server
repository's `postman/verification/live-smoke.json` for provenance and limitations.

The nullable recognition_details migration was applied to the linked Supabase project. The object
constraint and owner RLS were verified; existing patient records were not edited. Isolated fake
repository roundtrips assert the metadata path, but do not establish a live authenticated save.

## Device checks pending

The user chose **Continue without phone tests for now** after ADB showed no connected devices.
New Flutter Integration Test cases and Maestro flows 10/11 are prepared but **not executed on
Android** in this change. No new keyboard, camera-permission, real gallery or Maestro pass is claimed.
The isolated APK build is checked separately. To run both new suites when the phone is available:

```powershell
powershell -ExecutionPolicy Bypass -File tool/run_jt_e2e.ps1 -DeviceId YOUR_DEVICE -FeatureSet DietFeatures -Suite Both -MaestroPath maestro
```

This builds only the separate `.e2e` test package, with E2E_MULTI_FOOD=true for synthetic recognition.
Use English input (SwiftKey English on the previously used phone). The normal JT suite explicitly
runs its original nine flows with the legacy fixture. HealthGuide Test and the normal app retain
separate storage. Inspect outputs under build/e2e before reporting device results.
