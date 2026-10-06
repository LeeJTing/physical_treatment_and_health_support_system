import 'package:physical_treatment_and_health_support_system/data/models/enums.dart';

/// Repeating scheduled reminder (Table 4.24). Time is held as hour/minute so
/// the model does not depend on Flutter's TimeOfDay.
class Reminder {
  final String reminderId;
  final String accountId;
  final String? patientPlanId;
  final ReminderType reminderType;
  final String title;
  final int hour;
  final int minute;

  /// Seven characters, Monday to Sunday, '1' = fires that day (FR600_003).
  final String repeatDays;
  final bool isEnabled;

  const Reminder({
    required this.reminderId,
    required this.accountId,
    this.patientPlanId,
    required this.reminderType,
    required this.title,
    required this.hour,
    required this.minute,
    this.repeatDays = '1111111',
    this.isEnabled = true,
  }) : assert(repeatDays.length == 7);

  /// Spreads N sessions per week across the week (FR500_11).
  /// 1 -> Mon, 2 -> Mon Thu, 3 -> Mon Wed Fri, 4 -> Mon Tue Thu Fri,
  /// 5 -> Mon-Fri, 6 -> Mon-Sat, 7+ -> every day.
  static String maskForFrequency(int perWeek) {
    const masks = {
      1: '1000000',
      2: '1001000',
      3: '1010100',
      4: '1101100',
      5: '1111100',
      6: '1111110',
    };
    if (perWeek <= 0) return '0000000';
    return masks[perWeek] ?? '1111111';
  }

  /// Weekdays (DateTime.monday..sunday) this reminder fires on.
  List<int> get weekdays => [
    for (var i = 0; i < 7; i++)
      if (repeatDays[i] == '1') i + 1,
  ];

  bool firesOn(DateTime day) => repeatDays[day.weekday - 1] == '1';

  /// Only an exercise reminder is suppressed once the session is done (FR600_005).
  bool shouldSuppress(bool exerciseDone) =>
      reminderType == ReminderType.exercise && exerciseDone;

  /// Next fire time strictly after [from], or null when no day is selected.
  DateTime? nextOccurrence([DateTime? from]) {
    final now = from ?? DateTime.now();
    if (!isEnabled || !repeatDays.contains('1')) return null;
    for (var i = 0; i < 8; i++) {
      final d = DateTime(now.year, now.month, now.day + i, hour, minute);
      if (d.isAfter(now) && firesOn(d)) return d;
    }
    return null;
  }

  Reminder copyWith({
    bool? isEnabled,
    int? hour,
    int? minute,
    String? repeatDays,
  }) => Reminder(
    reminderId: reminderId,
    accountId: accountId,
    patientPlanId: patientPlanId,
    reminderType: reminderType,
    title: title,
    hour: hour ?? this.hour,
    minute: minute ?? this.minute,
    repeatDays: repeatDays ?? this.repeatDays,
    isEnabled: isEnabled ?? this.isEnabled,
  );

  Map<String, dynamic> toJson() => {
    'reminder_id': reminderId,
    'account_id': accountId,
    'patient_plan_id': patientPlanId,
    'reminder_type': reminderType.db,
    'title': title,
    'scheduled_time':
        '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}:00',
    'repeat_days': repeatDays,
    'is_enabled': isEnabled,
  };

  factory Reminder.fromJson(Map<String, dynamic> j) {
    final t = (j['scheduled_time'] as String).split(':');
    return Reminder(
      reminderId: j['reminder_id'] as String,
      accountId: j['account_id'] as String,
      patientPlanId: j['patient_plan_id'] as String?,
      reminderType: ReminderType.fromDb(j['reminder_type'] as String?),
      title: j['title'] as String,
      hour: int.parse(t[0]),
      minute: int.parse(t[1]),
      repeatDays: (j['repeat_days'] ?? '1111111') as String,
      isEnabled: (j['is_enabled'] ?? true) as bool,
    );
  }
}

/// Every notification issued, delivered or not (Table 4.23).
class NotificationLog {
  final String notificationId;
  final String accountId;
  final String? reminderId;
  final NotificationType notificationType;
  final String messageBody;
  final DeliveryStatus deliveryStatus;
  final bool isRead;
  final DateTime issuedAt;

  const NotificationLog({
    required this.notificationId,
    required this.accountId,
    this.reminderId,
    required this.notificationType,
    required this.messageBody,
    required this.deliveryStatus,
    this.isRead = false,
    required this.issuedAt,
  });

  Map<String, dynamic> toJson() => {
    'notification_id': notificationId,
    'account_id': accountId,
    'reminder_id': reminderId,
    'notification_type': notificationType.db,
    'message_body': messageBody,
    'delivery_status': deliveryStatus.db,
    'is_read': isRead,
    'issued_at': issuedAt.toIso8601String(),
  };

  factory NotificationLog.fromJson(Map<String, dynamic> j) => NotificationLog(
    notificationId: j['notification_id'] as String,
    accountId: j['account_id'] as String,
    reminderId: j['reminder_id'] as String?,
    notificationType: NotificationType.fromDb(
      j['notification_type'] as String?,
    ),
    messageBody: j['message_body'] as String,
    deliveryStatus: DeliveryStatus.fromDb(j['delivery_status'] as String?),
    isRead: (j['is_read'] ?? false) as bool,
    issuedAt: DateTime.parse(j['issued_at'] as String),
  );
}
