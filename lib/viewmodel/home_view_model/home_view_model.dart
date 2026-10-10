import 'package:physical_treatment_and_health_support_system/model/business_logic/plan_rules/plan_rules.dart';
import 'package:physical_treatment_and_health_support_system/viewmodel/base_view_model.dart';
import 'package:physical_treatment_and_health_support_system/model/result.dart';
import 'package:physical_treatment_and_health_support_system/viewmodel/ui_state.dart';
import 'package:physical_treatment_and_health_support_system/core/constants/app_constants.dart';
import 'package:physical_treatment_and_health_support_system/model/business_logic/recommendation_service/recommendation.dart';
import 'package:physical_treatment_and_health_support_system/model/business_logic/risk_assessment_service/risk_assessment_service.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/enums.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/exercise_session.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/health_profile.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/patient_treatment_plan.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/treatment_plan.dart';
import 'package:physical_treatment_and_health_support_system/model/repository/auth_repository/i_auth_repository.dart';
import 'package:physical_treatment_and_health_support_system/model/repository/notification_repository/i_notification_repository.dart';
import 'package:physical_treatment_and_health_support_system/model/repository/treatment_repository/i_treatment_repository.dart';

/// Everything the Home dashboard shows, read once per refresh.
class HomeData {
  final String username;
  final ProfileSnapshot profile;
  final PatientTreatmentPlan? plan;
  final PlanExercise? nextStage;
  final bool doneToday;
  final int unread;

  /// Plans being followed and how many have had their exercise today.
  final int planCount;
  final int plansDoneToday;

  /// A possible fall today in any plan: rest day for every plan.
  final bool restDay;

  /// The followed plans no longer fit the current health profile
  /// (PlanRules.checkActive): the patient reviews them, nothing is stopped.
  final List<PlanIssue> planIssues;

  /// Plans are paused from 65 (Terms of Use, section 2).
  bool get plansPaused => PlanRestriction.forAge(profile.profile?.age) != null;

  const HomeData({
    required this.username,
    required this.profile,
    this.plan,
    this.nextStage,
    this.doneToday = false,
    this.unread = 0,
    this.planCount = 0,
    this.plansDoneToday = 0,
    this.restDay = false,
    this.planIssues = const [],
  });

  RiskLevel get risk => profile.riskLevel;

  /// The profile must be completed before any limit is personalised (UC1000 A1/A2).
  bool get profileNeedsAttention =>
      profile.status == ProfileStatus.notConfigured ||
      profile.status == ProfileStatus.incomplete;

  bool get profileStale => profile.status == ProfileStatus.stale;
}

/// Home dashboard (Figma "Home"): greeting, risk level and active limits, today's
/// session from the treatment plan, the daily diet limits and quick actions.
/// Health score, vitals and meal totals belong to M200/M400/M700 (Jun Ting) and are
/// shown as empty states until those modules provide data.
class HomeViewModel extends BaseViewModel {
  final IAuthRepository _auth;
  final RiskAssessmentService _riskAssessment;
  final ITreatmentRepository _treatments;
  final INotificationRepository? _notifications;
  final DateTime Function() _now;

  HomeViewModel(
    this._auth,
    this._riskAssessment,
    this._treatments, [
    this._notifications,
    DateTime Function()? now,
  ]) : _now = now ?? DateTime.now;

  UiState<HomeData> state = const Idle();

  HomeData? get data => switch (state) {
    UiSuccess(:final data) => data,
    _ => null,
  };

  String greeting() {
    final h = _now().hour;
    // "Good morning" at 00:30 read oddly on the phone (8 Oct): plain "Hello" from midnight to 5 am.
    return h < 5
        ? 'Hello'
        : h < 12
        ? 'Good morning'
        : h < 18
        ? 'Good afternoon'
        : 'Good evening';
  }

  Future<void> load() async {
    if (data == null) {
      state = const Loading();
      notifyListeners();
    }
    final account = (await _auth.currentAccount()).dataOrNull;
    final snapshot = await _riskAssessment.retrieve();
    if (account == null || snapshot is Failure<ProfileSnapshot>) {
      state = const UiError(Messages.sessionExpired);
      notifyListeners();
      return;
    }
    final profile = snapshot.dataOrNull!;

    // A missing plan or an unreachable database still shows the rest of the dashboard.
    final plans =
        (await _treatments.getActivePlans(account.accountId)).dataOrNull ??
        const <PatientTreatmentPlan>[];
    final today = _now();
    final done = <String, bool>{};
    var restDay = false;
    for (final a in plans) {
      final sessions =
          (await _treatments.getSessions(a.patientPlanId)).dataOrNull ??
          const <ExerciseSession>[];
      done[a.patientPlanId] = ExerciseSession.anyCompletedOn(sessions, today);
      restDay =
          restDay ||
          sessions.any(
            (s) =>
                s.completedOn(today) &&
                (s.postureFeedback ?? '').contains(_fallPhrase),
          );
    }
    // The card shows the first plan that still has an exercise today.
    final plan =
        plans
            .where(
              (a) => done[a.patientPlanId] != true && a.currentStage() != null,
            )
            .firstOrNull ??
        plans.firstOrNull;
    final doneToday =
        restDay || (plan != null && (done[plan.patientPlanId] ?? false));
    final planIssues = PlanRules.checkActive(
      active: plans,
      risk: profile.riskLevel,
      limit: profile.safetyLimit,
    );
    final unread =
        (await _notifications?.unreadCount(account.accountId))?.dataOrNull ?? 0;

    state = UiSuccess(
      HomeData(
        username: account.username,
        profile: profile,
        plan: plan,
        nextStage: plan?.currentStage(),
        doneToday: doneToday,
        unread: unread,
        planCount: plans.length,
        plansDoneToday: done.values.where((d) => d).length,
        restDay: restDay,
        planIssues: planIssues,
      ),
    );
    notifyListeners();
  }

  /// Phrase of the server's possible-fall message, found in saved feedback
  /// (the same check as TreatmentViewModel.restDayToday).
  static const _fallPhrase = 'lost your balance or fallen';

  /// "3 exercises · 12 min · Both legs" for the Today's session card.
  static String sessionSummary(
    TreatmentPlan p,
    String Function(String) areaLabel,
  ) {
    final n = p.exercises.length;
    final minutes = (p.totalDurationSec / 60).ceil();
    return '$n exercise${n == 1 ? '' : 's'} · $minutes min · ${areaLabel(p.targetBodyArea)}';
  }

  /// "Medium risk · limits active" (Figma), or what the patient should do first.
  static String riskPill(HomeData d) {
    if (d.profileNeedsAttention) return 'Complete your profile';
    if (d.profile.status == ProfileStatus.error) {
      return 'Safe default limits active';
    }
    return '${d.risk.db} risk · limits active';
  }

  /// Name shown in the header: the username as the patient typed it.
  static String displayName(String username) =>
      username.trim().isEmpty ? 'there' : username.trim();
}
