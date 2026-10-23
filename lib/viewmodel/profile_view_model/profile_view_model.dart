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
import 'package:physical_treatment_and_health_support_system/model/repository/terms_repository/i_terms_repository.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/terms_acceptance.dart';

/// View and edit the health profile (UC300 Manage Profile; Table 4.51).
/// The saved profile and the editable draft are kept apart so Cancel restores
/// the saved values (FR100_052).
class ProfileViewModel extends BaseViewModel {
  final IProfileRepository _profiles;
  final IAuthRepository _auth;
  final RiskAssessmentService _risk;

  /// Cancels this phone's reminders when the account is deleted.
  final LocalNotificationService? _notifications;

  /// The age group accepted in the Terms, which the age must agree with.
  final ITermsRepository? _terms;

  ProfileViewModel(
    this._profiles,
    this._auth,
    this._risk, [
    this._notifications,
    this._terms,
  ]);

  /// Save stopped because the age does not match the age group accepted in
  /// the Terms (14 Oct): the screen offers "Review Terms".
  bool ageReviewNeeded = false;

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

  /// Conditions picked in this edit whose question is not answered yet.
  Set<int> unansweredConditions = {};

  /// What the screen shows: the draft while editing, else the saved profile.
  HealthProfile? get shown => isEditing ? draft : profile;

  /// A first profile counts as changed only once something is entered (audit, 24 Oct: the
  /// empty form asked "Discard your unsaved changes?").
  bool get hasUnsavedChanges =>
      isEditing &&
      draft != null &&
      !_same(draft!, profile ?? HealthProfile.empty(draft!.accountId));

