import 'package:flutter/services.dart';
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

  /// Whether notifications are allowed now, without showing the system dialog.
  Future<bool> isPermitted();

  /// Opens the phone's notification settings for this app; false when it could not.
  Future<bool> openSettings();
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
  Future<bool> isPermitted() async {
    await init();
    final android = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    return await android?.areNotificationsEnabled() ?? true;
  }

  /// MainActivity's "apths/settings" channel (no extra package).
  static const _settings = MethodChannel('apths/settings');

  @override
  Future<bool> openSettings() async {
    try {
      return await _settings.invokeMethod<bool>('openNotificationSettings') ??
          false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  @override
  Future<void> scheduleOnce(
    int id,
    String title,
    String body,
    DateTime at,
  ) async {
    await init();
    // On time where the phone allows exact alarms (SCHEDULE_EXACT_ALARM: on by default up to
    // Android 13, on 14+ only if the patient turned on "Alarms & reminders"). Otherwise inexact:
    // Android may deliver a far-off alarm up to an hour late to save battery (seen on the emulator:
    // window +1 h). No extra prompt either way.
    final android = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    final exact = await android?.canScheduleExactNotifications() ?? false;
    await _plugin.zonedSchedule(
      id,
      title,
      body,
      tz.TZDateTime.from(at, tz.local),
      _details,
      androidScheduleMode: exact
          ? AndroidScheduleMode.exactAllowWhileIdle
          : AndroidScheduleMode.inexactAllowWhileIdle,
    );
  }

  @override
  Future<void> cancel(int id) async {
    await init();
    await _plugin.cancel(id);
  }
}
