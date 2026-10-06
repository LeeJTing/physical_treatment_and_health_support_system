# CLAUDE.md — AI-Assisted Physical Treatment and Health Support System

Flutter app (Android) + FastAPI AI server. Team: Lee Jun Ting and Elwin Koh Soon Yit. Each works on their own branch.

If you are working for Elwin, also read `../fyp-notes/CLAUDE.md` and `../fyp-notes/PROJECT_STATE.md` first, and log every step there.

## Layout (feature-first MVVM, keep it)

| What | Where |
|---|---|
| `Result`, `UiState` (`Idle`, `Loading`, `UiSuccess`, `UiError`), `BaseViewModel` | `lib/core/base/` |
| Constants and user-facing messages copied verbatim from the use cases | `lib/core/constants/app_constants.dart` |
| `ApiClient`, `SupabaseProvider`, AI-calling services | `lib/core/services/` |
| Themes (`lightTheme`, `darkTheme`) | `lib/core/themes/` |
| Helpers (`FormValidators`, `ValidatorUtils`, `newId()`) | `lib/core/utils/` |
| Shared widgets (`StateBuilder`, `PrimaryButton`) | `lib/core/widgets/` |
| Entities, named exactly as the Chapter 4 class diagram | `lib/data/models/` |
| Repository interfaces / fakes / Supabase implementations | `lib/data/repository/{interfaces,fake,supabase}/` |
| One folder per feature: `view/`, `viewmodel/`, `widgets/`, `model/` | `lib/features/<feature>/` |
| AI server (stateless; never touches Supabase) | `ai_server/` |
| Posture model training (runs on the RTX 3050 PC) | `training/` |
| Catalogue seed for Supabase (`python supabase/seed/build_seed.py`) | `supabase/` |

## Rules

- View → ViewModel → service → repository **interface**. Views never import repositories, `ApiClient` or Supabase.
- `lib/main.dart` is the only file that names a concrete repository class.
- Repository and service methods return `Future<Result<T>>` and never throw.
- State management is `provider` + `ChangeNotifier` (no Riverpod, no Bloc). Plain Dart models, no code generation.
- Class names must match the report's Chapter 4 class diagram.
- Run with fakes until Supabase is ready: `flutter run --dart-define=USE_FAKES=true`.

## Commands

- App: `flutter pub get`, `flutter analyze`, `flutter test`
- AI server: `cd ai_server`, `pip install -r requirements.txt`, `pytest -q`, `uvicorn app.main:app --reload --port 8000`
