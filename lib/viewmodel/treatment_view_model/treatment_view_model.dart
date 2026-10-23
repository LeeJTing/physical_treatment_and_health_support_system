import 'dart:io';

import 'package:physical_treatment_and_health_support_system/model/business_logic/local_notification_service/local_notification_service.dart';
import 'package:physical_treatment_and_health_support_system/viewmodel/base_view_model.dart';
import 'package:physical_treatment_and_health_support_system/model/result.dart';
import 'package:physical_treatment_and_health_support_system/viewmodel/ui_state.dart';
import 'package:physical_treatment_and_health_support_system/core/constants/app_constants.dart';
import 'package:physical_treatment_and_health_support_system/model/business_logic/pose_estimation_service/pose_estimation_service.dart';
import 'package:physical_treatment_and_health_support_system/model/business_logic/recommendation_service/recommendation_service.dart';
import 'package:physical_treatment_and_health_support_system/model/business_logic/recommendation_service/recommendation.dart';
import 'package:physical_treatment_and_health_support_system/model/business_logic/risk_assessment_service/risk_assessment_service.dart';
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
  final RiskAssessmentService? _risk;

  TreatmentViewModel(
    this._repo,
    this._pose,
    this._auth, [
    this._notifications,
    this._reminders,
    this._risk,
  ]);

  /// Risk level and age from the health profile, so the server can lower the range-of-motion
  /// targets for older or high-risk patients. Nulls (full targets) when there is no profile.
  Future<(String?, int?)> _patientContext() async {
    final r = _risk;
    if (r == null) return (null, null);
    final profile = (await r.retrieve()).dataOrNull?.profile;
    if (profile == null) return (null, null);
    final risk = switch (profile.assignRiskLevel()) {
      RiskLevel.low => 'LOW',
      RiskLevel.medium => 'MODERATE',
      RiskLevel.high => 'HIGH',
    };
    return (risk, profile.age);
  }

  /// Plans are paused from 65 (Terms of Use, section 2): nothing can be
  /// started, the progress is kept and the exercise reminders stop ringing.
  PlanRestriction? _restriction;
  PlanRestriction? get restriction => _restriction;

  /// The profile age, for the age-limit page.
  int? _age;
  int? get age => _age;

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

  /// Every plan being followed; [plan] / [activePlan] is the one on screen.
  List<PatientTreatmentPlan> _plans = const [];
  List<PatientTreatmentPlan> get plans => _plans;

  /// The most recently completed plan, for "Find my next plan" when no plan
  /// is being followed (hybrid-3.0).
  PatientTreatmentPlan? _lastCompleted;
  PatientTreatmentPlan? get lastCompleted => _lastCompleted;

  /// Every exercise of the plan on screen is done.
  bool get planComplete {
    final p = activePlan;
    return p != null &&
        p.plan.exercises.isNotEmpty &&
        p.currentExercise() == null;
  }

  /// Attempts at the current exercise that did not pass.
  int get failsAtCurrent {
    final p = activePlan;
    return p == null ? 0 : RecommendationService.failsAtCurrent(p, _sessions);
  }

  /// The current exercise did not pass several times: offer plans that may
  /// suit better (the server's EASE step).
  bool get suggestEasier =>
      _restriction == null &&
      !planComplete &&
      failsAtCurrent >= RecommendationService.easeAfterFails;

  /// Sessions of every active plan (for the shared-exercise and rest-day rules).
  Map<String, List<ExerciseSession>> _sessionsByPlan = const {};

  /// Date a possible fall was seen in this app session (until it is saved).
  DateTime? _fallSeenOn;

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
    final risk = _risk;
    _age = risk == null
        ? null
        : (await risk.retrieve()).dataOrNull?.profile?.age;
    _restriction = PlanRestriction.forAge(_age);
    final res = await _repo.getActivePlans(account.accountId);
    if (res case Success(data: final all)) {
      _plans = all;
      _lastCompleted =
          ((await _repo.getPlanHistory(account.accountId)).dataOrNull ??
                  const <PatientTreatmentPlan>[])
              .where((p) => p.status == PlanStatus.completed)
              .lastOrNull;
      _sessionsByPlan = {
        for (final a in all)
          a.patientPlanId:
              (await _repo.getSessions(a.patientPlanId)).dataOrNull ??
              const <ExerciseSession>[],
      };
      final keep = activePlan?.patientPlanId ?? _preferredPlanId;
      final data =
          all.where((a) => a.patientPlanId == keep).firstOrNull ??
          all.lastOrNull;
      // FR300_23: the exercises come with the plan; a plan without them could not be read.
      _plan = data != null && data.plan.exercises.isEmpty
          ? const UiError(Messages.exerciseRetrieveFailed)
          : UiSuccess(data);
      _sessions = data == null
          ? const []
          : _sessionsByPlan[data.patientPlanId] ?? const [];
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

  String? _preferredPlanId;

  /// The plan to show first, e.g. the one a tapped reminder is about.
  void preferPlan(String? patientPlanId) => _preferredPlanId = patientPlanId;

  /// Shows another of the active plans (its pathway, sessions and lock).
  void selectPlan(String patientPlanId) {
    final next = _plans.where((a) => a.patientPlanId == patientPlanId);
    if (next.isEmpty) return;
    _plan = UiSuccess(next.first);
    _sessions = _sessionsByPlan[patientPlanId] ?? const [];
    _analysis = const Idle();
    _lastResult = null;
    _saving = const Idle();
    notifyListeners();
  }

  /// A possible fall today in ANY plan makes today a rest day for all plans.
  bool get restDayToday {
    final today = clock();
    final f = _fallSeenOn;
    if (f != null &&
        f.year == today.year &&
        f.month == today.month &&
        f.day == today.day) {
      return true;
    }
    return _sessionsByPlan.values.any(
      (list) => list.any(
        (s) => s.completedOn(today) && s.hadFallAlert(),
      ),
    );
  }

  /// Shown on every pathway after a possible fall today.
  static const restAfterFall =
      'Rest now and try your exercises another day. If you are hurt, dizzy '
      'or cannot get up, call for help or 999.';

  /// Clock for the one-exercise-per-day rule; replaced in tests.
  DateTime Function() clock = DateTime.now;

  /// Shown on the pathway once today's exercise is done.
  static const nextUnlocksTomorrow =
      "Today's exercise is done. Your next exercise unlocks tomorrow.";

  /// One exercise per day: a COMPLETED attempt was saved today (the shared
  /// ExerciseSession rule that Home and the reminder also use).
  bool get doneToday => ExerciseSession.anyCompletedOn(_sessions, clock());

  /// Whether [exerciseId] may be started now. Before today's exercise is done,
  /// anything the pathway offers; afterwards only today's own exercise, and
  /// only when today's attempt at it did not pass (a retry).
  bool canStart(String exerciseId) {
    if (_restriction != null || restDayToday) return false;
    if (!doneToday) return true;
    final today = [
      for (final s in _sessions)
        if (s.exerciseId == exerciseId && s.completedOn(clock())) s,
    ];
    return today.isNotEmpty && !today.any((s) => s.postureIsPassing());
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

  /// Testing mode (20 Oct): the exercise being tested has no plan, no
  /// one-exercise-per-day rule or rest day, full movement targets, and nothing
  /// is saved (TestModeViewModel turns the mode on).
  bool _testing = false;
  bool get testing => _testing;

  /// Every exercise of the catalogue, for testing mode.
  UiState<List<Exercise>> _testExercises = const Idle();
  UiState<List<Exercise>> get testExercises => _testExercises;

  Future<void> loadTestExercises() async {
    _testExercises = const Loading();
    notifyListeners();
    final res = await _repo.getCatalogue();
    if (res case Success(data: final plans)) {
      final seen = <String>{};
      final all = [
        for (final p in plans)
          for (final pe in p.orderedExercises())
            if (seen.add(pe.exercise.exerciseId)) pe.exercise,
      ]..sort((a, b) => a.exerciseName.compareTo(b.exerciseName));
      _testExercises = UiSuccess(all);
    } else {
      _testExercises = const UiError(Messages.exerciseRetrieveFailed);
    }
    notifyListeners();
  }

  /// Opens the recorder for [e] in testing mode.
  void startTest(Exercise e) {
    _attempt++;
    _testing = true;
    _current = e;
    _analysis = const Idle();
    _lastResult = null;
    _saving = const Idle();
    _autoAdvanced = false;
    notifyListeners();
  }

  /// Opens the recorder with the recording instructions (FR300_05).
  Future<void> startExercise(Exercise e) async {
    _attempt++;
    _testing = false;
    _current = e;
    _analysis = const Idle();
    // The last exercise's result and its "saved" state must not carry over (audit, 23 Oct):
    // acceptResult saw _saving as already saved and skipped saving the next attempt, e.g. a
    // second plan's exercise started after Continue on the first.
    _lastResult = null;
    _saving = const Idle();
    _autoAdvanced = false;
    notifyListeners();
  }

  /// Bumped by every start and exit, so a /pose reply that arrives after the patient left
  /// is dropped instead of saved.
  int _attempt = 0;

  /// "Exit" (FR300_13): the exercise in progress is cancelled. A clip still being analysed is
  /// not saved; an attempt already saved (a passing result) stays saved.
  void cancelExercise() {
    _attempt++;
    _testing = false;
    _current = null;
    _analysis = const Idle();
    _lastResult = null;
    _saving = const Idle();
    _autoAdvanced = false;
    notifyListeners();
  }

  /// Validates the clip on the device, then runs pose estimation (FR300_14 to FR300_17).
  /// Returns the attempt; its accuracy is null when the clip could not be analysed.
  Future<ExerciseSession?> submitVideo(File v, {int? clipSeconds}) async {
    final e = _current;
    final p = activePlan;
    if (e == null || (p == null && !_testing)) return null;
    final attempt = _attempt;
    _recordedAt = DateTime.now();
    _clipSeconds = clipSeconds;
    _analysis = const Loading();
    notifyListeners();

    final check = await _pose.validateVideo(v);
    if (attempt != _attempt) return null; // exited (FR300_13)
    if (!check.ok) {
      _analysis = UiError(check.message ?? Messages.videoInvalid);
      notifyListeners();
      return null;
    }
    // Testing mode checks against the full targets (no lowering for age or risk).
    final (riskLevel, age) = _testing ? (null, null) : await _patientContext();
    final res = await _pose.analyse(v, e, riskLevel: riskLevel, age: age);
    if (attempt != _attempt) return null; // exited while analysing: nothing is saved
    switch (res) {
      case Failure(:final message):
        _analysis = UiError(message);
        notifyListeners();
        return null;
      case Success(:final data):
        if (_testing || p == null) {
          _analysis = UiSuccess(data); // testing mode: shown, never saved
          notifyListeners();
          return null;
        }
        if (data.safetyAlert != null) _fallSeenOn = clock();
        _analysis = UiSuccess(data);
        _lastResult = _session(p, e, data, CompletionStatus.completed);
        notifyListeners();
        // UI Design, Posture Result Screen: 80% or more updates the progress automatically.
        // Not after a possible fall: the patient should stop and see the safety message first.
        if (data.isPassing && data.safetyAlert == null) await acceptResult();
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

  /// The saved tries below 80% of this exercise in a row, counting [s] (1 after the first);
  /// 0 when [s] passed.
  static int triesBelowPass(
    List<ExerciseSession> planSessions,
    ExerciseSession s,
  ) {
    if (s.postureIsPassing()) return 0;
    var n = 1;
    for (final x in planSessions.reversed.where(
      (x) => x.exerciseId == s.exerciseId && x.sessionId != s.sessionId,
    )) {
      if (x.completionStatus != CompletionStatus.completed) continue;
      if (x.postureIsPassing()) break;
      n++;
    }
    return n;
  }

  /// Whether saving [s] moves the plan on (Elwin, 23 Oct): at 80% or more, or on the
  /// [AppConstants.triesBeforeMovingOn]th saved try below it. Before, any Continue moved on.
  static bool movesOn(List<ExerciseSession> planSessions, ExerciseSession s) =>
      s.postureIsPassing() ||
      triesBelowPass(planSessions, s) >= AppConstants.triesBeforeMovingOn;

  /// After Continue: whether the plan moved on, and the tries below 80% so far (for the
  /// message on the result screen).
  bool _lastMovedOn = false;
  bool get lastMovedOn => _lastMovedOn;
  int _lastTriesBelowPass = 0;
  int get lastTriesBelowPass => _lastTriesBelowPass;

  /// Records the attempt and advances the pathway (FR300_11, FR300_21). Advancing only
  /// happens when the attempt is for the current stage, so repeating a finished exercise
  /// does not skip ahead.
  Future<bool> acceptResult() async {
    if (_testing) return true; // testing mode: nothing to save
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
    final advanced = isCurrentStage && movesOn(_sessions, s) ? p.advance() : null;
    final res = await _repo.saveSession(s, advancedPlan: advanced);
    if (res.isSuccess) {
      _sessions = [..._sessions, s];
      _sessionsByPlan = {..._sessionsByPlan, p.patientPlanId: _sessions};
      if (advanced != null) {
        _plan = UiSuccess(advanced);
        _replacePlan(advanced);
      }
      if (advanced?.status == PlanStatus.completed) {
        // The last exercise is done: no more "Time for ..." for this plan (audit, 23 Oct).
        await _reminders?.removeForPlan(p.accountId, p.patientPlanId);
      } else {
        // FR300_12, FR600_005: today's exercise reminder is no longer needed.
        await _reminders?.exerciseDone(p.accountId, p.patientPlanId);
      }
      await _countForOtherPlans(p, s);
      _autoAdvanced = s.postureIsPassing();
      _lastMovedOn = advanced != null;
      _lastTriesBelowPass = triesBelowPass(_sessions, s);
      _saving = const UiSuccess(null);
    } else {
      _saving = const UiError(Messages.progressSaveFailed); // FR300_27
    }
    notifyListeners();
    return res.isSuccess;
  }

  void _replacePlan(PatientTreatmentPlan updated) {
    _plans = [
      for (final a in _plans)
        a.patientPlanId == updated.patientPlanId ? updated : a,
    ];
  }

  /// An exercise shared by several active plans is done once and counts for
  /// every plan whose CURRENT stage it is and that has not had its exercise
  /// today (one exercise per plan per day). Each plan gets its own copy of the
  /// attempt and moves only its own stage.
  Future<void> _countForOtherPlans(
    PatientTreatmentPlan from,
    ExerciseSession s,
  ) async {
    if (!s.isCompleted()) return;
    for (final other in List.of(_plans)) {
      if (other.patientPlanId == from.patientPlanId) continue;
      if (other.currentExercise()?.exerciseId != s.exerciseId) continue;
      final theirs = _sessionsByPlan[other.patientPlanId] ?? const [];
      if (ExerciseSession.anyCompletedOn(theirs, clock())) continue;
      final copy = ExerciseSession(
        sessionId: newId(),
        accountId: s.accountId,
        patientPlanId: other.patientPlanId,
        exerciseId: s.exerciseId,
        completedAt: s.completedAt,
        durationSec: s.durationSec,
        repetitionsCompleted: s.repetitionsCompleted,
        completionStatus: s.completionStatus,
        postureAccuracy: s.postureAccuracy,
        postureFeedback: s.postureFeedback,
        modelVersion: s.modelVersion,
      );
      // The same rule in every plan: below 80% it moves on only after enough tries.
      final advanced = movesOn(theirs, copy) ? other.advance() : null;
      if ((await _repo.saveSession(copy, advancedPlan: advanced)).isSuccess) {
        _sessionsByPlan = {
          ..._sessionsByPlan,
          other.patientPlanId: [...theirs, copy],
        };
        if (advanced != null) _replacePlan(advanced);
        if (advanced?.status == PlanStatus.completed) {
          await _reminders?.removeForPlan(other.accountId, other.patientPlanId);
        } else {
          await _reminders?.exerciseDone(other.accountId, other.patientPlanId);
        }
      }
    }
  }

  /// Back to the recorder (FR300_20). The attempt is kept as RETRIED.
  /// Failed tries of the current exercise in a row; after two the result screen suggests trying
  /// again tomorrow (posture text review, 8 Oct).
  int get retriesInARow {
    final id = _current?.exerciseId;
    if (id == null) return 0;
    var n = 0;
    for (final s in _sessions.reversed.where((s) => s.exerciseId == id)) {
      if (s.completionStatus != CompletionStatus.retried) break;
      n++;
    }
    return n;
  }

  /// Back from the analysing screen (23 Oct): the clip still being checked is dropped, nothing
  /// is saved, and the patient is at the recorder again with the same exercise.
  void abandonAnalysis() {
    _attempt++;
    _analysis = const Idle();
    _lastResult = null;
    _saving = const Idle();
    _autoAdvanced = false;
    notifyListeners();
  }

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
        _sessionsByPlan = {..._sessionsByPlan, p.patientPlanId: _sessions};
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
      // A stopped plan's reminders went on ringing: ending only changes its status, and the
      // database removes them only with the plan row (audit, 23 Oct).
      await _reminders?.removeForPlan(p.accountId, p.patientPlanId);
      _plans = [
        for (final a in _plans)
          if (a.patientPlanId != p.patientPlanId) a,
      ];
      final next = _plans.lastOrNull;
      _plan = UiSuccess(next);
      _sessions = next == null
          ? const []
          : _sessionsByPlan[next.patientPlanId] ?? const [];
      notifyListeners();
    }
    return ok;
  }
}
