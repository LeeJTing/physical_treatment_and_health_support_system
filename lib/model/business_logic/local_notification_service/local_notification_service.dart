import 'package:physical_treatment_and_health_support_system/model/result.dart';
import 'package:physical_treatment_and_health_support_system/model/business_logic/recommendation_service/recommendation.dart';
import 'package:physical_treatment_and_health_support_system/device_platform/notification_scheduler/notification_scheduler.dart';
import 'package:physical_treatment_and_health_support_system/core/utils/id_utils.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/anomaly_event.dart';
import 'package:physical_treatment_and_health_support_system/core/constants/app_constants.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/enums.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/exercise_session.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/reminder.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/treatment_plan.dart';
import 'package:physical_treatment_and_health_support_system/model/business_logic/local_notification_service/reminder_tap.dart';
import 'package:physical_treatment_and_health_support_system/model/business_logic/diet_planner_service/plan_change.dart';
import 'package:physical_treatment_and_health_support_system/model/repository/notification_repository/i_notification_repository.dart';
import 'package:physical_treatment_and_health_support_system/model/repository/treatment_repository/i_treatment_repository.dart';

/// Schedules and delivers exercise reminders (Table 4.75; M600.1). Service layer of the
/// software architecture: keeps the stored reminders (Supabase, through
/// [INotificationRepository]) and the phone's schedule ([NotificationScheduler], Device
/// Platform layer) in step.
///
/// Each reminder is scheduled as separate one-off notifications for the next [windowDays] days
/// instead of one repeating alarm, so a single day can be cancelled when that day's exercise is
/// already done (FR600_005). The window is refreshed whenever the app starts or a reminder changes.
class LocalNotificationService {
  final INotificationRepository _repo;
  final ITreatmentRepository _treatments;
  final NotificationScheduler _scheduler;
  final DateTime Function() _now;
  static const windowDays = 14;

  /// The profile age, read when a reminder is scheduled: exercise reminders
  /// do not ring from 65, when plans are paused (Terms of Use, section 2).
  /// They are kept, not deleted. Null = no age check.
  final Future<int?> Function()? _profileAge;

  LocalNotificationService(
    this._repo,
    this._treatments, {
    NotificationScheduler? scheduler,
    DateTime Function()? now,
    this._profileAge,
  }) : _scheduler = scheduler ?? PluginScheduler(),
       _now = now ?? DateTime.now;

  /// Requested before the first reminder is scheduled (FR600_008).
  bool permissionGranted = false;

  /// The patient refused notifications: reminders are kept but cannot ring. Set by a refusal and
  /// not asked again on every change (Android would show its dialog once more); the Reminders
  /// screen says so and offers to ask again.
  bool permissionDenied = false;

  /// Asks before the first schedule (FR600_008).
  Future<bool> requestPermission() async {
    try {
      permissionGranted = await _scheduler.requestPermission();
    } catch (_) {
      permissionGranted = false;
    }
    permissionDenied = !permissionGranted;
    return permissionGranted;
  }

  /// Opens HealthGuide's notification settings (after a refusal Android may not show its dialog
  /// again). False when they could not be opened.
  Future<bool> openNotificationSettings() async {
    try {
      return await _scheduler.openSettings();
    } catch (_) {
      return false;
    }
  }

  /// Reads the phone's setting without asking, e.g. after the patient turned notifications on in
  /// Settings. True when allowed.
  Future<bool> checkPermission() async {
    try {
      permissionGranted = await _scheduler.isPermitted();
    } catch (_) {
      // Unknown: keep what we had.
    }
    if (permissionGranted) permissionDenied = false;
    return permissionGranted;
  }

  /// Stable notification id for one reminder on one day.
  static int idFor(String reminderId, DateTime day) {
    final key = '$reminderId:${day.year}-${day.month}-${day.day}';
    var h = 0;
    for (final c in key.codeUnits) {
      h = (h * 31 + c) & 0x7fffffff;
    }
    return h;
  }

