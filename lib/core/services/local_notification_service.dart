import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import 'package:physical_treatment_and_health_support_system/core/constants/app_constants.dart';
import 'package:physical_treatment_and_health_support_system/data/models/reminder.dart';

/// The device side of scheduling. The real one wraps flutter_local_notifications; tests use a
/// fake. Kept small so a plugin API change only touches [PluginScheduler].
abstract interface class NotificationScheduler {
  Future<void> init();
  Future<bool> requestPermission();
  Future<void> scheduleOnce(int id, String title, String body, DateTime at);
  Future<void> cancel(int id);
}

class PluginScheduler implements NotificationScheduler {
  final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();
  bool _ready = false;

  static const _details = NotificationDetails(
    android: AndroidNotificationDetails(
      'exercise_reminders',
      'Exercise reminders',
      channelDescription: 'Reminders for your rehabilitation exercises',
      importance: Importance.high,
      priority: Priority.high,
    ),
  );

  @override
  Future<void> init() async {
    if (_ready) return;
    tzdata.initializeTimeZones();
    tz.setLocalLocation(tz.getLocation(AppConstants.timezone));
    await _plugin.initialize(const InitializationSettings(android: AndroidInitializationSettings('@mipmap/ic_launcher')));
    _ready = true;
  }

  @override
  Future<bool> requestPermission() async {
    await init();
    final android = _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    return await android?.requestNotificationsPermission() ?? true;
  }

  @override
  Future<void> scheduleOnce(int id, String title, String body, DateTime at) async {
    await init();
    // Inexact delivery needs no exact-alarm permission and is fine for a reminder.
    await _plugin.zonedSchedule(id, title, body, tz.TZDateTime.from(at, tz.local), _details,
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle);
  }

  @override
  Future<void> cancel(int id) async {
    await init();
    await _plugin.cancel(id);
  }
}

/// Schedules and delivers device notifications (Table 4.75).
///
/// Each reminder is scheduled as separate one-off notifications for the next [windowDays] days
/// instead of one repeating alarm, so a single day can be cancelled when that day's exercise is
/// already done (FR600_005). The window is refreshed whenever the app starts or a reminder changes.
class LocalNotificationService {
  final NotificationScheduler _scheduler;
  final DateTime Function() _now;
  static const windowDays = 14;

  LocalNotificationService({NotificationScheduler? scheduler, DateTime Function()? now})
      : _scheduler = scheduler ?? PluginScheduler(),
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
  Future<int> schedule(Reminder r, {Set<DateTime> skipDays = const {}, String? body}) async {
    await cancel(r.reminderId);
    if (!r.isEnabled) return 0;
    if (!permissionGranted && !await requestPermission()) return 0;
    final now = _now();
    var count = 0;
    for (var i = 0; i < windowDays; i++) {
      final day = DateTime(now.year, now.month, now.day + i);
      final at = DateTime(day.year, day.month, day.day, r.hour, r.minute);
      if (!at.isAfter(now) || !r.firesOn(day) || skipDays.contains(day)) continue;
      await _scheduler.scheduleOnce(idFor(r.reminderId, day), r.title,
          body ?? 'Open the app to do today\'s exercises and check your posture.', at);
      count++;
    }
    return count;
  }

  /// Removes the schedule when a reminder is disabled or deleted.
  Future<void> cancel(String reminderId) async {
    final now = _now();
    for (var i = -1; i <= windowDays; i++) {
      await _scheduler.cancel(idFor(reminderId, DateTime(now.year, now.month, now.day + i)));
    }
  }

  /// Cancels only today's occurrence (FR600_005: the day's exercise is already done).
  Future<void> cancelToday(String reminderId) async {
    final now = _now();
    await _scheduler.cancel(idFor(reminderId, DateTime(now.year, now.month, now.day)));
  }
}
