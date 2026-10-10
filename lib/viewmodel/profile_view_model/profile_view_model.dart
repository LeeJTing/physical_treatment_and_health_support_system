import 'package:physical_treatment_and_health_support_system/viewmodel/base_view_model.dart';
import 'package:physical_treatment_and_health_support_system/model/result.dart';
import 'package:physical_treatment_and_health_support_system/viewmodel/ui_state.dart';
import 'package:physical_treatment_and_health_support_system/core/constants/app_constants.dart';
import 'package:physical_treatment_and_health_support_system/model/business_logic/local_notification_service/local_notification_service.dart';
import 'package:physical_treatment_and_health_support_system/model/business_logic/risk_assessment_service/risk_assessment_service.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/account.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/enums.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/health_profile.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/lookups.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/safety_limit.dart';
import 'package:physical_treatment_and_health_support_system/model/repository/auth_repository/i_auth_repository.dart';
import 'package:physical_treatment_and_health_support_system/model/repository/profile_repository/i_profile_repository.dart';

/// View and edit the health profile (UC300 Manage Profile; Table 4.51).
/// The saved profile and the editable draft are kept apart so Cancel restores
/// the saved values (FR100_052).
class ProfileViewModel extends BaseViewModel {
  final IProfileRepository _profiles;
  final IAuthRepository _auth;
  final RiskAssessmentService _risk;

  /// Cancels this phone's reminders when the account is deleted.
  final LocalNotificationService? _notifications;

  ProfileViewModel(
    this._profiles,
    this._auth,
    this._risk, [
    this._notifications,
  ]);

  Account? account;
  HealthProfile? profile; // last saved
  HealthProfile? draft; // being edited
  SafetyLimit? safetyLimit;
  List<HealthCondition> conditions = const [];
  List<PhysicalLimitation> limitations = const [];

  UiState<void> loadState = const Idle();
  UiState<void> saveState = const Idle();
  bool isEditing = false;

  /// Field that failed validation last time Save was pressed ('age', 'weight', ...).
  List<String> invalidFields = const [];

  /// What the screen shows: the draft while editing, else the saved profile.
  HealthProfile? get shown => isEditing ? draft : profile;

  bool get hasUnsavedChanges =>
      isEditing && draft != null && !_same(draft!, profile);

  static bool _same(HealthProfile a, HealthProfile? b) =>
      b != null &&
      a.age == b.age &&
      a.gender == b.gender &&
      a.weightKg == b.weightKg &&
      a.heightCm == b.heightCm &&
      a.conditions.toSet().containsAll(b.conditions) &&
      b.conditions.toSet().containsAll(a.conditions) &&
      a.limitations.toSet().containsAll(b.limitations) &&
      b.limitations.toSet().containsAll(a.limitations);

  Future<void> loadProfile() async {
    loadState = const Loading();
    notifyListeners();
    final acc = await _auth.currentAccount();
    if (acc case Success(:final data) when data != null) {
      account = data;
    } else {
      loadState = const UiError(Messages.sessionExpired);
      notifyListeners();
      return;
    }
    final results = await Future.wait([
      _profiles.getProfile(account!.accountId),
      _profiles.getConditions(),
      _profiles.getLimitations(),
    ]);
    final p = results[0] as Result<HealthProfile?>;
    if (p is Failure) {
      loadState = const UiError(Messages.profileLoadFailed);
      notifyListeners();
      return;
    }
    profile = p.dataOrNull;
    conditions =
        (results[1] as Result<List<HealthCondition>>).dataOrNull ??
        LookupSeed.conditions;
    limitations =
        (results[2] as Result<List<PhysicalLimitation>>).dataOrNull ??
        LookupSeed.limitations;
    safetyLimit = profile == null
        ? null
        : (await _profiles.getCurrentSafetyLimit(
            profile!.profileId,
          )).dataOrNull;
    // A brand-new patient has no profile yet: open straight in edit mode.
    if (profile == null) {
      draft = HealthProfile.empty(account!.accountId);
      isEditing = true;
    } else if (!isEditing) {
      draft = null;
    }
    loadState = const UiSuccess(null);
    notifyListeners();
  }