  /// Registers each repeat occurrence in the window (FR600_003, FR600_004). Days in [skipDays]
  /// (date only) are left out, e.g. today after the exercise is done.
  Future<int> schedule(
    Reminder r, {
    Set<DateTime> skipDays = const {},
    String? body,
  }) async {
    await cancel(r.reminderId);
    if (!r.isEnabled) return 0;
    final ageOf = _profileAge;
    if (ageOf != null &&
        r.reminderType == ReminderType.exercise &&
        PlanRestriction.forAge(await ageOf()) != null) {
      return 0; // plans paused from 65
    }
    if (!permissionGranted &&
        (permissionDenied || !await requestPermission())) {
      return 0; // refused: asked once, not on every change
    }
    final now = _now();
    final text = body ?? await _bodyFor(r);
    final payload = ReminderTap(r.reminderType, r.patientPlanId).toPayload();
    var count = 0;
    for (var i = 0; i < windowDays; i++) {
      final day = DateTime(now.year, now.month, now.day + i);
      final at = DateTime(day.year, day.month, day.day, r.hour, r.minute);
      if (!at.isAfter(now) || !r.firesOn(day) || skipDays.contains(day)) {
        continue;
      }
      try {
        await _scheduler.scheduleOnce(
          idFor(r.reminderId, day),
          r.title,
          text,
          at,
          payload: payload,
        );
        count++;
      } catch (_) {
        // A plugin failure must not stop the other days or reach the caller (services never
        // throw); the count says how many were scheduled.
      }
    }
    return count;
  }

  /// Removes the schedule when a reminder is disabled or deleted.
  Future<void> cancel(String reminderId) async {
    final now = _now();
    for (var i = -1; i <= windowDays; i++) {
      await _cancelOne(
        idFor(reminderId, DateTime(now.year, now.month, now.day + i)),
      );
    }
  }

  /// Takes every HealthGuide notification off the phone, without reading the reminders, so it
  /// also works offline (log out; PC review, Elwin's OK, 23 Oct). Never throws.
  Future<void> cancelEverything() async {
    try {
      await _scheduler.cancelAll();
    } catch (_) {
      // No scheduler on this device: nothing was scheduled either.
    }
  }

  Future<void> _cancelOne(int id) async {
    try {
      await _scheduler.cancel(id);
    } catch (_) {
      // Nothing scheduled under that id, or the plugin is unavailable: nothing to undo.
    }
  }

  /// What the notification says. An exercise reminder names the plan's exercise for today (one
  /// exercise per plan a day) and its length; worked out again whenever the reminder is scheduled
  /// (app start, an edit, a finished exercise), so it follows the pathway.
  Future<String> _bodyFor(Reminder r) async {
    if (r.reminderType == ReminderType.healthLog) {
      return 'Tap to open HealthGuide and record today\'s health readings.';
    }
    if (r.reminderType == ReminderType.meal) {
      final slot = r.title.split(' ').first.toLowerCase();
      return 'Tap to see the $slot in today\'s diet plan and log what you eat.';
    }
    final stage = await _currentStage(r);
    if (stage == null) return 'Tap to open your plan and do today\'s exercise.';
    final min = (stage.prescribedDurationSec / 60).ceil().clamp(1, 60);
    return 'Today: ${stage.exercise.exerciseName}, about $min '
        'minute${min == 1 ? '' : 's'}. Tap to open it.';
  }

  Future<PlanExercise?> _currentStage(Reminder r) async {
    final id = r.patientPlanId;
    if (id == null) return null;
    final plans =
        (await _treatments.getActivePlans(r.accountId)).dataOrNull ?? const [];
    return plans.where((p) => p.patientPlanId == id).firstOrNull?.currentStage();
  }

  /// Reminders the patient taps while the app is running.
  Stream<ReminderTap> taps() {
    _scheduler.init().ignore(); // taps arrive only once the plugin is set up
    return _scheduler.taps
        .handleError((Object _) {}) // a plugin error must not reach the app
        .map(ReminderTap.fromPayload)
        .where((t) => t != null)
        .cast<ReminderTap>();
  }

  /// The reminder whose tap started the app, if one did.
  Future<ReminderTap?> launchTap() async {
    try {
      return ReminderTap.fromPayload(await _scheduler.launchPayload());
    } catch (_) {
      return null;
    }
  }

  /// False when the phone may deliver reminders up to an hour late (no exact alarms).
  Future<bool> canRingOnTime() async {
    try {
      return await _scheduler.canRingOnTime();
    } catch (_) {
      return true;
    }
  }

  /// Opens "Alarms & reminders" for HealthGuide.
  Future<void> openOnTimeSettings() async {
    try {
      await _scheduler.openExactAlarmSettings();
    } catch (_) {
      // Nothing to open on this phone.
    }
  }

  /// Cancels only today's occurrence (FR600_005: the day's exercise is already done).
  Future<void> cancelToday(String reminderId) async {
    final now = _now();
    await _cancelOne(idFor(reminderId, DateTime(now.year, now.month, now.day)));
  }

  // ---- Reminders of the treatment plan (formerly a separate ReminderService) ----------------

  DateTime get _today {
    final n = _now();
    return DateTime(n.year, n.month, n.day);
  }

