import 'package:physical_treatment_and_health_support_system/core/base/result.dart';
import 'package:physical_treatment_and_health_support_system/data/models/reminder.dart';

/// Contract for reminders and the notification log (Table 4.58).
abstract interface class INotificationRepository {
  Future<Result<void>> saveReminder(Reminder r);
  Future<Result<List<Reminder>>> getReminders(String accountId);
  Future<Result<void>> deleteRemindersForPlan(String patientPlanId);
  Future<Result<void>> logNotification(NotificationLog n);
  Future<Result<int>> unreadCount(String accountId);

  /// Notifications issued between [from] and [to], newest first (FR600_013, FR600_015).
  Future<Result<List<NotificationLog>>> getLog(
    String accountId,
    DateTime from,
    DateTime to,
  );

  /// Marks one entry read, clearing it from the unread count (FR600_016).
  Future<Result<void>> markRead(String notificationId);
}
