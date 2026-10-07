import 'dart:io';

import 'package:physical_treatment_and_health_support_system/model/business_logic/local_notification_service/local_notification_service.dart';
import 'package:physical_treatment_and_health_support_system/viewmodel/base_view_model.dart';
import 'package:physical_treatment_and_health_support_system/model/result.dart';
import 'package:physical_treatment_and_health_support_system/viewmodel/ui_state.dart';
import 'package:physical_treatment_and_health_support_system/core/constants/app_constants.dart';
import 'package:physical_treatment_and_health_support_system/model/business_logic/pose_estimation_service/pose_estimation_service.dart';
import 'package:physical_treatment_and_health_support_system/core/utils/id_utils.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/enums.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/exercise.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/exercise_session.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/patient_treatment_plan.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/reminder.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/treatment_plan.dart';
import 'package:physical_treatment_and_health_support_system/model/repository/auth_repository/i_auth_repository.dart';
import 'package:physical_treatment_and_health_support_system/model/repository/notification_repository/i_notification_repository.dart';
import 'package:physical_treatment_and_health_support_system/model/repository/treatment_repository/i_treatment_repository.dart';

/// Where an exercise stands in the pathway (FR300_02).
enum StageStatus { done, attempted, current, upcoming }

class PathwayStage {
  final PlanExercise item;
  final StageStatus status;
  final double? bestAccuracy; // best posture score so far, if attempted
  const PathwayStage(this.item, this.status, this.bestAccuracy);
}

/// Pathway progress, video capture and the posture result (Table 4.52).
/// One row of the session history: the attempt and the name of its exercise.
class SessionHistoryEntry {
  final ExerciseSession session;
  final String exerciseName;
  const SessionHistoryEntry(this.session, this.exerciseName);
}

class TreatmentViewModel extends BaseViewModel {
  final ITreatmentRepository _repo;
  final PoseEstimationService _pose;
  final IAuthRepository _auth;
  final INotificationRepository? _notifications;
  final LocalNotificationService? _reminders;

  TreatmentViewModel(
    this._repo,
    this._pose,
    this._auth, [
    this._notifications,
    this._reminders,
  ]);

  /// The next exercise reminder for the active plan, for the Treatment screen card.
  DateTime? _nextReminderAt;
  DateTime? get nextReminderAt => _nextReminderAt;

  UiState<PatientTreatmentPlan?> _plan = const Idle();
  UiState<PatientTreatmentPlan?> get plan => _plan;

  /// The plan being followed.
  PatientTreatmentPlan? get activePlan =>
      _plan is UiSuccess<PatientTreatmentPlan?>
      ? (_plan as UiSuccess<PatientTreatmentPlan?>).data
      : null;

  List<ExerciseSession> _sessions = const [];
  List<ExerciseSession> get sessions => _sessions;

  /// The exercise being recorded.
  Exercise? _current;
  Exercise? get current => _current;
  PlanExercise? get currentItem => activePlan?.plan
      .orderedExercises()
      .where((pe) => pe.exercise.exerciseId == _current?.exerciseId)
      .firstOrNull;

  /// The clip being analysed, kept so "Retry" goes back to the recorder (FR300_20).
  UiState<PostureResult> _analysis = const Idle();
  UiState<PostureResult> get analysis => _analysis;

  /// Most recent attempt and its posture score (Table 4.52).
  ExerciseSession? _lastResult;
  ExerciseSession? get lastResult => _lastResult;

  /// True once a passing result has advanced the pathway automatically.
  bool _autoAdvanced = false;
  bool get autoAdvanced => _autoAdvanced;

  DateTime? _recordedAt;
  int? _clipSeconds;

  /// Reads the assigned plan and its pathway (FR300_01, FR300_02).
  Future<void> loadPlan() async {
    _plan = const Loading();
    notifyListeners();
    final account = (await _auth.currentAccount()).dataOrNull;
    if (account == null) {
      _plan = const UiError(Messages.sessionExpired);
      notifyListeners();
      return;
    }
    final res = await _repo.getActivePlan(account.accountId);
    if (res case Success(:final data)) {
      _plan = UiSuccess(data);
      _sessions = data == null
          ? const []
          : ((await _repo.getSessions(data.patientPlanId)).dataOrNull ??
                const []);
      _nextReminderAt = null;
      await _reminders?.sync(
        account.accountId,
      ); // refresh the device schedule (M600.1)
      if (data != null && _notifications != null) {
        final reminders =
            (await _notifications.getReminders(account.accountId)).dataOrNull ??
            const <Reminder>[];
        final times = [
          for (final r in reminders)
            if (r.patientPlanId == data.patientPlanId) r.nextOccurrence(),
        ].whereType<DateTime>().toList()..sort();
        _nextReminderAt = times.isEmpty ? null : times.first;
      }
    } else {
      _plan = const UiError(Messages.planRetrieveFailed); // FR300_22
    }
    notifyListeners();
  }

  /// The pathway with completed, current and upcoming exercises (FR300_02).
  List<PathwayStage> get pathway {
    final p = activePlan;
    if (p == null) return const [];
    final ordered = p.plan.orderedExercises();
    return [
      for (var i = 0; i < ordered.length; i++)
        PathwayStage(
          ordered[i],
          i < p.completedStages
              ? StageStatus.done
              : i == p.completedStages
              ? (_best(ordered[i].exerciseId) != null
                    ? StageStatus.attempted
                    : StageStatus.current)
              : StageStatus.upcoming,
          _best(ordered[i].exerciseId),
        ),
    ];
  }

  double? _best(String exerciseId) {
    final scores = [
      for (final s in _sessions)
        if (s.exerciseId == exerciseId && s.postureAccuracy != null)
          s.postureAccuracy!,
    ];
    return scores.isEmpty ? null : scores.reduce((a, b) => a > b ? a : b);
  }