  /// After a plan is selected (FR500_11): the old plan's reminders are removed and the new
  /// one is scheduled on the device.
  Future<Result<void>> planSelected(
    Reminder r, {
    String? previousPatientPlanId,
  }) async {
    if (previousPatientPlanId != null &&
        previousPatientPlanId != r.patientPlanId) {
      await removeForPlan(r.accountId, previousPatientPlanId);
    }
    await schedule(r);
    return const Success(null);
  }

  /// Cancels every reminder of the account on this phone (the stored ones are
  /// left alone), e.g. before the account is deleted.
  Future<void> cancelAllFor(String accountId) async {
    final all =
        (await _repo.getReminders(accountId)).dataOrNull ?? const <Reminder>[];
    for (final r in all) {
      await cancel(r.reminderId);
    }
  }

  /// Cancels and deletes the reminders of a plan that is no longer followed.
  Future<void> removeForPlan(String accountId, String patientPlanId) async {
    final all =
        (await _repo.getReminders(accountId)).dataOrNull ?? const <Reminder>[];
    for (final r in all.where((r) => r.patientPlanId == patientPlanId)) {
      await cancel(r.reminderId);
    }
    await _repo.deleteRemindersForPlan(patientPlanId);
  }

  /// Refreshes the device schedule for the account, e.g. when the app starts. An exercise
  /// reminder skips today if a session was already completed today (FR600_005).
  Future<int> sync(String accountId) async {
    final reminders =
        (await _repo.getReminders(accountId)).dataOrNull ?? const <Reminder>[];
    // An exercise reminder of a plan no longer followed (ended or finished before its
    // reminders were removed with it, or on another phone) does not ring; it is not deleted.
    // When the plans cannot be read (offline) every reminder rings as before (audit, 23 Oct).
    final active = (await _treatments.getActivePlans(accountId)).dataOrNull
        ?.map((p) => p.patientPlanId)
        .toSet();
    final rest = await _fallToday(active ?? const {});
    var scheduled = 0;
    for (final r in reminders) {
      if (active != null &&
          r.reminderType == ReminderType.exercise &&
          r.patientPlanId != null &&
          !active.contains(r.patientPlanId)) {
        await cancel(r.reminderId);
        continue;
      }
      final skip = await _quietToday(r, rest: rest) ? {_today} : <DateTime>{};
      scheduled += await schedule(r, skipDays: skip);
    }
    return scheduled;
  }

  Future<bool> _doneToday(String patientPlanId) async {
    final sessions =
        (await _treatments.getSessions(patientPlanId)).dataOrNull ?? const [];
    // Same rule as Home and Treatment (local calendar date).
    return ExerciseSession.anyCompletedOn(sessions, _today);
  }

  /// A possible fall today in any of these plans: today is a rest day for every plan
  /// (TreatmentViewModel.restDayToday), so no exercise reminder rings today.
  Future<bool> _fallToday(Iterable<String> patientPlanIds) async {
    for (final id in patientPlanIds) {
      final sessions =
          (await _treatments.getSessions(id)).dataOrNull ?? const [];
      if (sessions.any((s) => s.completedOn(_today) && s.hadFallAlert())) {
        return true;
      }
    }
    return false;
  }

  /// Whether an exercise reminder stays silent today: its plan's exercise is done
  /// (FR600_005), or [rest] (a possible fall today).
  Future<bool> _quietToday(Reminder r, {required bool rest}) async =>
      r.reminderType == ReminderType.exercise &&
      r.patientPlanId != null &&
      (rest || await _doneToday(r.patientPlanId!));

  /// A session was completed (FR300_12, FR600_005): today's exercise reminders for the plan are
  /// cancelled and the skip is logged as SUPPRESSED. The later days are scheduled again, so they
  /// name the plan's next exercise.
  Future<void> exerciseDone(String accountId, String patientPlanId) =>
      _skipToday(
        accountId,
        (r) => r.patientPlanId == patientPlanId,
        'today\'s exercise is already done',
      );

  /// A possible fall was saved: today is a rest day for every plan, so today's exercise
  /// reminders of all plans are cancelled and logged as SUPPRESSED (audit, 24 Oct: the other
  /// plans' reminders still rang with "Today: ..."). The later days stay.
  Future<void> restToday(String accountId) =>
      _skipToday(accountId, (_) => true, 'rest day after a possible fall');

