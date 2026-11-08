import 'dart:async';

import 'package:physical_treatment_and_health_support_system/core/constants/app_constants.dart';
import 'package:physical_treatment_and_health_support_system/core/utils/id_utils.dart';
import 'package:physical_treatment_and_health_support_system/model/business_logic/health_connect_service/health_connect_service.dart';
import 'package:physical_treatment_and_health_support_system/model/business_logic/local_notification_service/local_notification_service.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/biometric_reading.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/enums.dart';
import 'package:physical_treatment_and_health_support_system/model/repository/auth_repository/i_auth_repository.dart';
import 'package:physical_treatment_and_health_support_system/model/repository/biometric_repository/i_biometric_repository.dart';
import 'package:physical_treatment_and_health_support_system/model/repository/treatment_repository/activity_records.dart';
import 'package:physical_treatment_and_health_support_system/model/repository/treatment_repository/i_treatment_repository.dart';
import 'package:physical_treatment_and_health_support_system/model/result.dart';
import 'package:physical_treatment_and_health_support_system/viewmodel/base_view_model.dart';
import 'package:physical_treatment_and_health_support_system/viewmodel/ui_state.dart';

/// What the Tracking screen shows for the selected period.
class MonitoringData {
  final List<BiometricReading> readings;
  final List<ActivityRecord> sessions;
  final PeriodSummary summary;

  const MonitoringData(this.readings, this.sessions, this.summary);

  bool get isEmpty => readings.isEmpty && sessions.isEmpty;

  List<BiometricReading> of(MetricType m) =>
      readings.where((r) => r.metricType == m).toList();

  /// Newest first, as the Monitoring Screen lists them (UI Design).
  List<BiometricReading> get recentFirst =>
      [...readings]..sort((a, b) => b.recordedAt.compareTo(a.recordedAt));
}

/// Biometric entry, import, and the history and trend state (Table 4.70; UC700 Track Health).
class MonitoringViewModel extends BaseViewModel {
  final IBiometricRepository _repo;
  final HealthConnectService _healthSource;
  final IAuthRepository _auth;
  final ITreatmentRepository _treatments;
  final LocalNotificationService? _notifications;
  final DateTime Function() _now;

  MonitoringViewModel(
    this._repo,
    this._healthSource,
    this._auth,
    this._treatments, [
    this._notifications,
    DateTime Function()? now,
  ]) : _now = now ?? DateTime.now;

  String? _accountId;
  String? get accountId => _accountId;

  UiState<MonitoringData> state = const Idle();
  MonitoringData? _cache; // shown again when a reload fails (UC700 E1)

  /// True while another period is loaded over the one on screen (a thin progress bar).
  bool reloading = false;

  /// Selected period; rejected when the start is after the end (FR200_020).
  late DateTime rangeStart = _dayStart(
    _now().subtract(const Duration(days: AppConstants.defaultRangeDays - 1)),
  );
  late DateTime rangeEnd = _now();

  /// 7, 30, 90 or null for a custom range (UC700 C13).
  int? rangeDays = AppConstants.defaultRangeDays;

  /// Health Connect connection state (FR100_064).
  bool connected = false;
  DateTime? lastSync;
  bool importing = false;
  bool _overdueTold = false;

  /// One-off message for a SnackBar (M5, M14, M15, ...); read with [takeMessage].
  String? _message;
  String? takeMessage() {
    final m = _message;
    _message = null;
    return m;
  }

  static DateTime _dayStart(DateTime d) => DateTime(d.year, d.month, d.day);
  static DateTime _dayEnd(DateTime d) => DateTime(d.year, d.month, d.day, 23, 59, 59, 999);

  MonitoringData? get data => switch (state) {
    UiSuccess(:final data) => data,
    _ => _cache,
  };

  /// Opens the screen: the default 30 days (UC700 C1), the connection state, and an import when
  /// one is due (on foreground, every 6 h; UC700 C10).
  Future<void> load() async {
    _accountId ??= (await _auth.currentAccount()).dataOrNull?.accountId;
    final id = _accountId;
    if (id == null) {
      state = const UiError(Messages.sessionExpired);
      notifyListeners();
      return;
    }
    final src = (await _repo.healthSourceState(id)).dataOrNull;
    connected = src?.connected ?? false;
    lastSync = src?.lastSync;
    await loadRange(rangeStart, rangeEnd, days: rangeDays);
    if (connected) {
      // Always look for new readings when the screen opens (no Import button needed).
      await importFromHealthSource(quiet: true);
      final after = lastSync;
      // FR200_013: told once per app session when nothing was imported for 24 hours.
      if (!_overdueTold &&
          (after == null || _now().difference(after) >= AppConstants.importOverdueAfter)) {
        _overdueTold = true;
        _message = Messages.importOverdue;
        await _notifications?.importOverdue(id);
        notifyListeners();
      }
    }
  }

