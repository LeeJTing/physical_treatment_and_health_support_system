import 'package:physical_treatment_and_health_support_system/core/constants/app_constants.dart';
import 'package:physical_treatment_and_health_support_system/core/utils/id_utils.dart';
import 'package:physical_treatment_and_health_support_system/device_platform/health_connect/health_data_source.dart';
import 'package:physical_treatment_and_health_support_system/model/result.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/biometric_reading.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/enums.dart';

/// What the patient can tap to fix a failed connection.
enum HealthFix {
  /// Open the Play Store page of Health Connect (install or update it).
  install,

  /// Open Health Connect's permission page for HealthGuide.
  openSettings,
}

/// Result of [HealthConnectService.connect].
class HealthConnectAttempt {
  final bool connected;

  /// What to tell the patient when not connected.
  final String? message;
  final HealthFix? fix;
  const HealthConnectAttempt(this.connected, {this.message, this.fix});
}

/// Reads biometric records from the platform health data source (Table 4.96). The only class that
/// knows about Health Connect, so an iOS HealthKit source can be added behind the same methods.
class HealthConnectService {
  final HealthDataSource _source;

  /// Blood pressure, blood glucose and body weight; read permission only (UC700 C9).
  final List<String> recordTypes = const ['BLOOD_PRESSURE', 'BLOOD_GLUCOSE', 'BODY_WEIGHT'];

  /// False when the health data source is absent from the device.
  bool isAvailable = false;

  HealthConnectService(this._source);

  Future<bool> checkAvailability() async => isAvailable = await _source.isAvailable();

  /// Why Health Connect is or is not usable (installed, needs install/update, unsupported).
  Future<HealthSourceState> state() => _source.state();

  /// Play Store page of Health Connect.
  Future<void> installOrUpdate() => _source.installOrUpdate();

  /// Health Connect's permission page for HealthGuide.
  Future<bool> openPermissionSettings() => _source.openPermissionSettings();

  /// Checks Health Connect and asks for read access (FR100_062, FR100_063), saying exactly what
  /// is wrong when it fails: not installed / too old (Play Store), or access refused (Health
  /// Connect's permission page, because Android stops asking after two refusals).
  Future<HealthConnectAttempt> connect() async {
    final s = await _source.state();
    isAvailable = s == HealthSourceState.available;
    if (s == HealthSourceState.needsInstall) {
      return const HealthConnectAttempt(false, message: Messages.healthConnectInstall, fix: HealthFix.install);
    }
    if (s == HealthSourceState.unsupported) {
      return const HealthConnectAttempt(false, message: Messages.healthConnectMissing);
    }
    if (!await _source.requestRead()) {
      return const HealthConnectAttempt(false, message: Messages.healthPermissionSteps, fix: HealthFix.openSettings);
    }
    return const HealthConnectAttempt(true);
  }

  /// Carries out [fix]: the Play Store page or Health Connect's permission page.
  Future<void> applyFix(HealthFix fix) async {
    if (fix == HealthFix.install) {
      await _source.installOrUpdate();
    } else {
      await _source.openPermissionSettings();
    }
  }

  /// Requests read access; false when any type is refused (FR100_063).
  Future<bool> requestPermissions() async {
    if (!await checkAvailability()) return false;
    return _source.requestRead();
  }

  Future<bool> hasPermissions() => _source.hasRead();

  /// Imports the records of the supported types recorded since [since] (FR200_009), tagged
  /// Imported (FR200_010). Values outside the plausible ranges are dropped (FR200_004).
  Future<Result<List<BiometricReading>>> readRecords(
    String accountId,
    DateTime since, {
    DateTime? until,
  }) async {
    try {
      if (!await _source.hasRead()) {
        return const Failure(Messages.healthPermissionRequired, code: 'permission');
      }
      final recs = await _source.read(since, until ?? DateTime.now());
      final out = <BiometricReading>[];
      for (final r in recs) {
        final m = MetricType.fromDb(r.metric);
        final reading = BiometricReading(
          readingId: newId(),
          accountId: accountId,
          metricType: m,
          primaryValue: r.value,
          secondaryValue: r.secondary,
          // Health Connect does not always say when glucose was measured: "random" then.
          measurementContext: m == MetricType.bloodGlucose ? MeasurementContext.random : null,
          source: ReadingSource.imported,
          recordedAt: r.at.toLocal(),
        );
        if (reading.isPlausible() && reading.isValidBloodPressure() && !reading.isFutureDated()) {
          out.add(reading);
        }
      }
      return Success(out);
    } catch (e) {
      return Failure(Messages.importFailed, code: 'import_failed', cause: e);
    }
  }

  /// Drops access and stops scheduled imports (FR100_065).
  Future<void> revoke() => _source.revoke();
}
