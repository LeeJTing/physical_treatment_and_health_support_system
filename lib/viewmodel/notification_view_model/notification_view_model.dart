import 'package:physical_treatment_and_health_support_system/model/business_logic/local_notification_service/local_notification_service.dart';
import 'package:physical_treatment_and_health_support_system/viewmodel/base_view_model.dart';
import 'package:physical_treatment_and_health_support_system/model/result.dart';
import 'package:physical_treatment_and_health_support_system/viewmodel/ui_state.dart';
import 'package:physical_treatment_and_health_support_system/core/constants/app_constants.dart';
import 'package:physical_treatment_and_health_support_system/core/utils/id_utils.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/anomaly_event.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/enums.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/reminder.dart';
import 'package:physical_treatment_and_health_support_system/model/repository/auth_repository/i_auth_repository.dart';
import 'package:physical_treatment_and_health_support_system/model/repository/notification_repository/i_notification_repository.dart';

/// Reminder management and the notification log (Table 4.71). Alerts from M400 arrive through
/// [receiveAnomaly] (FR600_009, FR600_010).
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

  /// Reads the reminders and the log. [quiet]: the list on screen stays while it is read again
  /// (after a change), instead of being replaced by a spinner.
  Future<void> load({bool quiet = false}) async {
    if (!quiet || _reminders is! UiSuccess<List<Reminder>>) {
      _reminders = const Loading();
      notifyListeners();
    }
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
      Success(:final data) => UiSuccess(_byTime(data)),
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

  /// True while reminders are being added (the button shows a spinner).
  bool adding = false;

  /// Saves and schedules a reminder (FR600_001 to FR600_003).
  Future<void> createReminder(Reminder r) async {
    await _scheduler.update(r);
    await load(quiet: true);
  }

  /// One change at a time: a second tap waits for the first and starts from what the first
  /// saved (audit, 24 Oct: two quick day taps both started from the old days, so the second
  /// undid the first).
  Future<void> _last = Future<void>.value();
  Future<void> _oneAtATime(Future<void> Function() op) {
    final next = _last.then((_) => op());
    _last = next.then((_) {}, onError: (Object _) {});
    return next;
  }

  /// Disables or re-enables without deleting (FR600_006).
  Future<void> toggleReminder(String id, bool on) => _oneAtATime(
    () => _change(id, (r) => _scheduler.update(r, enabled: on)),
  );

  /// Changes the time of day it fires (FR600_004).
  Future<void> changeTime(String id, int hour, int minute) => _oneAtATime(
    () => _change(id, (r) => _scheduler.update(r, hour: hour, minute: minute)),
  Future<void> toggleReminder(String id, bool on) => _change(
    id,
    (r) => r.copyWith(isEnabled: on),
    (r) => _scheduler.update(r, enabled: on),
  );

  /// Changes the time of day it fires (FR600_004).
  Future<void> changeTime(String id, int hour, int minute) => _change(
    id,
    (r) => r.copyWith(hour: hour, minute: minute),
    (r) => _scheduler.update(r, hour: hour, minute: minute),
  );

  /// Turns one weekday on or off (FR600_003; [weekday] 1 = Monday). The last day cannot be turned
  /// off: switch the reminder off instead.
  Future<void> toggleDay(String id, int weekday) =>
      _oneAtATime(() => _toggleDay(id, weekday));

  Future<void> _toggleDay(String id, int weekday) async {
    final r = _find(id);
    if (r == null) return;
    final days = r.repeatDays.split('');
    days[weekday - 1] = days[weekday - 1] == '1' ? '0' : '1';
    if (!days.contains('1')) {
      setError(Messages.reminderNeedsADay);
      return;
    }
    setError(null);
    final repeat = days.join();
    await _change(
      id,
      (r) => r.copyWith(repeatDays: repeat),
      (r) => _scheduler.update(r, repeatDays: repeat),
    );
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
    if (id == null || hasHealthLogReminder || adding) return;
    adding = true;
    notifyListeners();
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
    await load(quiet: true);
    adding = false;
    notifyListeners();
  }

  /// Usual Malaysian meal times for the meal reminders (the patient can change each one).
  static const mealTimes = <MealSlot, (int, int)>{
    MealSlot.breakfast: (7, 30),
    MealSlot.lunch: (12, 30),
    MealSlot.dinner: (19, 0),
  };

  bool get hasMealReminders => switch (_reminders) {
    UiSuccess(:final data) => data.any((r) => r.reminderType == ReminderType.meal),
    _ => false,
  };

  /// Adds a daily meal reminder for breakfast, lunch and dinner (M700 with M600): tapping one
  /// opens the Diet tab to log the meal or see the plan. Slots that already have one are kept.
  Future<void> addMealReminders({Map<MealSlot, (int, int)> times = mealTimes}) async {
    final id = _accountId;
    if (id == null || adding) return;
    adding = true;
    notifyListeners();
    final have = switch (_reminders) {
      UiSuccess(:final data) =>
        data.where((r) => r.reminderType == ReminderType.meal).map((r) => r.title.split(' ').first).toSet(),
      _ => <String>{},
    };
    var failed = false;
    for (final e in times.entries) {
      if (have.contains(e.key.label)) continue;
      final res = await _scheduler.update(
        Reminder(
          reminderId: newId(),
          accountId: id,
          reminderType: ReminderType.meal,
          title: '${e.key.label} reminder',
          hour: e.value.$1,
          minute: e.value.$2,
        ),
      );
      failed = failed || res is Failure;
    }
    setError(failed ? Messages.dbUnavailable : null);
    await load(quiet: true);
    adding = false;
    notifyListeners();
  }

  /// Deletes a reminder the patient added. A treatment plan's exercise reminders stay with the
  /// plan (switch them off instead); they go when the plan is stopped or replaced.
  /// UI first: the reminder leaves the list at once and comes back if it could not be deleted.
  Future<void> deleteReminder(String id) async {
    final r = _find(id);
    if (r == null || r.patientPlanId != null) return;
    final before = _list;
    _reminders = UiSuccess(before.where((x) => x.reminderId != id).toList());
    notifyListeners();
    final res = await _scheduler.remove(r);
    if (res is Failure) _reminders = UiSuccess(before);
    // Also clears an earlier notice such as "keep at least one day" (phone test, 9 Oct).
    setError(res is Failure ? Messages.dbUnavailable : null);
    await load(quiet: true);
  }

  /// Earliest in the day first.
  static List<Reminder> _byTime(List<Reminder> list) => [...list]
    ..sort(
      (a, b) => (a.hour * 60 + a.minute).compareTo(b.hour * 60 + b.minute),
    );
  List<Reminder> get _list => switch (_reminders) {
    UiSuccess(:final data) => data,
    _ => const <Reminder>[],
  };

  Reminder? _find(String id) => switch (_reminders) {
    UiSuccess(:final data) => data.where((r) => r.reminderId == id).firstOrNull,
    _ => null,
  };

  /// UI first: [preview] is shown at once, [op] then saves and schedules it; on a failure the
  /// reminder goes back to how it was. Each step replaces the reminder in the list as it is then,
  /// so quick taps on several days do not undo each other.
  Future<void> _change(
    String id,
    Reminder Function(Reminder) preview,
    Future<Result<Reminder>> Function(Reminder) op,
  ) async {
    final original = _find(id);
    if (original == null) return;
    _replace(id, preview(original));
    notifyListeners();
    final res = await op(original);
    if (res case Success(:final data)) {
      // Kept in time order, so a changed time moves the card at once (audit, 24 Oct).
      _reminders = UiSuccess(_byTime([...list]..[i] = data));
      _replace(id, data);
      setError(null);
    } else {
      _replace(id, original);
      setError(Messages.dbUnavailable);
    }
    notifyListeners();
  }

  void _replace(String id, Reminder r) {
    _reminders = UiSuccess([for (final x in _list) x.reminderId == id ? r : x]);
  }

  /// The log's date range (FR600_015): the last two weeks until the patient picks another.
  DateTime logFrom = DateTime.now().subtract(const Duration(days: 14));
  DateTime logTo = DateTime.now();

  /// Turns an anomaly into an alert (FR600_009, FR600_010): logged, shown on the phone, counted.
  Future<void> receiveAnomaly(AnomalyEvent a) async {
    await _scheduler.receiveAnomaly(a);
    await loadLog(logFrom, DateTime.now());
  }

  /// Filters the log by date (FR600_015).
  Future<void> loadLog(DateTime from, DateTime to) async {
    final id = _accountId;
    if (id == null) return;
    logFrom = from;
    logTo = to;
    _log = (await _repo.getLog(id, from, to)).dataOrNull ?? const [];
    _unreadCount = (await _repo.unreadCount(id)).dataOrNull ?? 0;
    notifyListeners();
  }

  /// Clears one entry from the unread count (FR600_016). UI first: shown as read at once.
  Future<void> markRead(String id) async {
    final i = _log.indexWhere((n) => n.notificationId == id);
    if (i >= 0 && !_log[i].isRead) {
      _log = [..._log]..[i] = _log[i].markRead();
      if (_unreadCount > 0) _unreadCount--;
      notifyListeners();
    }
    await _repo.markRead(id);
    await loadLog(logFrom, logTo.isBefore(DateTime.now()) ? logTo : DateTime.now());
  }
}
