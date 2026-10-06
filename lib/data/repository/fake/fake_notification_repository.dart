import 'package:physical_treatment_and_health_support_system/core/base/result.dart';
import 'package:physical_treatment_and_health_support_system/data/models/reminder.dart';
import 'package:physical_treatment_and_health_support_system/data/repository/interfaces/i_notification_repository.dart';

class FakeNotificationRepository implements INotificationRepository {
  final Map<String, Reminder> reminders = {};
  final List<NotificationLog> log = [];

  @override
  Future<Result<void>> saveReminder(Reminder r) async {
    reminders[r.reminderId] = r;
    return const Success(null);
  }

  @override
  Future<Result<List<Reminder>>> getReminders(String accountId) async =>
      Success(reminders.values.where((r) => r.accountId == accountId).toList());

  @override
  Future<Result<void>> deleteRemindersForPlan(String patientPlanId) async {
    reminders.removeWhere((_, r) => r.patientPlanId == patientPlanId);
    return const Success(null);
  }

  @override
  Future<Result<void>> logNotification(NotificationLog n) async {
    log.add(n);
    return const Success(null);
  }

  @override
  Future<Result<int>> unreadCount(String accountId) async =>
      Success(log.where((n) => n.accountId == accountId && !n.isRead).length);
}
