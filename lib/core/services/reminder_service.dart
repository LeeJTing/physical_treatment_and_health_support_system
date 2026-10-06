import 'package:physical_treatment_and_health_support_system/core/base/result.dart';
import 'package:physical_treatment_and_health_support_system/core/services/local_notification_service.dart';
import 'package:physical_treatment_and_health_support_system/core/utils/id_utils.dart';
import 'package:physical_treatment_and_health_support_system/data/models/enums.dart';
import 'package:physical_treatment_and_health_support_system/data/models/reminder.dart';
import 'package:physical_treatment_and_health_support_system/data/repository/interfaces/i_notification_repository.dart';
import 'package:physical_treatment_and_health_support_system/data/repository/interfaces/i_treatment_repository.dart';

/// Keeps the stored reminders (Supabase) and the device schedule in step (M600.1).
class ReminderService {
  final INotificationRepository _repo;
  final ITreatmentRepository _treatments;
  final LocalNotificationService _local;
  final DateTime Function() _now;

  ReminderService(
    this._repo,
    this._treatments,
    this._local, {
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

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
    await _local.schedule(r);
    return const Success(null);
  }

  /// Cancels and deletes the reminders of a plan that is no longer followed.
  Future<void> removeForPlan(String accountId, String patientPlanId) async {
    final all =
        (await _repo.getReminders(accountId)).dataOrNull ?? const <Reminder>[];
    for (final r in all.where((r) => r.patientPlanId == patientPlanId)) {
      await _local.cancel(r.reminderId);
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
      scheduled += await _local.schedule(r, skipDays: skip);
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
      await _local.cancelToday(r.reminderId);
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
      await _local.schedule(updated, skipDays: skip);
    } else {
      await _local.cancel(updated.reminderId);
    }
    return Success(updated);
  }
}
