import 'package:physical_treatment_and_health_support_system/model/entity/enums.dart';

/// Where a tapped reminder should take the patient: an exercise reminder opens its plan, a
/// health-logging reminder opens the app. Carried in the notification's payload, written by
/// LocalNotificationService.schedule().
class ReminderTap {
  final ReminderType type;
  final String? patientPlanId;
  const ReminderTap(this.type, [this.patientPlanId]);

  /// "EXERCISE|<patientPlanId>" or "HEALTH_LOG|".
  String toPayload() => '${type.db}|${patientPlanId ?? ''}';

  /// Null for anything that is not a payload written by [toPayload].
  static ReminderTap? fromPayload(String? payload) {
    if (payload == null) return null;
    final parts = payload.split('|');
    if (parts.length != 2) return null;
    final type = ReminderType.values.where((t) => t.db == parts[0]).firstOrNull;
    if (type == null) return null;
    return ReminderTap(type, parts[1].isEmpty ? null : parts[1]);
  }
}