  /// Every recorded attempt of the active plan, newest first, with its exercise name
  /// (Session history screen; FR300_10 results kept per session).
  List<SessionHistoryEntry> get history {
    final p = activePlan;
    if (p == null) return const [];
    final names = {
      for (final e in p.plan.exercises) e.exerciseId: e.exercise.exerciseName,
    };
    final list = [
      for (final s in _sessions)
        SessionHistoryEntry(s, names[s.exerciseId] ?? 'Exercise'),
    ];
    // Unfinished attempts have no completion time; they sort last.
    list.sort(
      (a, b) => (b.session.completedAt ?? DateTime(0)).compareTo(
        a.session.completedAt ?? DateTime(0),
      ),
    );
    return list;
  }

  List<double> get _scores => [
    for (final s in _sessions)
      if (s.postureAccuracy != null) s.postureAccuracy!,
  ];

  double? get averageAccuracy {
    final xs = _scores;
    return xs.isEmpty ? null : xs.reduce((a, b) => a + b) / xs.length;
  }

  double? get bestAccuracy {
    final xs = _scores;
    return xs.isEmpty ? null : xs.reduce((a, b) => a > b ? a : b);
  }

  int get completedSessionCount =>
      _sessions.where((s) => s.isCompleted()).length;

  /// Opens the recorder with the recording instructions (FR300_05).
  Future<void> startExercise(Exercise e) async {
    _current = e;
    _analysis = const Idle();
    _autoAdvanced = false;
    notifyListeners();
  }

  /// Validates the clip on the device, then runs pose estimation (FR300_14 to FR300_17).
  /// Returns the attempt; its accuracy is null when the clip could not be analysed.
  Future<ExerciseSession?> submitVideo(File v, {int? clipSeconds}) async {
    final e = _current;
    final p = activePlan;
    if (e == null || p == null) return null;
    _recordedAt = DateTime.now();
    _clipSeconds = clipSeconds;
    _analysis = const Loading();
    notifyListeners();

    final check = await _pose.validateVideo(v);
    if (!check.ok) {
      _analysis = UiError(check.message ?? Messages.videoInvalid);
      notifyListeners();
      return null;
    }
    final res = await _pose.analyse(v, e);
    switch (res) {
      case Failure(:final message):
        _analysis = UiError(message);
        notifyListeners();
        return null;
      case Success(:final data):
        _analysis = UiSuccess(data);
        _lastResult = _session(p, e, data, CompletionStatus.completed);
        notifyListeners();
        // UI Design, Posture Result Screen: 80% or more updates the progress automatically.
        if (data.isPassing) await acceptResult();
        return _lastResult;
    }
  }

  ExerciseSession _session(
    PatientTreatmentPlan p,
    Exercise e,
    PostureResult r,
    CompletionStatus status,
  ) => ExerciseSession(
    sessionId: newId(),
    accountId: p.accountId,
    patientPlanId: p.patientPlanId,
    exerciseId: e.exerciseId,
    completedAt: status == CompletionStatus.completed
        ? (_recordedAt ?? DateTime.now())
        : null,
    durationSec: _clipSeconds,
    repetitionsCompleted: r.repetitions,
    completionStatus: status,
    postureAccuracy: r.accuracy,
    postureFeedback: r.feedback.join('\n'),
    modelVersion: r.modelVersion,
  );

  UiState<void> _saving = const Idle();
  UiState<void> get saving => _saving;

  /// Records the attempt and advances the pathway (FR300_11, FR300_21). Advancing only
  /// happens when the attempt is for the current stage, so repeating a finished exercise
  /// does not skip ahead.
  Future<bool> acceptResult() async {
    final p = activePlan;
    final s = _lastResult;
    if (p == null || s == null) return false;
    if (_saving is UiSuccess) {
      return true; // already saved (passing result, or Continue tapped twice)
    }
    if (_saving is Loading) return false;
    _saving = const Loading();
    notifyListeners();
    final isCurrentStage = p.currentExercise()?.exerciseId == s.exerciseId;
    final advanced = isCurrentStage ? p.advance() : null;
    final res = await _repo.saveSession(s, advancedPlan: advanced);
    if (res.isSuccess) {
      _sessions = [..._sessions, s];
      if (advanced != null) _plan = UiSuccess(advanced);
      // FR300_12, FR600_005: today's exercise reminder is no longer needed.
      await _reminders?.exerciseDone(p.accountId, p.patientPlanId);
      _autoAdvanced = s.postureIsPassing();
      _saving = const UiSuccess(null);
    } else {
      _saving = const UiError(Messages.progressSaveFailed); // FR300_27
    }
    notifyListeners();
    return res.isSuccess;
  }

  /// Back to the recorder (FR300_20). The attempt is kept as RETRIED.
  Future<void> retry() async {
    final p = activePlan;
    final s = _lastResult;
    if (p != null &&
        s != null &&
        !s.postureIsPassing() &&
        _saving is! UiSuccess) {
      final retried = s.withStatus(CompletionStatus.retried);
      if ((await _repo.saveSession(retried)).isSuccess) {
        _sessions = [..._sessions, retried];
      }
    }
    _analysis = const Idle();
    _lastResult = null;
    _saving = const Idle();
    _autoAdvanced = false;
    notifyListeners();
  }

  /// Stops the plan (UI Design, Physical Treatment Page: delete the treatment plan).
  Future<bool> endPlan() async {
    final p = activePlan;
    if (p == null) return false;
    final ok = (await _repo.endPlan(p)).isSuccess;
    if (ok) {
      _plan = const UiSuccess(null);
      _sessions = const [];
      notifyListeners();
    }
    return ok;
  }
}
