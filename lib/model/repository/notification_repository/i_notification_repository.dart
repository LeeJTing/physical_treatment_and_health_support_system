import 'package:physical_treatment_and_health_support_system/model/result.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/reminder.dart';

/// Contract for reminders and the notification log (Table 4.58).
abstract interface class INotificationRepository {
  Future<Result<void>> saveReminder(Reminder r);
  Future<Result<List<Reminder>>> getReminders(String accountId);
  Future<Result<void>> deleteRemindersForPlan(String patientPlanId);

  /// Deletes one reminder, e.g. a health-logging reminder the patient no longer wants.
  Future<Result<void>> deleteReminder(String reminderId);
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