  /// A preset period ending today.
  Future<void> selectDays(int days) {
    final end = _now();
    return loadRange(_dayStart(end.subtract(Duration(days: days - 1))), end, days: days);
  }

  /// Loads readings and sessions for the trend (FR200_017, FR200_018). False when the range is
  /// invalid (M9).
  Future<bool> loadRange(DateTime start, DateTime end, {int? days}) async {
    if (start.isAfter(end)) {
      _message = Messages.invalidDateRange; // A5.1
      notifyListeners();
      return false;
    }
    final id = _accountId;
    if (id == null) return false;
    rangeStart = _dayStart(start);
    rangeEnd = _dayEnd(end);
    rangeDays = days;
    if (_cache == null) {
      state = const Loading();
    } else {
      reloading = true; // the chip is selected at once; the old period stays until the new arrives
    }
    notifyListeners();
    final r = await _repo.findBetween(id, rangeStart, rangeEnd);
    final s = await _treatments.completedSessions(id, rangeStart, rangeEnd);
    reloading = false;
    if (r is Failure) {
      state = const UiError(Messages.historyRetrievalFailed); // E1; the cache stays visible
      notifyListeners();
      return true;
    }
    final readings = r.dataOrNull!;
    final sessions = s.dataOrNull ?? const <ActivityRecord>[];
    final d = MonitoringData(readings, sessions, PeriodSummary.of(readings, sessions));
    _cache = d;
    state = UiSuccess(d);
    notifyListeners();
    return true;
  }

  /// Aggregate for the selected period (FR200_019).
  PeriodSummary summary() =>
      data?.summary ?? PeriodSummary.of(const [], const []);

  /// Checks a reading before it is saved: every required field (M4), the plausible ranges (M6),
  /// systolic above diastolic and no future time. Null when it may be saved.
  String? validate({
    required MetricType metric,
    double? primary,
    double? secondary,
    MeasurementContext? context,
    required DateTime recordedAt,
  }) {
    if (primary == null ||
        (metric == MetricType.bloodPressure && secondary == null) ||
        (metric == MetricType.bloodGlucose && context == null)) {
      return Messages.emptyField; // FR200_007
    }
    final r = _draft(metric, primary, secondary, context, recordedAt, 'x');
    if (!r.isPlausible()) return Messages.implausibleValue; // FR200_004
    if (!r.isValidBloodPressure()) return Messages.systolicNotAboveDiastolic; // FR200_005
    if (r.isFutureDated(_now())) return Messages.futureReading; // FR200_006
    return null;
  }

  BiometricReading _draft(
    MetricType metric,
    double primary,
    double? secondary,
    MeasurementContext? context,
    DateTime recordedAt,
    String accountId,
  ) => BiometricReading(
    readingId: newId(),
    accountId: accountId,
    metricType: metric,
    primaryValue: primary,
    secondaryValue: metric == MetricType.bloodPressure ? secondary : null,
    measurementContext: metric == MetricType.bloodGlucose ? context : null,
    source: ReadingSource.manual, // FR200_010
    recordedAt: recordedAt,
  );

  /// Validates and saves a manual reading (FR200_001 to FR200_008). Returns the message to show on
  /// the form when it is rejected (the form keeps its values, FR200_008), or null when saved.
  Future<String?> addReading({
    required MetricType metric,
    double? primary,
    double? secondary,
    MeasurementContext? context,
    required DateTime recordedAt,
  }) async {
    final problem = validate(
      metric: metric,
      primary: primary,
      secondary: secondary,
      context: context,
      recordedAt: recordedAt,
    );
    if (problem != null) return problem;
    final id = _accountId;
    if (id == null) return Messages.sessionExpired;
    final reading = _draft(metric, primary!, secondary, context, recordedAt, id);
    setLoading(true);
    final res = await _repo.insert(reading);
    setLoading(false);
    if (res is Failure) return Messages.readingSaveFailed; // E2
    _message = Messages.readingSaved; // M5
    // UI first: the reading is on the trend as soon as it is stored; the period is then read again
    // in the background instead of keeping the form open for it.
    if (!reading.recordedAt.isBefore(rangeStart)) _show([...?data?.readings, reading]);
    unawaited(loadRange(rangeStart, _now(), days: rangeDays));
    return null;
  }

  /// Puts [readings] on screen at once, with the period's summary worked out again.
  void _show(List<BiometricReading> readings) {
    final sessions = data?.sessions ?? const <ActivityRecord>[];
    final d = MonitoringData(readings, sessions, PeriodSummary.of(readings, sessions));
    _cache = d;
    state = UiSuccess(d);
    notifyListeners();
  }

