# AI-Assisted Physical Treatment and Health Support System (APTHS)

A Flutter app for Android that helps older patients with chronic conditions follow a physical
treatment plan, track their health and eat within safe limits. Final Year Project (BMCS3404) by
**Lee Jun Ting** and **Elwin Koh Soon Yit**.

The app talks to two back ends:

- **Supabase**: accounts, profiles and everything the patient records (Postgres with row-level security).
- **The AI server** (FastAPI, repo `fyp-fastapi`): posture check, plan recommender, chatbot, health
  analysis, food recognition and the diet planner. It is stateless and never touches Supabase; the app
  sends what is needed and stores what comes back.

## Modules

| Module | What the patient gets | Main screens | Built by |
|---|---|---|---|
| M100 Personalised Health Profiling | register, log in (email or Google), health profile, risk level and safety limits | `login_view`, `profile_view` | both |
| M200 Health Monitoring and Tracking | blood pressure, glucose and weight readings (typed or from Health Connect), trends, health report | `monitoring_view`, `health_report_view` | Jun Ting |
| M300 Physical Treatment | exercise sessions recorded on the phone with a posture check | `treatment_view` | Elwin |
| M400 Predictive Health Analysis | forecast of each reading, unusual readings, health score and condition risk | `monitoring_view`, `health_report_view` | Jun Ting |
| M500 AI-Assisted Treatment Planning | questionnaire, ranked treatment plans, rehabilitation chatbot | `planning_view` | Elwin |
| M600 Notification and Alert | M600.1 exercise reminders (Elwin); M600.2 health and diet alerts, meal reminders (Jun Ting) | `notification_view` | both |
| M700 Diet Support | meal photo recognition, nutrients and suitability of each food, daily and weekly diet plans, plan alerts | `diet_view` | Jun Ting |

### Diet Support (M700) in short

- **Log a meal from a photo.** The photo is reduced to 384 px and sent to `/recognise`. Each food
  found shows its confidence, its nutrients for the portion and a verdict for the patient's conditions
  (Suitable, Limit, Not Suitable) with the reason. Below 60 % confidence, the app asks the patient to
  search for the food instead.
- **Set the weight of each food.** Use the − and + buttons (one step is a quarter of a serving), or
  tap the weight and type it in grams. The weight must be **from 10 g to 1000 g**
  (`AppConstants.portionMinG` / `portionMaxG`). A weight outside that range, or text that is not a
  number, is refused with the reason, and **Set** stays off until the weight is accepted. The nutrients
  and the verdict follow the new weight at once.
- **Repeated foods.** Adding the same food twice in one meal combines its grams into one row and
  recalculates nutrients and suitability for the combined portion. Changing a food to another
  existing choice also merges them. The same food in different meals or days stays separate.
- **Diet plan.** A daily or weekly plan built from suitable foods only (`/plan`). It stays within the
  calorie target and the sodium and free-sugar limits.
  - The phone checks every returned food against the current profile, including locked foods.
    An unsafe reply is rejected and requested again, up to three attempts; it is never saved.
    User choices in the manual builder and Today/Weekly plan edits are allowed even when they
    conflict with the profile or limits. Those foods stay highlighted in red with the reason,
    including foods contributing to an excessive daily total; the warning does not block saving.
    Search includes all catalogue foods, and warnings persist when saved plans are reopened.
  - Today's meals in the weekly view follow Today's Plan, including portions, locks and empty slots.
    Weekly regeneration keeps them. Use **Edit today's plan** to change them; the other days stay.
  - **Build my plan myself** opens a draft with all four meals. Review existing picks, add several
    foods, change a food or portion, or remove one. The whole day is confirmed before saving;
    Close asks before discarding changes, and a failed save keeps the draft for another try.
    The builder shares the meal headers, food icons, nutrient rows and totals cards used by the
    Today/Weekly screens. Profile choices no longer include **Other condition (not listed)**.
  - The patient can add, remove or swap a food, or change a portion. Before saving, the app shows what
    the change does to the day. Anything that would go over a limit or is not good for the patient's
    conditions is shown in red.
    Saving an add, remove, swap or portion change shows progress with the action name and disables
    repeat taps until it finishes. Food search and delayed suggestions show their own progress;
    manual draft edits are immediate, with a spinner while the confirmed day is saved.
