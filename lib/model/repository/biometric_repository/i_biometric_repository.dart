import 'package:physical_treatment_and_health_support_system/model/result.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/biometric_reading.dart';

/// Contract for biometric readings (Table 4.77) and the health data source connection state kept
/// on the account (FR100_062 to FR100_065, FR200_012).
abstract interface class IBiometricRepository {
  /// Writes one reading (FR200_024).
  Future<Result<void>> insert(BiometricReading r);

  /// Bulk import; a reading within 5 minutes of a stored one of the same metric is discarded
  /// (FR200_011). Returns how many were stored.
  Future<Result<int>> insertBatch(List<BiometricReading> rs);

  /// Readings recorded between [a] and [b], oldest first (FR200_017).
  Future<Result<List<BiometricReading>>> findBetween(
    String accountId,
    DateTime a,
    DateTime b,
  );

  /// Removes one entry (FR200_022).
  Future<Result<void>> delete(String readingId);

  /// Connection state of the health data source (FR100_064).
  Future<Result<({bool connected, DateTime? lastSync})>> healthSourceState(
    String accountId,
  );

  /// Records that the patient granted or revoked access (FR100_062, FR100_065).
  Future<Result<void>> setHealthSourceConnected(String accountId, bool on);

  /// Records the time of the most recent successful import (FR200_012).
  Future<Result<void>> recordImport(String accountId, DateTime at);
}
