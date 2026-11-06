import 'package:flutter/services.dart';
import 'package:health/health.dart';

/// One record read from the platform health data source, before it becomes a BiometricReading.
class HealthRecord {
  /// BLOOD_PRESSURE, BLOOD_GLUCOSE or BODY_WEIGHT (biometric_reading.metric_type).
  final String metric;
  final double value;

  /// Diastolic, for blood pressure.
  final double? secondary;
  final DateTime at;

  const HealthRecord(this.metric, this.value, this.at, {this.secondary});
}

/// Why Health Connect can or cannot be used on this phone.
enum HealthSourceState {
  /// Installed and usable.
  available,

  /// Android 13 or older without the Health Connect app, or with an old version of it: the
  /// Play Store page fixes it ([HealthDataSource.installOrUpdate]).
  needsInstall,

  /// Not offered on this device at all (e.g. Android older than 9, or not Android).
  unsupported,
}

/// Device Platform layer: the phone's health data store (Health Connect on Android). Kept behind
/// an interface so an iOS HealthKit source, or a fake in the tests, fits the same methods.
abstract interface class HealthDataSource {
  /// Health Connect is installed and usable (FR100_066).
  Future<bool> isAvailable();

  /// Why it is or is not usable, so the app can say what to do.
  Future<HealthSourceState> state();

  /// Opens the Play Store page of Health Connect (install or update).
  Future<void> installOrUpdate();

  /// Opens Health Connect's permission page for this app, where refused types can be allowed
  /// again (Android stops showing the request dialog after the patient refuses twice).
  Future<bool> openPermissionSettings();

  /// Asks for read access to blood pressure, blood glucose and weight (UC700 C9). True only when
  /// every type was granted (FR100_063).
  Future<bool> requestRead();

  /// Whether read access to every type is held now, without asking.
  Future<bool> hasRead();

  /// Records of the supported types between [from] and [to] (FR200_009).
  Future<List<HealthRecord>> read(DateTime from, DateTime to);

  /// Drops the access (FR100_065).
  Future<void> revoke();
}

/// Health Connect through the `health` plugin (android/app/src/main/AndroidManifest.xml declares
/// the three read permissions and the permission-rationale intent).
class PluginHealthDataSource implements HealthDataSource {
  final Health _health = Health();
  bool _configured = false;

  static const _types = [
    HealthDataType.BLOOD_PRESSURE_SYSTOLIC,
    HealthDataType.BLOOD_PRESSURE_DIASTOLIC,
    HealthDataType.BLOOD_GLUCOSE,
    HealthDataType.WEIGHT,
  ];
  static final _read = _types.map((_) => HealthDataAccess.READ).toList();

  Future<void> _init() async {
    if (_configured) return;
    await _health.configure();
    _configured = true;
  }

  static const _settings = MethodChannel('apths/settings');

  @override
  Future<bool> isAvailable() async => await state() == HealthSourceState.available;

  @override
  Future<HealthSourceState> state() async {
    try {
      await _init();
      return switch (await _health.getHealthConnectSdkStatus()) {
        HealthConnectSdkStatus.sdkAvailable => HealthSourceState.available,
        // Not installed, or too old (Android 9 to 13 need the Health Connect app). The Play
        // Store page is the fix in both cases.
        HealthConnectSdkStatus.sdkUnavailableProviderUpdateRequired ||
        HealthConnectSdkStatus.sdkUnavailable => HealthSourceState.needsInstall,
        null => HealthSourceState.unsupported,
      };
    } catch (_) {
      return HealthSourceState.unsupported;
    }
  }

  @override
  Future<void> installOrUpdate() async {
    try {
      await _init();
      await _health.installHealthConnect();
    } catch (_) {
      // No Play Store: the message on screen says what to install.
    }
  }

