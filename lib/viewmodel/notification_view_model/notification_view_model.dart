import 'package:physical_treatment_and_health_support_system/model/business_logic/local_notification_service/local_notification_service.dart';
import 'package:physical_treatment_and_health_support_system/viewmodel/base_view_model.dart';
import 'package:physical_treatment_and_health_support_system/model/result.dart';
import 'package:physical_treatment_and_health_support_system/viewmodel/ui_state.dart';
import 'package:physical_treatment_and_health_support_system/core/constants/app_constants.dart';
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