- **Plan alerts.** If a planned meal is not logged by 10:30, 14:30 or 20:30, or a logged meal is off
  the plan, the patient gets a reminder to follow the plan.

## Architecture

MVVM, layer-first: each layer of the software architecture diagram is a folder, and each box in a
layer is a folder inside it. Every folder has a `desc.txt` saying what belongs there.

```
lib/
  view/<name>_view/                  screens and their widgets; view/common/ = shared widgets
  viewmodel/<name>_view_model/       one ChangeNotifier ViewModel each
  model/
    business_logic/<name>_service/   services and the result types they return
    repository/<name>_repository/    i_<name>_repository.dart, supabase_..., fake_...
    entity/                          data classes named as in the Chapter 4 class diagram
    result.dart                      Result / Success / Failure
  shared_client/                     SupabaseProvider (repositories only), ApiClient (services only)
  device_platform/                   notifications, Health Connect, camera and gallery, speech, local settings
  core/                              constants and report messages, routes, themes, utils
  main.dart                          the only file that names a concrete repository
```

These rules are checked by `python tool/check_architecture.py`:

- **Layers.** Views → ViewModels → services → repository interfaces. A view never imports a
  repository, the shared client or Supabase.
- **Results.** Repository and service methods return `Future<Result<T>>` and never throw.
- **State.** State management is `provider` + `ChangeNotifier`. The models are plain Dart, with no
  code generation.

More detail is in [`CLAUDE.md`](CLAUDE.md).

## Set-up

Requirements:

- Flutter (Dart SDK ^3.12)
- Android Studio with an Android device or emulator
- For Health Connect: an Android phone with Health Connect installed

```
flutter pub get
flutter run
```

`flutter run` uses the team's Supabase project and the AI server address built into
`lib/core/constants/app_constants.dart`. To use other values, copy `config/dev.example.json` to
`config/dev.json` (git-ignored), fill it in and run
`flutter run --dart-define-from-file=config/dev.json`.

| Key | Meaning |
|---|---|
| `USE_FAKES` | `true` runs on in-memory data with no Supabase or internet (demo account `demo@apths.test` / `password123`) |
| `SUPABASE_URL`, `SUPABASE_ANON_KEY` | the Supabase project and its **publishable** key. The secret / service-role key and the database password never go in the app or in Git |
| `AI_BASE_URL` | the AI server's address when the app first starts (default `https://billion-rehab-marker-uploaded.trycloudflare.com`) |
| `GOOGLE_SIGN_IN` | `false` hides "Continue with Google" |

**AI server address.** The address can be changed on the phone with no new build:
**Profile > AI server**, enter the address, **Test connection**, **Save**.

- On the same Wi-Fi as the laptop, use the laptop's address, e.g. `http://192.168.0.13:8000`. Plain
  http works in debug builds only.
- From anywhere, use the Cloudflare tunnel address (`https://….trycloudflare.com`).

How to start the server and the tunnel: the `fyp-fastapi` README, section "Phone and laptop".

**Database.** How to create the Supabase project (migrations, seeds, storage bucket) is in
[`supabase/HANDOFF.md`](supabase/HANDOFF.md). The food catalogue seed comes from the AI server's
`food_catalogue.json`, so the app and the server use the same foods and values:
`python supabase/seed/build_food_seed.py`.

## Tests and checks

```
flutter analyze                    # must report no issues
flutter test                       # 593 tests in 49 files (9 Nov 2026)
python tool/check_architecture.py  # the layer rules above
dart run tool/check_ai_server.dart http://192.168.0.13:8000 [--photo meal.jpg] [--token <Supabase token>]
```

- `check_ai_server.dart` calls every AI server endpoint through the app's own services and prints
  PASS or FAIL for each.
- The Postman collection "FYP AI server (M400 / M700) tests" in the workspace "FYP AI server API
  testing" checks the same endpoints, including that diet plans contain suitable foods only.

## Data and licences

- **Food photos.** No food photos are shipped in the app. The recogniser was trained on the AI server
  side, partly on FoodSG-233, which is for non-commercial research only and is not redistributed.
- **Nutrients.** Nutrient values come from USDA FoodData Central ingredients and Malaysian laboratory
  analyses (see the AI server's `training/reports/catalogue_validation.md`).
- **Patient data.** Patient data stays in Supabase under row-level security. The AI server receives
  only condition codes, readings and a pseudonymous id, never a name.
