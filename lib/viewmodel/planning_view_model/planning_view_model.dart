import 'package:physical_treatment_and_health_support_system/model/business_logic/local_notification_service/local_notification_service.dart';
import 'package:physical_treatment_and_health_support_system/viewmodel/base_view_model.dart';
import 'package:physical_treatment_and_health_support_system/model/business_logic/plan_rules/plan_rules.dart';
import 'package:physical_treatment_and_health_support_system/model/result.dart';
import 'package:physical_treatment_and_health_support_system/viewmodel/ui_state.dart';
import 'package:physical_treatment_and_health_support_system/core/constants/app_constants.dart';
import 'package:physical_treatment_and_health_support_system/model/business_logic/risk_assessment_service/risk_assessment_service.dart';
import 'package:physical_treatment_and_health_support_system/model/business_logic/recommendation_service/recommendation_service.dart';
import 'package:physical_treatment_and_health_support_system/core/utils/id_utils.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/enums.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/exercise_session.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/health_profile.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/lookups.dart';
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

  /// The profile age of the last request, for the age-limit page.
  int? get age => _snapshot?.profile?.age;

  /// The conditions waiting for a doctor's OK (PlanRestriction.clearanceNeeded).
  List<HealthCondition> get conditionsNeedingClearance => [
    for (final c in _snapshot?.profile?.conditions ?? const <HealthCondition>[])
      if (c.blocksPlans) c,
  ];

  /// Whether plans may be generated for the patient, from the profile age
  /// (Terms of Use, section 2: none from 65). Checked before the
  /// questionnaire so a restricted patient is not asked for nothing; a
  /// failure to read the profile is not a restriction (the request then
  /// reports it).
  Future<PlanRestriction?> checkRestriction() async {
    final snap = await _riskAssessment.retrieve();
    if (snap case Success(:final data)) {
      _snapshot = data;
      return PlanRestriction.forProfile(data.profile);
    }
    return null;
  }

  /// Questionnaire answers of the last request, kept for "Try again".
  RehabInfo? _lastRehab;
  RehabInfo? get lastRehab => _lastRehab;

  /// Profile message to show above the plans, e.g. not configured or stale (UC1000 M1, M3).
  String? _notice;
  String? get notice => _notice;

  /// Plans the patient is already following. Several can run at once within
  /// PlanRules; the view shows each plan's checks before Select.
  List<PatientTreatmentPlan> _activePlans = const [];
  List<PatientTreatmentPlan> get activePlans => _activePlans;

  /// Shown when the database still allows only one ACTIVE plan (unique index,
  /// Postgres 23505) - until supabase/proposed/..._multiple_active_plans.sql
  /// is applied.
  static const multiPlanNotEnabled =
      'Following more than one plan at a time is not switched on yet. You can '
      'replace your current plan instead.';

  /// The plan this recommendation moves on from ("Find my next plan"), or
  /// null after the questionnaire.
  PatientTreatmentPlan? _from;
  PatientTreatmentPlan? get from => _from;

  /// After an EASE step from a plan that is still being followed, that plan:
  /// the chosen plan replaces it. The patient still confirms it in the dialog.
  String? get easingFrom {
    final f = _from;
    final r = _recommendation;
    if (f == null ||
        r is! UiSuccess<Recommendation> ||
        r.data.nextStep != NextStep.ease) {
      return null;
    }
    return _activePlans.any((a) => a.patientPlanId == f.patientPlanId)
        ? f.patientPlanId
        : null;
  }

  /// Checks for adding [p] beside the plans already followed, under the
  /// CURRENT risk level and safety limit (PlanRules.checkAdd). A plan being
  /// eased is left out: the new plan replaces it.
  List<PlanIssue> issuesFor(TreatmentPlan p) {
    final s = _snapshot;
    if (s == null) return const [];
    final easing = easingFrom;
    return PlanRules.checkAdd(
      candidate: p,
      active: [
        for (final a in _activePlans)
          if (a.patientPlanId != easing) a,
      ],
      risk: s.riskLevel,
      limit: s.safetyLimit,
    );
  }

  /// The three highest-ranked plans (FR500_07).
  List<TreatmentPlan> get candidates => switch (_recommendation) {
    UiSuccess(:final data) => data.plans,
    _ => const [],
  };

  /// Scores the catalogue against the profile (FR500_02 to FR500_07).
  /// Errors map to UC400 E1 (M3), E2 (M4) and E3 (M5).
  Future<void> recommend(RehabInfo rehab) {
    _from = null;
    return _run(rehab);
  }

  /// "Find my next plan" (hybrid-3.0): the questionnaire answered with the
  /// plan the patient is moving on from, so the server's next step applies to
  /// it (a step up after a completed plan, an easier plan after repeated
  /// attempts that did not pass).
  Future<void> recommendNext(PatientTreatmentPlan from) {
    _from = from;
    final p = from.plan;
    return _run(
      RehabInfo(
        affectedBodyArea: p.targetBodyArea,
        recoveryStage: p.recoveryStage,
        mobilityLevel: p.mobilityLevel,
        goal: p.goal ?? RehabInfo.goals.first,
      ),
    );
  }

  /// The patient's own plans and attempts (hybrid-3.0). Optional like the
  /// cohort evidence: a failure means no history, never an error.
  Future<PatientProgress?> _progress(String accountId) async {
    final plans = (await _repo.getPlanHistory(accountId)).dataOrNull;
    if (plans == null || plans.isEmpty) return null;
    return (
      plans: plans,
      sessions: {
        for (final p in plans)
          p.patientPlanId:
              (await _repo.getSessions(p.patientPlanId)).dataOrNull ??
              const <ExerciseSession>[],
      },
    );
  }

  Future<void> _run(RehabInfo rehab) async {
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
    // No plan from 65, also for "Find my next plan" (Terms of Use, section 2).
    if (PlanRestriction.forProfile(snapshot.profile) case final r?) {
      _recommendation = UiSuccess(Recommendation.restricted(r));
      notifyListeners();
      return;
    }
    final accountId = snapshot.accountId;
    _activePlans = accountId == null
        ? const []
        : (await _repo.getActivePlans(accountId)).dataOrNull ?? const [];
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
    final progress = accountId == null ? null : await _progress(accountId);

    final result = await _recommender.topThree(
      snapshot,
      rehab,
      catalogue.dataOrNull!,
      outcomes: outcomes,
      progress: progress,
      nextFromPlanId: _from?.plan.planId,
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
    if (rehab != null) await _run(rehab);
  }

  void _fail(String message) {
    _recommendation = UiError(message);
    notifyListeners();
  }

  /// Saves [p] with the patient and selection date (FR500_09), then the exercise reminder built
  /// from its weekly frequency (FR500_11). [replacing] are the patientPlanIds the patient chose
  /// to stop for it (a clash or the risk cap); every other active plan keeps running.
  Future<bool> select(
    TreatmentPlan p, {
    List<String> replacing = const [],
  }) async {
    // Two taps before the screen disables the button would assign the plan twice (23 Oct).
    if (_saving is Loading) return false;
    final accountId = _snapshot?.accountId;
    if (accountId == null) {
      _saving = const UiError(Messages.sessionExpired);
      notifyListeners();
      return false;
    }
    _saving = const Loading();
    notifyListeners();

    final kept = _activePlans
        .where((a) => !replacing.contains(a.patientPlanId))
        .length;
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
      // One hour later per plan that keeps running, so reminders of
      // different plans do not ring at the same time.
      hour: (AppConstants.defaultReminderHour + kept).clamp(0, 20),
      minute: AppConstants.defaultReminderMinute,
      repeatDays: Reminder.maskForFrequency(p.frequencyPerWeek),
    );

    final saved = await _repo.assignPlan(assignment, replacing: replacing);
    if (saved is Failure<void>) {
      _saving = UiError(
        saved.code == '23505' ? multiPlanNotEnabled : Messages.dbUnavailable,
      );
      notifyListeners();
      return false;
    }
    // The plan is assigned (and the replaced ones ended) from here on, even if its reminder
    // fails: reporting a failure made the patient select it again and follow it twice
    // (audit, 23 Oct).
    // FR500_11, M600.1: the new plan's reminder goes on the device; only the
    // replaced plans' reminders are removed.
    for (final id in replacing) {
      await _reminders?.removeForPlan(accountId, id);
    }
    final scheduled = await _notifications.saveReminder(reminder);
    if (scheduled.isSuccess) await _reminders?.planSelected(reminder);
    reminderNotSet = !scheduled.isSuccess;
    // The followed plans change only now, with the success: while the reminder was being set
    // (seconds on the emulator) a redraw showed the selected card as "You are already following
    // this plan" (emulator, 24 Oct).
    _activePlans = [
      for (final a in _activePlans)
        if (!replacing.contains(a.patientPlanId)) a,
      assignment,
    ];
    _saving = UiSuccess(p);
    notifyListeners();
    return true;
  }

  /// The last selected plan was saved but its reminder was not.
  bool reminderNotSet = false;

  /// Clears the recommendation after the patient confirms rejecting all
  /// plans (FR500_12, FR500_13) or exits (FR500_16). Nothing is saved.
  void rejectAll() {
    _recommendation = const Idle();
    _saving = const Idle();
    _notice = null;
    notifyListeners();
  }
}
