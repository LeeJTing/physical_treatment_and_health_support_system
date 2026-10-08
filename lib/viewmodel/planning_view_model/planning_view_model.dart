import 'package:physical_treatment_and_health_support_system/model/business_logic/local_notification_service/local_notification_service.dart';
import 'package:physical_treatment_and_health_support_system/viewmodel/base_view_model.dart';
import 'package:physical_treatment_and_health_support_system/model/result.dart';
import 'package:physical_treatment_and_health_support_system/viewmodel/ui_state.dart';
import 'package:physical_treatment_and_health_support_system/core/constants/app_constants.dart';
import 'package:physical_treatment_and_health_support_system/model/business_logic/risk_assessment_service/risk_assessment_service.dart';
import 'package:physical_treatment_and_health_support_system/model/business_logic/recommendation_service/recommendation_service.dart';
import 'package:physical_treatment_and_health_support_system/core/utils/id_utils.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/enums.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/health_profile.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/patient_treatment_plan.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/rehab_info.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/reminder.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/treatment_plan.dart';
import 'package:physical_treatment_and_health_support_system/model/repository/notification_repository/i_notification_repository.dart';
import 'package:physical_treatment_and_health_support_system/model/repository/treatment_repository/i_treatment_repository.dart';
import 'package:physical_treatment_and_health_support_system/model/business_logic/recommendation_service/recommendation.dart';

/// Plan recommendation and selection state (Table 4.50, UC400).
class PlanningViewModel extends BaseViewModel {
  final ITreatmentRepository _repo;
  final RecommendationService _recommender;
  final RiskAssessmentService _riskAssessment;
  final INotificationRepository _notifications;
  final LocalNotificationService? _reminders;

  PlanningViewModel(
    this._repo,
    this._recommender,
    this._riskAssessment,
    this._notifications, [
    this._reminders,
  ]);

  UiState<Recommendation> _recommendation = const Idle();
  UiState<Recommendation> get recommendation => _recommendation;

  UiState<TreatmentPlan> _saving = const Idle();
  UiState<TreatmentPlan> get saving => _saving;

  ProfileSnapshot? _snapshot;

  /// Questionnaire answers of the last request, kept for "Try again".
  RehabInfo? _lastRehab;
  RehabInfo? get lastRehab => _lastRehab;

  /// Profile message to show above the plans, e.g. not configured or stale (UC1000 M1, M3).
  String? _notice;
  String? get notice => _notice;

  /// The plan the patient is already following, if any. Selecting another
  /// plan stops it, so the view asks first.
  PatientTreatmentPlan? _currentPlan;
  PatientTreatmentPlan? get currentPlan => _currentPlan;

  /// The three highest-ranked plans (FR500_07).
  List<TreatmentPlan> get candidates => switch (_recommendation) {
    UiSuccess(:final data) => data.plans,
    _ => const [],
  };

  /// Scores the catalogue against the profile (FR500_02 to FR500_07).
  /// Errors map to UC400 E1 (M3), E2 (M4) and E3 (M5).
  Future<void> recommend(RehabInfo rehab) async {
    _lastRehab = rehab;
    _notice = null;
    _saving = const Idle();
    _recommendation = const Loading();
    notifyListeners();

    final snap = await _riskAssessment.retrieve();
    if (snap is Failure<ProfileSnapshot>) {
      _fail(snap.message);
      return;
    }
    final snapshot = snap.dataOrNull!;
    if (snapshot.status == ProfileStatus.error) {
      _fail(Messages.healthInfoFailed);
      return;
    }
    _snapshot = snapshot;
    final accountId = snapshot.accountId;
    _currentPlan = accountId == null
        ? null
        : (await _repo.getActivePlan(accountId)).dataOrNull;
    _notice = switch (snapshot.status) {
      ProfileStatus.notConfigured ||
      ProfileStatus.incomplete => Messages.profileNotConfigured,
      ProfileStatus.stale => Messages.profileStale,
      _ => null,
    };

    final catalogue = await _repo.getCatalogue();
    if (catalogue is Failure<List<TreatmentPlan>>) {
      _fail(Messages.dbUnavailable);
      return;
    }
    // An empty catalogue (e.g. the seed was never loaded) has nothing to
    // rank: UC400 A1 / M1, instead of sending an invalid request (M4).
    if (catalogue.dataOrNull!.isEmpty) {
      _fail(Messages.conditionNotMet);
      return;
    }

    // Collaborative evidence is optional: a failure (e.g. the RPC is not
    // deployed) just means a cold start, never an error for the patient.
    final outcomes = (await _repo.getPlanOutcomes()).dataOrNull ?? const [];

    final result = await _recommender.topThree(
      snapshot,
      rehab,
      catalogue.dataOrNull!,
      outcomes: outcomes,
    );
    _recommendation = switch (result) {
      Success(:final data) => UiSuccess(data),
      Failure(:final message) => UiError(message),
    };
    notifyListeners();
  }

  /// Runs the last request again after an error (FR500_26 retry).
  Future<void> retry() async {
    final rehab = _lastRehab;
    if (rehab != null) await recommend(rehab);
  }

  void _fail(String message) {
    _recommendation = UiError(message);
    notifyListeners();
  }

  /// Saves the plan with the patient and selection date, then the exercise
  /// reminder built from its weekly frequency (FR500_09, FR500_11).
  Future<bool> select(TreatmentPlan p) async {
    final accountId = _snapshot?.accountId;
    if (accountId == null) {
      _saving = const UiError(Messages.sessionExpired);
      notifyListeners();
      return false;
    }
    _saving = const Loading();
    notifyListeners();

    final assignment = PatientTreatmentPlan(
      patientPlanId: newId(),
      accountId: accountId,
      plan: p,
      suitabilityScore: p.suitabilityScore,
      selectedAt: DateTime.now(),
    );
    final reminder = Reminder(
      reminderId: newId(),
      accountId: accountId,
      patientPlanId: assignment.patientPlanId,
      reminderType: ReminderType.exercise,
      title: 'Time for ${p.planName}',
      hour: AppConstants.defaultReminderHour,
      minute: AppConstants.defaultReminderMinute,
      repeatDays: Reminder.maskForFrequency(p.frequencyPerWeek),
    );

    final previous = (await _repo.getActivePlan(accountId)).dataOrNull;
    final saved = await _repo.assignPlan(assignment);
    final scheduled = saved.isSuccess
        ? await _notifications.saveReminder(reminder)
        : null;
    final ok = saved.isSuccess && (scheduled?.isSuccess ?? false);
    // FR500_11, M600.1: the new plan's reminder goes on the device; the old plan's are removed.
    if (ok) {
      await _reminders?.planSelected(
        reminder,
        previousPatientPlanId: previous?.patientPlanId,
      );
    }
    _saving = ok ? UiSuccess(p) : const UiError(Messages.dbUnavailable);
    notifyListeners();
    return ok;
  }

  /// Clears the recommendation after the patient confirms rejecting all
  /// plans (FR500_12, FR500_13) or exits (FR500_16). Nothing is saved.
  void rejectAll() {
    _recommendation = const Idle();
    _saving = const Idle();
    _notice = null;
    notifyListeners();
  }
}