  void startEdit() {
    final p = profile;
    if (p == null && account == null) return;
    draft = p ?? HealthProfile.empty(account!.accountId);
    isEditing = true;
    invalidFields = const [];
    saveState = const Idle();
    notifyListeners();
  }

  /// Text fields pass their parsed value; an empty or unparsable field passes null.
  void updateDraft({
    int? age,
    Gender? gender,
    double? weightKg,
    double? heightCm,
    bool clearAge = false,
    bool clearWeight = false,
    bool clearHeight = false,
  }) {
    final d = draft;
    if (d == null) return;
    draft = HealthProfile(
      profileId: d.profileId,
      accountId: d.accountId,
      age: clearAge ? null : (age ?? d.age),
      gender: gender ?? d.gender,
      weightKg: clearWeight ? null : (weightKg ?? d.weightKg),
      heightCm: clearHeight ? null : (heightCm ?? d.heightCm),
      conditions: d.conditions,
      limitations: d.limitations,
      restrictions: d.restrictions,
      version: d.version,
      updatedAt: d.updatedAt,
    );
    notifyListeners();
  }

  void toggleCondition(int id) {
    final d = draft;
    if (d == null || !isEditing) return;
    final c = conditions.firstWhere((c) => c.conditionId == id);
    final list = [...d.conditions];
    list.contains(c) ? list.remove(c) : list.add(c);
    draft = d.copyWith(conditions: list);
    notifyListeners();
  }

  void toggleLimitation(int id) {
    final d = draft;
    if (d == null || !isEditing) return;
    final l = limitations.firstWhere((l) => l.limitationId == id);
    final list = [...d.limitations];
    list.contains(l) ? list.remove(l) : list.add(l);
    draft = d.copyWith(limitations: list);
    notifyListeners();
  }

  /// The "None" chip.
  void clearLimitations() {
    final d = draft;
    if (d == null || !isEditing) return;
    draft = d.copyWith(limitations: const []);
    notifyListeners();
  }

  /// Discards the draft (FR100_052). A patient without any saved profile stays in edit mode.
  void cancelEdit() {
    if (profile == null) return;
    draft = null;
    isEditing = false;
    invalidFields = const [];
    saveState = const Idle();
    notifyListeners();
  }

  /// Validates, saves the profile with a regenerated safety limit (FR100_057) and reloads.
  Future<bool> saveProfile() async {
    final d = draft;
    if (d == null) return false;
    final errors = d.validate();
    if (errors.isNotEmpty) {
      invalidFields = errors;
      final missing =
          d.age == null ||
          d.gender == null ||
          d.weightKg == null ||
          d.heightCm == null;
      saveState = UiError(
        missing ? Messages.requiredFieldsEmpty : Messages.valueOutOfRange,
      ); // FR100_049, FR100_051
      notifyListeners();
      return false;
    }
    invalidFields = const [];
    saveState = const Loading();
    notifyListeners();
    final res = await _profiles.saveProfile(d, _risk.generateSafetyLimit(d));
    if (res is Failure) {
      saveState = const UiError(
        Messages.profileSaveFailed,
      ); // the draft is kept
      notifyListeners();
      return false;
    }
    isEditing = false;
    draft = null;
    await loadProfile();
    saveState = const UiSuccess(null);
    notifyListeners();
    return true;
  }

  Future<bool> logout() async => (await _auth.signOut()).isSuccess;

  UiState<void> deleteState = const Idle();

  /// "Delete my account" (Privacy Notice section 5): the phone's reminders are
  /// cancelled, then the account and all its data are deleted.
  Future<bool> deleteAccount() async {
    deleteState = const Loading();
    notifyListeners();
    final id = account?.accountId;
    if (id != null) await _notifications?.cancelAllFor(id);
    final res = await _auth.deleteAccount();
    deleteState = res.isSuccess
        ? const UiSuccess(null)
        : const UiError(Messages.accountDeleteFailed);
    notifyListeners();
    return res.isSuccess;
  }
}