  @override
  Future<bool> openPermissionSettings() async {
    try {
      return await _settings.invokeMethod<bool>('openHealthConnectPermissions') ?? false;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> requestRead() async {
    try {
      await _init();
      final ok = await _health.requestAuthorization(_types, permissions: _read);
      // Health Connect only gives the 30 days before the first grant unless this extra permission
      // is held too (Android 14+, READ_HEALTH_DATA_HISTORY in the manifest). Optional: the
      // connection works without it.
      if (ok) {
        try {
          if (await _health.isHealthDataHistoryAvailable() &&
              !await _health.isHealthDataHistoryAuthorized()) {
            await _health.requestHealthDataHistoryAuthorization();
          }
        } catch (_) {
          // Older Health Connect: recent readings only.
        }
      }
      return ok;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> hasRead() async {
    try {
      await _init();
      return await _health.hasPermissions(_types, permissions: _read) ?? false;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<List<HealthRecord>> read(DateTime from, DateTime to) async {
    await _init();
    final points = await _health.getHealthDataFromTypes(
      types: _types,
      startTime: from,
      endTime: to,
    );
    double? numOf(HealthDataPoint p) {
      final v = p.value;
      return v is NumericHealthValue ? v.numericValue.toDouble() : null;
    }

    final out = <HealthRecord>[];
    final systolic = points.where((p) => p.type == HealthDataType.BLOOD_PRESSURE_SYSTOLIC);
    final diastolic = points.where((p) => p.type == HealthDataType.BLOOD_PRESSURE_DIASTOLIC).toList();
    for (final s in systolic) {
      final v = numOf(s);
      final d = diastolic.where((x) => x.dateFrom == s.dateFrom).firstOrNull;
      final dv = d == null ? null : numOf(d);
      if (v != null && dv != null) {
        out.add(HealthRecord('BLOOD_PRESSURE', v, s.dateFrom, secondary: dv));
      }
    }
    for (final p in points.where((p) => p.type == HealthDataType.BLOOD_GLUCOSE)) {
      var v = numOf(p);
      if (v == null) continue;
      // The plugin reports glucose in mg/dL; the app stores mmol/L.
      if (p.unit.name.toUpperCase().contains('MILLIGRAM')) v = v / 18.016;
      out.add(HealthRecord('BLOOD_GLUCOSE', double.parse(v.toStringAsFixed(1)), p.dateFrom));
    }
    for (final p in points.where((p) => p.type == HealthDataType.WEIGHT)) {
      final v = numOf(p);
      if (v != null) out.add(HealthRecord('BODY_WEIGHT', double.parse(v.toStringAsFixed(1)), p.dateFrom));
    }
    return out;
  }

  @override
  Future<void> revoke() async {
    try {
      await _init();
      await _health.revokePermissions();
    } catch (_) {
      // Nothing to revoke (Health Connect missing or never granted).
    }
  }
}

/// No health data source (USE_FAKES on a desktop, or tests): a few plausible records so the
/// import path can be tried without a phone.
class FakeHealthDataSource implements HealthDataSource {
  bool available;
  bool granted;
  bool failRead;
  final List<HealthRecord> records;

  FakeHealthDataSource({
    this.available = true,
    this.granted = false,
    this.failRead = false,
    List<HealthRecord>? records,
  }) : records = records ?? [];

  bool installRequested = false;
  bool settingsOpened = false;

  @override
  Future<bool> isAvailable() async => available;

  @override
  Future<HealthSourceState> state() async =>
      available ? HealthSourceState.available : HealthSourceState.needsInstall;

  @override
  Future<void> installOrUpdate() async => installRequested = true;

  @override
  Future<bool> openPermissionSettings() async => settingsOpened = true;

  @override
  Future<bool> requestRead() async => granted = available;

  @override
  Future<bool> hasRead() async => granted;

  @override
  Future<List<HealthRecord>> read(DateTime from, DateTime to) async {
    if (failRead) throw StateError('read failed');
    return records.where((r) => !r.at.isBefore(from) && !r.at.isAfter(to)).toList();
  }

  @override
  Future<void> revoke() async => granted = false;
}
