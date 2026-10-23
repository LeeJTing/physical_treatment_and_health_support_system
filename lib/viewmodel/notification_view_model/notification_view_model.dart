import 'package:physical_treatment_and_health_support_system/model/business_logic/local_notification_service/local_notification_service.dart';
import 'package:physical_treatment_and_health_support_system/viewmodel/base_view_model.dart';
import 'package:physical_treatment_and_health_support_system/model/result.dart';
import 'package:physical_treatment_and_health_support_system/viewmodel/ui_state.dart';
import 'package:physical_treatment_and_health_support_system/core/constants/app_constants.dart';
import 'package:physical_treatment_and_health_support_system/core/utils/id_utils.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/enums.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/reminder.dart';
import 'package:physical_treatment_and_health_support_system/model/repository/auth_repository/i_auth_repository.dart';
import 'package:physical_treatment_and_health_support_system/model/repository/notification_repository/i_notification_repository.dart';

/// Reminder management and the notification log (Table 4.49). receiveAnomaly (FR600_009/010)
/// belongs to the M400 health-monitoring alerts and is added with that module.
class NotificationViewModel extends BaseViewModel {
  final INotificationRepository _repo;
  final LocalNotificationService _scheduler;
  final IAuthRepository _auth;

  NotificationViewModel(this._repo, this._scheduler, this._auth);

  String? _accountId;

  UiState<List<Reminder>> _reminders = const Idle();
  UiState<List<Reminder>> get reminders => _reminders;

  List<NotificationLog> _log = const [];
  List<NotificationLog> get log => _log;

  /// Drives the notification indicator (FR600_017).
  int _unreadCount = 0;
  int get unreadCount => _unreadCount;

  Future<void> load() async {
    _reminders = const Loading();
    notifyListeners();
    _accountId = (await _auth.currentAccount()).dataOrNull?.accountId;
    final id = _accountId;
    if (id == null) {
      _reminders = const UiError(Messages.sessionExpired);
      notifyListeners();
      return;
    }
    // Turned on in Settings since the refusal: put the reminders on the phone again.
    final wasDenied = _scheduler.permissionDenied;
    if (await _scheduler.checkPermission() && wasDenied) {
      await _scheduler.sync(id);
    }
    _onTime = await _scheduler.canRingOnTime();
    final res = await _repo.getReminders(id);
    _reminders = switch (res) {
      Success(:final data) => UiSuccess(
        [...data]..sort(
          (a, b) => (a.hour * 60 + a.minute).compareTo(b.hour * 60 + b.minute),
        ),
      ),
      Failure() => const UiError(Messages.dbUnavailable),
    };
    final now = DateTime.now();
    await loadLog(now.subtract(const Duration(days: 14)), now);
  }

  /// Notifications are refused for the app: reminders are saved but cannot ring (FR600_008).
  bool get notificationsBlocked => _scheduler.permissionDenied;

  /// "Turn on notifications": opens HealthGuide's notification settings. Asking again would often
  /// do nothing: after two refusals Android no longer shows its dialog.
  Future<void> openNotificationSettings() async {
    await _scheduler.openNotificationSettings();
  }

  bool _onTime = true;

  /// False when this phone may deliver reminders up to an hour late (Android 14+ without
  /// "Alarms & reminders"); the screen offers to turn it on.
  bool get remindersOnTime => _onTime;

  /// "Turn on Alarms & reminders".
  Future<void> openOnTimeSettings() => _scheduler.openOnTimeSettings();

  /// Back in the app (e.g. from Settings): reads the settings again. Notifications now allowed, or
  /// on-time alarms newly allowed: the reminders are put on the phone again (exact this time).
  Future<void> recheckPermission() async {
    final id = _accountId;
    if (id == null) return;
    var resync = false;
    if (_scheduler.permissionDenied && await _scheduler.checkPermission()) {
      resync = true;
    }
    final onTime = await _scheduler.canRingOnTime();
    if (onTime && !_onTime) resync = true;
    _onTime = onTime;
    if (resync) await _scheduler.sync(id);
    notifyListeners();
  }

  /// Saves and schedules a reminder (FR600_001 to FR600_003).
  Future<void> createReminder(Reminder r) async {
    await _scheduler.update(r);
    await load();
  }