  Future<void> _skipToday(
    String accountId,
    bool Function(Reminder) which,
    String why,
  ) async {
    final reminders =
        (await _repo.getReminders(accountId)).dataOrNull ?? const <Reminder>[];
    final now = _now();
    for (final r in reminders.where(
      (r) => which(r) && r.reminderType == ReminderType.exercise && r.isEnabled,
    )) {
      await schedule(r, skipDays: {_today});
      final due = DateTime(now.year, now.month, now.day, r.hour, r.minute);
      // Logged only when today's reminder was still to come.
      if (!r.firesOn(now) || !due.isAfter(now)) continue;
      await _repo.logNotification(
        NotificationLog(
          notificationId: newId(),
          accountId: accountId,
          reminderId: r.reminderId,
          notificationType: NotificationType.reminder,
          messageBody: '${r.title} (skipped: $why)',
          deliveryStatus: DeliveryStatus.suppressed,
          isRead: true,
          issuedAt: now,
        ),
      );
    }
  }

  /// Switch a reminder on or off without deleting it (FR600_006), or change its time (FR600_004)
  /// or the days it fires on (FR600_003). Also saves and schedules a new reminder.
  Future<Result<Reminder>> update(
    Reminder r, {
    bool? enabled,
    int? hour,
    int? minute,
    String? repeatDays,
  }) async {
    final updated = r.copyWith(
      isEnabled: enabled,
      hour: hour,
      minute: minute,
      repeatDays: repeatDays,
    );
    final saved = await _repo.saveReminder(updated);
    if (saved is Failure<void>) return saved.cast<Reminder>();
    if (updated.isEnabled) {
      final plans =
          (await _treatments.getActivePlans(updated.accountId)).dataOrNull ??
          const [];
      final rest = await _fallToday(plans.map((p) => p.patientPlanId));
      final skip = await _quietToday(updated, rest: rest)
          ? {_today}
          : <DateTime>{};
      await schedule(updated, skipDays: skip);
    } else {
      await cancel(updated.reminderId);
    }
    return Success(updated);
  }

  // ---------------------------------------------------------------- changes that outlive the screen

  /// Changes made on the Reminders screen that are not saved yet, by reminder id: the latest state
  /// the patient chose. They are saved in the background, one at a time and in the order made, even
  /// after the screen is closed, and a Reminders screen opened meanwhile shows them (phone test,
  /// 9 Nov: days tapped quickly just before closing the screen were missing when it was opened
  /// again, because the new screen read the reminder before those saves had finished).
  final Map<String, Reminder> _unsaved = {};
  final Map<String, Result<Reminder>> _lastSave = {};
  Future<void> _saving = Future<void>.value();

  Map<String, Reminder> get unsaved => Map.unmodifiable(_unsaved);

  /// Completes when every change queued so far has been saved (or has failed).
  Future<void> get settled => _saving;

  /// Saves [wanted] (switched on or off, a new time or new days) after the changes queued before
  /// it, and schedules it. Quick changes to one reminder are merged: only the latest is written.
  Future<Result<Reminder>> queueUpdate(Reminder wanted) {
    final id = wanted.reminderId;
    _unsaved[id] = wanted;
    final result = _saving.then((_) async {
      final latest = _unsaved[id];
      // Already written together with an earlier change of the same reminder.
      if (latest == null) return _lastSave[id] ?? Success<Reminder>(wanted);
      Result<Reminder> res;
      try {
        res = await update(latest);
      } catch (e) {
        res = Failure<Reminder>(Messages.dbUnavailable, cause: e);
      }
      if (identical(_unsaved[id], latest)) _unsaved.remove(id); // nothing newer is waiting
      _lastSave[id] = res;
      return res;
    });
    _saving = result.then((_) {}, onError: (Object _) {});
    return result;
  }

  /// Cancels a reminder on the phone and deletes it.
  Future<Result<void>> remove(Reminder r) async {
    await cancel(r.reminderId);
    return _repo.deleteReminder(r.reminderId);
  }

  // ---------------------------------------------------------------- M600.2 alerts (Jun Ting)

  /// Accepts an anomaly from the Predictive Health Analysis Module (FR600_009): records it in the
  /// notification log (FR600_013), even when it cannot be shown on the phone (FR600_014), and shows
  /// it as a notification. A High severity alert also gets the full-screen warning in the app
  /// (FR600_010; HealthReportView) and the consult-a-professional advice (FR600_012).
  Future<NotificationLog> receiveAnomaly(AnomalyEvent a) async {
    var status = DeliveryStatus.delivered;
    final body = a.isHighSeverity()
        ? '${a.explanationText} ${Messages.consultProfessional}'
        : a.explanationText;
    try {
      if (await _scheduler.isPermitted()) {
        await showAlert(a, body: body);
      } else {
        status = DeliveryStatus.failed;
      }
    } catch (_) {
      status = DeliveryStatus.failed;
    }
    final entry = NotificationLog(
      notificationId: newId(),
      accountId: a.accountId,
      anomalyId: a.anomalyId,
      notificationType: NotificationType.alert,
      severity: a.severity,
      messageBody: body,
      deliveryStatus: status,
      issuedAt: _now(),
    );
    await _repo.logNotification(entry);
    return entry;
  }

