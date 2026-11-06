# CLAUDE.md — AI-Assisted Physical Treatment and Health Support System

Flutter app (Android) + FastAPI AI server. Team: Lee Jun Ting and Elwin Koh Soon Yit. Each works on their own branch.

If you are working for Elwin, also read `../fyp-notes/CLAUDE.md` and `../fyp-notes/PROJECT_STATE.md` first, and log every step there.

## Layout (layer-first, mirrors the software architecture diagram; keep it)

Each layer of the diagram is a folder, and each box (column) in a layer is a folder inside it.
Every folder has a `desc.txt` saying what belongs there; boxes not built yet (mostly Jun Ting's M200/M400/M700) are empty folders with only `desc.txt`.

| Diagram layer | Folder | Inside |
|---|---|---|
| View | `lib/view/<name>_view/` | the screen, its sub-screens, `widgets/` used only there; `lib/view/common/` = shared widgets (`StateBuilder`, `PrimaryButton`, `StatusBarStrip`, `RehabLabels`) |
| ViewModel | `lib/viewmodel/<name>_view_model/` | one ViewModel each; `base_view_model.dart`, `ui_state.dart` (`Idle`, `Loading`, `UiSuccess`, `UiError`) at the top |
| Model: Business Logic (Service layer) | `lib/model/business_logic/<name>_service/` | the service and the result types it returns (e.g. `chat_reply.dart`, `recommendation.dart`) |
| Model: Repository layer | `lib/model/repository/<name>_repository/` | `i_<name>_repository.dart` (interface), `supabase_<name>_repository.dart`, `fake_<name>_repository.dart`; `supabase_guard.dart` at the top |
| Model: entities | `lib/model/entity/` | data classes named exactly as the Chapter 4 class diagram; `lib/model/result.dart` = `Result`/`Success`/`Failure` |
| Shared Client | `lib/shared_client/{supabase_provider,api_client}/` | `SupabaseProvider` (repositories only), `ApiClient` (services only) |
| Device Platform | `lib/device_platform/<name>/` | `NotificationScheduler`; Health Connect and Camera / Gallery folders |
| (cross-cutting) | `lib/core/{constants,routes,themes,utils}/` | report messages (`app_constants.dart`), routes, themes and `design_tokens.dart`, `FormValidators`, `newId()` |
| AI server (stateless; never touches Supabase) | `ai_server/` | |
| Posture model training (runs on the RTX 3050 PC) | `training/` | |
| Catalogue seed for Supabase (`python supabase/seed/build_seed.py`; food catalogue `python supabase/seed/build_food_seed.py` after copying `food_catalogue.json` from fyp-fastapi to `assets/seed/`) | `supabase/` | set-up steps in `supabase/HANDOFF.md` |

## Rules

- View → ViewModel → Model (service → repository **interface**). Views never import `lib/model/repository/`, `lib/shared_client/` or Supabase; ViewModels never import `lib/view/`.
- `lib/main.dart` is the only file that names a concrete repository class.
- Repository and service methods return `Future<Result<T>>` and never throw.
- State management is `provider` + `ChangeNotifier` (no Riverpod, no Bloc). Plain Dart models, no code generation.
- Class names must match the report's Chapter 4 class diagram.
- `flutter run` uses the real Supabase project (URL and publishable key are the defaults in `app_constants.dart`). In-memory fakes only on request: `flutter run --dart-define=USE_FAKES=true`.

## Commands

- App: `flutter pub get`, `flutter analyze`, `flutter test`
- AI server: `cd ai_server`, `pip install -r requirements.txt`, `pytest -q`, `uvicorn app.main:app --reload --port 8000`
- Phone ↔ AI server on the laptop: the address is set in the app (Profile > AI server, saved on the phone; `AI_BASE_URL` is only the default). Check a server from here with `dart run tool/check_ai_server.dart <address>`; server side see fyp-fastapi README "Phone and laptop".
