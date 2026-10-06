import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:physical_treatment_and_health_support_system/core/base/result.dart';
import 'package:physical_treatment_and_health_support_system/core/services/supabase_provider.dart';
import 'package:physical_treatment_and_health_support_system/data/models/reminder.dart';
import 'package:physical_treatment_and_health_support_system/data/repository/interfaces/i_notification_repository.dart';
import 'package:physical_treatment_and_health_support_system/data/repository/supabase/supabase_guard.dart';

/// Reminders and the notification log (Table 4.58).
class SupabaseNotificationRepository implements INotificationRepository {
  final SupabaseProvider _sb;

  SupabaseNotificationRepository(this._sb);

  @override
  Future<Result<void>> saveReminder(Reminder r) => supabaseGuard(() async {
    await _sb.from('reminder').upsert(r.toJson());
  });

  @override
  Future<Result<List<Reminder>>> getReminders(String accountId) =>
      supabaseGuard(
        () async =>
            (await _sb.from('reminder').select().eq('account_id', accountId))
                .map(Reminder.fromJson)
                .toList(),
      );

  @override
  Future<Result<void>> deleteRemindersForPlan(String patientPlanId) =>
      supabaseGuard(() async {
        await _sb
            .from('reminder')
            .delete()
            .eq('patient_plan_id', patientPlanId);
      });

  @override
  Future<Result<void>> logNotification(NotificationLog n) =>
      supabaseGuard(() async {
        await _sb.from('notification_log').insert(n.toJson());
      });

  @override
  Future<Result<int>> unreadCount(String accountId) => supabaseGuard(() async {
    final res = await _sb
        .from('notification_log')
        .select('notification_id')
        .eq('account_id', accountId)
        .eq('is_read', false)
        .count(CountOption.exact);
    return res.count;
  });

  @override
  Future<Result<List<NotificationLog>>> getLog(
    String accountId,
    DateTime from,
    DateTime to,
  ) => supabaseGuard(
    () async =>
        (await _sb
                .from('notification_log')
                .select()
                .eq('account_id', accountId)
                .gte('issued_at', from.toUtc().toIso8601String())
                .lte('issued_at', to.toUtc().toIso8601String())
                .order('issued_at', ascending: false))
            .map(NotificationLog.fromJson)
            .toList(),
  );

  @override
  Future<Result<void>> markRead(String notificationId) =>
      supabaseGuard(() async {
        await _sb
            .from('notification_log')
            .update({'is_read': true})
            .eq('notification_id', notificationId);
      });
}
