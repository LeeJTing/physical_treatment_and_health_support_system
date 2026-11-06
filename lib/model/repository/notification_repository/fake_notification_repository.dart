import 'package:physical_treatment_and_health_support_system/model/result.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/reminder.dart';
import 'package:physical_treatment_and_health_support_system/model/repository/notification_repository/i_notification_repository.dart';

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
  Future<Result<void>> deleteReminder(String reminderId) async {
    reminders.remove(reminderId);
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

  @override
  Future<Result<List<NotificationLog>>> getLog(
    String accountId,
    DateTime from,
    DateTime to,
  ) async => Success(
    log
        .where(
          (n) =>
              n.accountId == accountId &&
              !n.issuedAt.isBefore(from) &&
              !n.issuedAt.isAfter(to),
        )
        .toList()
      ..sort((a, b) => b.issuedAt.compareTo(a.issuedAt)),
  );

  @override
  Future<Result<void>> markRead(String notificationId) async {
    final i = log.indexWhere((n) => n.notificationId == notificationId);
    if (i >= 0) log[i] = log[i].markRead();
    return const Success(null);
  }
}