  /// Shows the alert on the phone now (a one-off notification two seconds ahead; tapping it opens
  /// the Health Report).
  Future<void> showAlert(AnomalyEvent a, {String? body}) async {
    final title = switch (a.severity) {
      Severity.high => 'Health alert: please check this reading',
      Severity.medium => 'Health alert',
      Severity.low => 'Health note',
    };
    await _scheduler.scheduleOnce(
      _alertId(a.anomalyId),
      title,
      body ?? a.explanationText,
      _now().add(const Duration(seconds: 2)),
      payload: ReminderTap.alertPayload(a.anomalyId),
    );
  }

  /// No successful import for 24 hours (FR200_013, UC700 A1.2): logged and shown once.
  Future<void> importOverdue(String accountId) async {
    var status = DeliveryStatus.delivered;
    try {
      if (await _scheduler.isPermitted()) {
        await _scheduler.scheduleOnce(
          900000001,
          'Health readings',
          Messages.importOverdue,
          _now().add(const Duration(seconds: 2)),
          payload: const ReminderTap(ReminderType.healthLog).toPayload(),
        );
      } else {
        status = DeliveryStatus.failed;
      }
    } catch (_) {
      status = DeliveryStatus.failed;
    }
    await _repo.logNotification(
      NotificationLog(
        notificationId: newId(),
        accountId: accountId,
        notificationType: NotificationType.reminder,
        messageBody: Messages.importOverdue,
        deliveryStatus: status,
        issuedAt: _now(),
      ),
    );
  }

  // ---------------------------------------------------------------- diet plan alerts (Jun Ting)

  /// Notification ids of today's "follow your diet plan" alerts, one per meal slot, and of the
  /// alert shown when a logged meal was not the planned one.
  static int planAlertId(MealSlot s) => 700000000 + s.index;
  static int offPlanAlertId(MealSlot s) => 700000010 + s.index;

  Future<bool> _mayShow() async {
    try {
      return await _scheduler.isPermitted();
    } catch (_) {
      return false;
    }
  }

  /// Keeps today's "follow your diet plan" alerts in step with the plan and the meals logged: the
  /// slots in [alerts] (planned, not logged yet) ring at their time, the others are cancelled. Not
  /// asked for permission here; without it nothing rings. Returns how many were scheduled.
  Future<int> schedulePlanAlerts(List<PlanAlert> alerts) async {
    for (final s in MealSlot.values) {
      await _cancelOne(planAlertId(s));
    }
    if (!await _mayShow()) return 0;
    var n = 0;
    for (final a in alerts.where((a) => a.at.isAfter(_now()))) {
      try {
        await _scheduler.scheduleOnce(
          planAlertId(a.slot),
          a.title,
          a.body,
          a.at,
          payload: const ReminderTap(ReminderType.meal).toPayload(), // opens the Diet tab
        );
        n++;
      } catch (_) {
        // The plugin is unavailable: the alert still shows in the app.
      }
    }
    return n;
  }

  /// A meal was logged that is not the planned one: recorded in the notification history
  /// (FR600_013) and shown on the phone now, so it stays in the notification shade.
  Future<NotificationLog> planAlert(String accountId, PlanAlert a) async {
    var status = DeliveryStatus.delivered;
    try {
      if (await _mayShow()) {
        await _scheduler.scheduleOnce(
          offPlanAlertId(a.slot),
          a.title,
          a.body,
          _now().add(const Duration(seconds: 2)),
          payload: const ReminderTap(ReminderType.meal).toPayload(),
        );
      } else {
        status = DeliveryStatus.failed;
      }
    } catch (_) {
      status = DeliveryStatus.failed;
    }
    final entry = NotificationLog(
      notificationId: newId(),
      accountId: accountId,
      notificationType: NotificationType.reminder,
      messageBody: '${a.title}. ${a.body}',
      deliveryStatus: status,
      issuedAt: _now(),
    );
    await _repo.logNotification(entry);
    return entry;
  }

  static int _alertId(String anomalyId) => 800000000 + (anomalyId.hashCode & 0x0fffffff) % 99999999;
}