  /// What a Fix button does after a failed connection (null: none).
  HealthFix? healthFix;

  /// The Fix button: Play Store or Health Connect's permission page.
  Future<void> fixHealthSource() async {
    final f = healthFix;
    if (f != null) await _healthSource.applyFix(f);
  }

  Timer? _autoSync;

  /// Keeps Health Connect in step while the app is open: an import every
  /// [AppConstants.autoSyncEvery] and one at once (call [syncNow] again when the app returns to
  /// the front). Quiet: a SnackBar only when new readings arrived. Started by the app shell.
  void startAutoSync({Duration every = AppConstants.autoSyncEvery}) {
    _autoSync?.cancel();
    _autoSync = Timer.periodic(every, (_) => syncNow());
    syncNow();
  }

  void stopAutoSync() {
    _autoSync?.cancel();
    _autoSync = null;
  }

  /// One quiet import if Health Connect is connected; nothing otherwise.
  Future<void> syncNow() async {
    if (importing || isDisposed) return;
    _accountId ??= (await _auth.currentAccount()).dataOrNull?.accountId;
    final id = _accountId;
    if (id == null) return;
    if (!connected) {
      final src = (await _repo.healthSourceState(id)).dataOrNull;
      connected = src?.connected ?? false;
      lastSync = src?.lastSync ?? lastSync;
      if (!connected) return;
    }
    await importFromHealthSource(quiet: true);
  }

  @override
  void dispose() {
    stopAutoSync();
    super.dispose();
  }

  /// Grants read access to Health Connect and records the connection (FR100_062, FR100_063).
  Future<bool> connect() async {
    final id = _accountId;
    if (id == null) return false;
    final attempt = await _healthSource.connect();
    healthFix = attempt.fix;
    if (!attempt.connected) {
      _message = attempt.message; // A1.1 M1
      notifyListeners();
      return false;
    }
    await _repo.setHealthSourceConnected(id, true);
    connected = true;
    notifyListeners();
    await importFromHealthSource();
    return true;
  }

  /// Revokes the access and stops scheduled imports (FR100_065).
  Future<void> disconnect() async {
    final id = _accountId;
    if (id == null) return;
    await _healthSource.revoke();
    await _repo.setHealthSourceConnected(id, false);
    connected = false;
    lastSync = null;
    notifyListeners();
  }

  /// Pulls the records since the last import, discards duplicates and records the sync time
  /// (FR200_009 to FR200_012). On a failure the stored readings and the connection stay
  /// (FR200_014). Returns how many readings were added.
  Future<int> importFromHealthSource({bool quiet = false}) async {
    final id = _accountId;
    if (id == null || importing) return 0;
    importing = true;
    notifyListeners();
    try {
      if (!await _healthSource.hasPermissions()) {
        if (!quiet) _message = Messages.healthPermissionRequired;
        return 0;
      }
      final since = lastSync?.subtract(const Duration(minutes: 5)) ??
          _now().subtract(const Duration(days: 90));
      final read = await _healthSource.readRecords(id, since, until: _now());
      if (read is Failure) {
        _message = Messages.importFailed; // E3
        return 0;
      }
      final stored = await _repo.insertBatch(read.dataOrNull!);
      if (stored is Failure) {
        _message = Messages.importFailed;
        return 0;
      }
      final at = _now();
      await _repo.recordImport(id, at);
      lastSync = at;
      final n = stored.dataOrNull ?? 0;
      if (!quiet || n > 0) {
        _message = n == 0
            ? 'No new readings in Health Connect.'
            : 'Imported $n reading${n == 1 ? '' : 's'} from Health Connect.';
      }
      // The trend only changes when something new came in (auto sync runs every minute).
      if (n > 0 || !quiet) await loadRange(rangeStart, _now(), days: rangeDays);
      return n;
    } finally {
      importing = false;
      notifyListeners();
    }
  }

  /// Deletes one entry after the View's confirmation (FR200_022, FR200_023). UI first: the entry
  /// leaves the list and the trend at once and comes back if the deletion fails.
  Future<bool> deleteReading(String readingId) async {
    final kept = data?.readings;
    if (kept != null) _show(kept.where((r) => r.readingId != readingId).toList());
    final res = await _repo.delete(readingId);
    if (res is Failure) {
      if (kept != null) _show(kept);
      _message = Messages.deletionFailed; // E4
      notifyListeners();
      return false;
    }
    unawaited(loadRange(rangeStart, rangeEnd, days: rangeDays));
    return true;
  }

  /// The newest reading of each metric, for the Home vitals.
  BiometricReading? latest(MetricType m) {
    final rs = data?.of(m) ?? const <BiometricReading>[];
    return rs.isEmpty ? null : rs.last;
  }
}
