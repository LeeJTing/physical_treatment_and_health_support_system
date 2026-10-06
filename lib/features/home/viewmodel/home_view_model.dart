import 'package:physical_treatment_and_health_support_system/core/base/base_view_model.dart';
import 'package:physical_treatment_and_health_support_system/core/base/result.dart';
import 'package:physical_treatment_and_health_support_system/core/base/ui_state.dart';
import 'package:physical_treatment_and_health_support_system/core/constants/app_constants.dart';
import 'package:physical_treatment_and_health_support_system/core/services/profile_info_service.dart';
import 'package:physical_treatment_and_health_support_system/data/models/enums.dart';
import 'package:physical_treatment_and_health_support_system/data/models/exercise_session.dart';
import 'package:physical_treatment_and_health_support_system/data/models/health_profile.dart';
import 'package:physical_treatment_and_health_support_system/data/models/patient_treatment_plan.dart';
import 'package:physical_treatment_and_health_support_system/data/models/treatment_plan.dart';
import 'package:physical_treatment_and_health_support_system/data/repository/interfaces/i_auth_repository.dart';
import 'package:physical_treatment_and_health_support_system/data/repository/interfaces/i_notification_repository.dart';
import 'package:physical_treatment_and_health_support_system/data/repository/interfaces/i_treatment_repository.dart';

/// Everything the Home dashboard shows, read once per refresh.
class HomeData {
  final String username;
  final ProfileSnapshot profile;
  final PatientTreatmentPlan? plan;
  final PlanExercise? nextStage;
  final bool doneToday;
  final int unread;

  const HomeData({
    required this.username,
    required this.profile,
    this.plan,
    this.nextStage,
    this.doneToday = false,
    this.unread = 0,
  });

  RiskLevel get risk => profile.riskLevel;

  /// The profile must be completed before any limit is personalised (UC1000 A1/A2).
  bool get profileNeedsAttention =>
      profile.status == ProfileStatus.notConfigured || profile.status == ProfileStatus.incomplete;

  bool get profileStale => profile.status == ProfileStatus.stale;
}

/// Home dashboard (Figma "Home"): greeting, risk level and active limits, today's
/// session from the treatment plan, the daily diet limits and quick actions.
/// Health score, vitals and meal totals belong to M200/M400/M700 (Jun Ting) and are
/// shown as empty states until those modules provide data.
class HomeViewModel extends BaseViewModel {
  final IAuthRepository _auth;
  final ProfileInfoService _profileInfo;
  final ITreatmentRepository _treatments;
  final INotificationRepository? _notifications;
  final DateTime Function() _now;

  HomeViewModel(this._auth, this._profileInfo, this._treatments, [this._notifications, DateTime Function()? now])
      : _now = now ?? DateTime.now;

  UiState<HomeData> state = const Idle();

  HomeData? get data => switch (state) { UiSuccess(:final data) => data, _ => null };

  String greeting() {
    final h = _now().hour;
    return h < 12
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
    final snapshot = await _profileInfo.retrieve();
    if (account == null || snapshot is Failure<ProfileSnapshot>) {
      state = const UiError(Messages.sessionExpired);
      notifyListeners();
      return;
    }
    final profile = snapshot.dataOrNull!;

    // A missing plan or an unreachable database still shows the rest of the dashboard.
    final plan = (await _treatments.getActivePlan(account.accountId)).dataOrNull;
    var doneToday = false;
    if (plan != null) {
      final sessions = (await _treatments.getSessions(plan.patientPlanId)).dataOrNull ?? const <ExerciseSession>[];
      final now = _now();
      doneToday = sessions.any((s) =>
          s.isCompleted() &&
          s.completedAt != null &&
          s.completedAt!.toLocal().year == now.year &&
          s.completedAt!.toLocal().month == now.month &&
          s.completedAt!.toLocal().day == now.day);
    }
    final unread = (await _notifications?.unreadCount(account.accountId))?.dataOrNull ?? 0;

    state = UiSuccess(HomeData(
      username: account.username,
      profile: profile,
      plan: plan,
      nextStage: plan?.currentStage(),
      doneToday: doneToday,
      unread: unread,
    ));
    notifyListeners();
  }

  /// "3 exercises · 12 min · Both legs" for the Today's session card.
  static String sessionSummary(TreatmentPlan p, String Function(String) areaLabel) {
    final n = p.exercises.length;
    final minutes = (p.totalDurationSec / 60).ceil();
    return '$n exercise${n == 1 ? '' : 's'} · $minutes min · ${areaLabel(p.targetBodyArea)}';
  }

  /// "Medium risk · limits active" (Figma), or what the patient should do first.
  static String riskPill(HomeData d) {
    if (d.profileNeedsAttention) return 'Complete your profile';
    if (d.profile.status == ProfileStatus.error) return 'Safe default limits active';
    return '${d.risk.db} risk · limits active';
  }

  /// Name shown in the header: the username as the patient typed it.
  static String displayName(String username) => username.trim().isEmpty ? 'there' : username.trim();
}
