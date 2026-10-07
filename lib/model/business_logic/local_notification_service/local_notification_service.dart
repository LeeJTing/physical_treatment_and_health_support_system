import 'package:physical_treatment_and_health_support_system/model/result.dart';
import 'package:physical_treatment_and_health_support_system/device_platform/notification_scheduler/notification_scheduler.dart';
import 'package:physical_treatment_and_health_support_system/core/utils/id_utils.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/enums.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/reminder.dart';
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

  LocalNotificationService(
    this._repo,
    this._treatments, {
    NotificationScheduler? scheduler,
    DateTime Function()? now,
  }) : _scheduler = scheduler ?? PluginScheduler(),
       _now = now ?? DateTime.now;

  /// Requested before the first reminder is scheduled (FR600_008).
  bool permissionGranted = false;

  /// Asks before the first schedule (FR600_008).
  Future<bool> requestPermission() async {
    try {
      permissionGranted = await _scheduler.requestPermission();
    } catch (_) {
      permissionGranted = false;
    }
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
    if (!permissionGranted && !await requestPermission()) return 0;
    final now = _now();
    var count = 0;
    for (var i = 0; i < windowDays; i++) {
      final day = DateTime(now.year, now.month, now.day + i);
      final at = DateTime(day.year, day.month, day.day, r.hour, r.minute);
      if (!at.isAfter(now) || !r.firesOn(day) || skipDays.contains(day)) {
        continue;
      }
      await _scheduler.scheduleOnce(
        idFor(r.reminderId, day),
        r.title,
        body ?? 'Open the app to do today\'s exercises and check your posture.',
        at,
      );
      count++;
    }
    return count;
  }

  /// Removes the schedule when a reminder is disabled or deleted.
  Future<void> cancel(String reminderId) async {
    final now = _now();
    for (var i = -1; i <= windowDays; i++) {
      await _scheduler.cancel(
        idFor(reminderId, DateTime(now.year, now.month, now.day + i)),
      );
    }
  }

  /// Cancels only today's occurrence (FR600_005: the day's exercise is already done).
  Future<void> cancelToday(String reminderId) async {
    final now = _now();
    await _scheduler.cancel(
      idFor(reminderId, DateTime(now.year, now.month, now.day)),
    );
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
    var scheduled = 0;
    for (final r in reminders) {
      final skip =
          r.reminderType == ReminderType.exercise &&
              r.patientPlanId != null &&
              await _doneToday(r.patientPlanId!)
          ? {_today}
          : <DateTime>{};
      scheduled += await schedule(r, skipDays: skip);
    }
    return scheduled;
  }

  Future<bool> _doneToday(String patientPlanId) async {
    final sessions =
        (await _treatments.getSessions(patientPlanId)).dataOrNull ?? const [];
    final t = _today;
    return sessions.any(
      (s) =>
          s.completionStatus == CompletionStatus.completed &&
          s.completedAt != null &&
          DateTime(
                s.completedAt!.year,
                s.completedAt!.month,
                s.completedAt!.day,
              ) ==
              t,
    );
  }

  /// A session was completed (FR300_12, FR600_005): today's exercise reminders for the plan are
  /// cancelled and the skip is logged as SUPPRESSED.
  Future<void> exerciseDone(String accountId, String patientPlanId) async {
    final reminders =
        (await _repo.getReminders(accountId)).dataOrNull ?? const <Reminder>[];
    final now = _now();
    for (final r in reminders.where(
      (r) =>
          r.patientPlanId == patientPlanId &&
          r.reminderType == ReminderType.exercise &&
          r.isEnabled &&
          r.firesOn(now),
    )) {
      final due = DateTime(now.year, now.month, now.day, r.hour, r.minute);
      if (!due.isAfter(now)) continue; // already fired today
      await cancelToday(r.reminderId);
      await _repo.logNotification(
        NotificationLog(
          notificationId: newId(),
          accountId: accountId,
          reminderId: r.reminderId,
          notificationType: NotificationType.reminder,
          messageBody:
              '${r.title} (skipped: today\'s exercise is already done)',
          deliveryStatus: DeliveryStatus.suppressed,
          isRead: true,
          issuedAt: now,
        ),
      );
    }
  }

  /// Switch a reminder on or off without deleting it (FR600_006), or change its time (FR600_004).
  Future<Result<Reminder>> update(
    Reminder r, {
    bool? enabled,
    int? hour,
    int? minute,
  }) async {
    final updated = r.copyWith(isEnabled: enabled, hour: hour, minute: minute);
    final saved = await _repo.saveReminder(updated);
    if (saved is Failure<void>) return saved.cast<Reminder>();
    if (updated.isEnabled) {
      final skip =
          updated.reminderType == ReminderType.exercise &&
              updated.patientPlanId != null &&
              await _doneToday(updated.patientPlanId!)
          ? {_today}
          : <DateTime>{};
      await schedule(updated, skipDays: skip);
    } else {
      await cancel(updated.reminderId);
    }
    return Success(updated);
  }
}