  /// Disables or re-enables without deleting (FR600_006).
  Future<void> toggleReminder(String id, bool on) =>
      _change(id, (r) => _scheduler.update(r, enabled: on));

  /// Changes the time of day it fires (FR600_004).
  Future<void> changeTime(String id, int hour, int minute) =>
      _change(id, (r) => _scheduler.update(r, hour: hour, minute: minute));

  /// Turns one weekday on or off (FR600_003; [weekday] 1 = Monday). The last day cannot be turned
  /// off: switch the reminder off instead.
  Future<void> toggleDay(String id, int weekday) async {
    final r = _find(id);
    if (r == null) return;
    final days = r.repeatDays.split('');
    days[weekday - 1] = days[weekday - 1] == '1' ? '0' : '1';
    if (!days.contains('1')) {
      setError(Messages.reminderNeedsADay);
      return;
    }
    setError(null);
    await _change(id, (r) => _scheduler.update(r, repeatDays: days.join()));
  }

  /// Whether the patient already has a health-logging reminder (FR600_002).
  bool get hasHealthLogReminder => switch (_reminders) {
    UiSuccess(:final data) => data.any(
      (r) => r.reminderType == ReminderType.healthLog,
    ),
    _ => false,
  };

  /// True while a health-log reminder is being added: a second tap before the first is saved
  /// made two of them (audit, 23 Oct).
  bool _adding = false;

  /// Adds a daily reminder to record health readings (FR600_002), at 8 pm unless changed.
  Future<void> addHealthLogReminder({int hour = 20, int minute = 0}) async {
    final id = _accountId;
    if (id == null || hasHealthLogReminder || _adding) return;
    _adding = true;
    try {
      await _addHealthLog(id, hour, minute);
    } finally {
      _adding = false;
    }
  }

  Future<void> _addHealthLog(String id, int hour, int minute) async {
    final res = await _scheduler.update(
      Reminder(
        reminderId: newId(),
        accountId: id,
        reminderType: ReminderType.healthLog,
        title: 'Log your health readings',
        hour: hour,
        minute: minute,
      ),
    );
    // Also clears an earlier notice such as "keep at least one day" (phone test, 9 Oct).
    setError(res is Failure ? Messages.dbUnavailable : null);
    await load();
  }

  /// Deletes a reminder the patient added. A treatment plan's exercise reminders stay with the
  /// plan (switch them off instead); they go when the plan is stopped or replaced.
  Future<void> deleteReminder(String id) async {
    final r = _find(id);
    if (r == null || r.patientPlanId != null) return;
    final res = await _scheduler.remove(r);
    // Also clears an earlier notice such as "keep at least one day" (phone test, 9 Oct).
    setError(res is Failure ? Messages.dbUnavailable : null);
    await load();
  }

  Reminder? _find(String id) => switch (_reminders) {
    UiSuccess(:final data) => data.where((r) => r.reminderId == id).firstOrNull,
    _ => null,
  };

  Future<void> _change(
    String id,
    Future<Result<Reminder>> Function(Reminder) op,
  ) async {
    final list = switch (_reminders) {
      UiSuccess(:final data) => data,
      _ => const <Reminder>[],
    };
    final i = list.indexWhere((r) => r.reminderId == id);
    if (i < 0) return;
    final res = await op(list[i]);
    if (res case Success(:final data)) {
      _reminders = UiSuccess([...list]..[i] = data);
      setError(null);
    } else {
      setError(Messages.dbUnavailable);
    }
    notifyListeners();
  }

  /// Filters the log by date (FR600_015).
  Future<void> loadLog(DateTime from, DateTime to) async {
    final id = _accountId;
    if (id == null) return;
    _log = (await _repo.getLog(id, from, to)).dataOrNull ?? const [];
    _unreadCount = (await _repo.unreadCount(id)).dataOrNull ?? 0;
    notifyListeners();
  }

  /// Clears one entry from the unread count (FR600_016).
  Future<void> markRead(String id) async {
    await _repo.markRead(id);
    final now = DateTime.now();
    await loadLog(now.subtract(const Duration(days: 14)), now);
  }
}
