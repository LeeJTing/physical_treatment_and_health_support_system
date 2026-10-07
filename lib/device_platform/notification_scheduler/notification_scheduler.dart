import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import 'package:physical_treatment_and_health_support_system/core/constants/app_constants.dart';

/// Device Platform layer of the software architecture ("Notification Scheduler"): the
/// phone's own scheduler. The real one wraps flutter_local_notifications; tests use a
/// fake. Kept small so a plugin API change only touches [PluginScheduler].
abstract interface class NotificationScheduler {
  Future<void> init();
  Future<bool> requestPermission();
  Future<void> scheduleOnce(int id, String title, String body, DateTime at);
  Future<void> cancel(int id);
}

class PluginScheduler implements NotificationScheduler {
  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
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
    await _plugin.initialize(
      const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      ),
    );
    _ready = true;
  }

  @override
  Future<bool> requestPermission() async {
    await init();
    final android = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    return await android?.requestNotificationsPermission() ?? true;
  }

  @override
  Future<void> scheduleOnce(
    int id,
    String title,
    String body,
    DateTime at,
  ) async {
    await init();
    // Inexact delivery needs no exact-alarm permission and is fine for a reminder.
    await _plugin.zonedSchedule(
      id,
      title,
      body,
      tz.TZDateTime.from(at, tz.local),
      _details,
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
    );
  }

  @override
  Future<void> cancel(int id) async {
    await init();
    await _plugin.cancel(id);
  }
}