  static bool _same(HealthProfile a, HealthProfile? b) =>
      b != null &&
      a.age == b.age &&
      a.gender == b.gender &&
      a.weightKg == b.weightKg &&
      a.heightCm == b.heightCm &&
      a.conditions.toSet().containsAll(b.conditions) &&
      b.conditions.toSet().containsAll(a.conditions) &&
      // The answers too (equality is by condition id only).
      a.conditions.every(
        (c) => b.conditions.any(
          (o) =>
              o.conditionId == c.conditionId &&
              o.controlled == c.controlled &&
              o.note == c.note,
        ),
      ) &&
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
    unansweredConditions = {};
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
    // An edited field loses its mark from the last Save (audit, 23 Oct). Weight and height
    // were marked together when they did not match, so editing either clears both.
    final edited = {
      if (age != null || clearAge) 'age',
      if (gender != null) 'gender',
      if (weightKg != null || clearWeight) 'weight',
      if (heightCm != null || clearHeight) 'height',
    };
    if (saveState case UiError(
      message: Messages.weightHeightMismatch,
    ) when edited.contains('weight') || edited.contains('height')) {
      edited.addAll(const ['weight', 'height']);
    }
    invalidFields = [
      for (final f in invalidFields)
        if (!edited.contains(f)) f,
    ];
    notifyListeners();
  }

  void toggleCondition(int id) {
    final d = draft;
    if (d == null || !isEditing) return;
    final c = conditions.firstWhere((c) => c.conditionId == id);
    final list = [...d.conditions];
    if (list.contains(c)) {
      list.remove(c);
      unansweredConditions.remove(id);
    } else {
      list.add(c);
      // A condition with a question waits for the answer (no default).
      if (c.statusQuestion != null) unansweredConditions.add(id);
    }
    draft = d.copyWith(conditions: list);
    notifyListeners();
  }

  /// The answer to a condition's status question (11 Oct).
  void setConditionControlled(int id, bool controlled) => _updateCondition(
    id,
    (c) => c.withStatus(controlled: controlled),
    answered: true,
  );

  /// What the "Other" condition is.
  void setConditionNote(int id, String note) =>
      _updateCondition(id, (c) => c.withStatus(note: note.trim()));

  void _updateCondition(
    int id,
    HealthCondition Function(HealthCondition) change, {
    bool answered = false,
  }) {
    final d = draft;
    if (d == null || !isEditing) return;
    draft = d.copyWith(
      conditions: [
        for (final c in d.conditions) c.conditionId == id ? change(c) : c,
      ],
    );
    if (answered) unansweredConditions.remove(id);
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
    unansweredConditions = {};
    draft = null;
    isEditing = false;
    invalidFields = const [];
    saveState = const Idle();
    notifyListeners();
  }

  /// True from the first line of [saveProfile] to its end: a second Save while the first is
  /// on its way (before it shows Loading) would write the profile twice (23 Oct).
  bool _saving = false;

  /// Validates, saves the profile with a regenerated safety limit (FR100_057) and reloads.
  Future<bool> saveProfile() async {
    if (_saving) return false;
    _saving = true;
    try {
      return await _save();
    } finally {
      _saving = false;
    }
  }

  Future<bool> _save() async {
    final d = draft;
    if (d == null) return false;
    // Every question answered, and the "Other" condition named (11 Oct).
    final conditionProblem = unansweredConditions.isNotEmpty
        ? Messages.conditionQuestionUnanswered
        : d.conditions.any((c) => c.isOther && (c.note ?? '').isEmpty)
        ? Messages.otherConditionNote
        : null;
    if (conditionProblem != null) {
      saveState = UiError(conditionProblem);
      notifyListeners();
      return false;
    }
    final errors = d.validate();
    ageReviewNeeded = false;
    final bmi = d.calculateBmi();
    if (errors.isEmpty &&
        (bmi < AppConstants.bmiMin || bmi > AppConstants.bmiMax)) {
      invalidFields = const ['weight', 'height'];
      saveState = const UiError(Messages.weightHeightMismatch);
      notifyListeners();
      return false;
    }
    if (errors.isEmpty) {
      final mismatch = await _ageGroupMismatch(d.age!);
      if (mismatch != null) {
        invalidFields = const ['age'];
        ageReviewNeeded = true;
        saveState = UiError(mismatch);
        notifyListeners();
        return false;
      }
    }
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
    final limit = _risk.generateSafetyLimit(d);
    final res = await _profiles.saveProfile(d, limit);
    if (res is Failure) {
      saveState = const UiError(
        Messages.profileSaveFailed,
      ); // the draft is kept
      notifyListeners();
      return false;
    }
    isEditing = false;
    draft = null;
    unansweredConditions = {};
    // What was saved is shown even if the reload below fails (connection lost right after the
    // save); the reload then only brings the stored version number (audit, 23 Oct).
    profile = d.copyWith(version: d.version + 1, updatedAt: DateTime.now());
    safetyLimit = limit;
    await loadProfile();
    saveState = const UiSuccess(null);
    notifyListeners();
    return true;
  }

  /// The message when [age] does not agree with the age group of the last
  /// accepted Terms, else null. Not checked when the Terms cannot be read
  /// (offline, or no acceptance yet), as with the sign-in gate.
  Future<String?> _ageGroupMismatch(int age) async {
    final terms = _terms;
    final id = (await _auth.currentAccount()).dataOrNull?.accountId;
    if (terms == null || id == null) return null;
    final last = (await terms.latestAcceptance(id)).dataOrNull;
    if (last == null) return null;
    final adult = age >= AppConstants.adultAge;
    if (last.ageGroup == TermsAgeGroup.minor && adult) {
      return Messages.ageAboveTermsGroup;
    }
    if (last.ageGroup == TermsAgeGroup.adult && !adult) {
      return Messages.ageBelowTermsGroup;
    }
    return null;
  }

  /// Logs out (FR100_059). Once signed out, every HealthGuide notification is taken off the
  /// phone, so the reminders stop ringing and a next person on the phone does not get them
  /// (Elwin, 23 Oct). Cancelling all of them, not reading the account's reminders first, also
  /// works offline (PC review). They stay saved and come back at the next sign-in. A failed
  /// sign-out leaves them as they are.
  Future<bool> logout() async {
    final ok = (await _auth.signOut()).isSuccess;
    if (ok) await _notifications?.cancelEverything();
    return ok;
  }

  UiState<void> deleteState = const Idle();

  /// "Delete my account" (Privacy Notice section 5): the account and all its data are
  /// deleted, then every reminder is taken off the phone. Only after a successful delete,
  /// as with log out, so a failed delete leaves the reminders ringing (audit, 23 Oct).
  Future<bool> deleteAccount() async {
    deleteState = const Loading();
    notifyListeners();
    final res = await _auth.deleteAccount();
    if (res.isSuccess) await _notifications?.cancelEverything();
    deleteState = res.isSuccess
        ? const UiSuccess(null)
        : const UiError(Messages.accountDeleteFailed);
    notifyListeners();
    return res.isSuccess;
  }
}
