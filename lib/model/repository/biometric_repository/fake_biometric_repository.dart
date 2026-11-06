import 'package:physical_treatment_and_health_support_system/model/result.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/biometric_reading.dart';
import 'package:physical_treatment_and_health_support_system/model/repository/biometric_repository/i_biometric_repository.dart';

/// In-memory readings for USE_FAKES and the tests.
class FakeBiometricRepository implements IBiometricRepository {
  final List<BiometricReading> readings = [];
  final Map<String, ({bool connected, DateTime? lastSync})> sources = {};
  bool failNext = false;

  Failure<T>? _fail<T>() {
    if (!failNext) return null;
    failNext = false;
    return Failure<T>('offline', code: 'offline');
  }

  @override
  Future<Result<void>> insert(BiometricReading r) async {
    final f = _fail<void>();
    if (f != null) return f;
    if (readings.any((x) => x.duplicateKey() == r.duplicateKey())) {
      return const Failure('duplicate', code: '23505');
    }
    readings.add(r);
    return const Success(null);
  }

  @override
  Future<Result<int>> insertBatch(List<BiometricReading> rs) async {
    final f = _fail<int>();
    if (f != null) return f;
    var n = 0;
    for (final r in rs) {
      final dup = readings.any(
        (x) => x.accountId == r.accountId && x.duplicates(r),
      );
      if (!dup) {
        readings.add(r);
        n++;
      }
    }
    return Success(n);
  }

  @override
  Future<Result<List<BiometricReading>>> findBetween(
    String accountId,
    DateTime a,
    DateTime b,
  ) async {
    final f = _fail<List<BiometricReading>>();
    if (f != null) return f;
    return Success(
      readings
          .where(
            (r) =>
                r.accountId == accountId &&
                !r.recordedAt.isBefore(a) &&
                !r.recordedAt.isAfter(b),
          )
          .toList()
        ..sort((x, y) => x.recordedAt.compareTo(y.recordedAt)),
    );
  }

  @override
  Future<Result<void>> delete(String readingId) async {
    final f = _fail<void>();
    if (f != null) return f;
    readings.removeWhere((r) => r.readingId == readingId);
    return const Success(null);
  }

  @override
  Future<Result<({bool connected, DateTime? lastSync})>> healthSourceState(
    String accountId,
  ) async => Success(sources[accountId] ?? (connected: false, lastSync: null));

  @override
  Future<Result<void>> setHealthSourceConnected(String accountId, bool on) async {
    final s = sources[accountId];
    sources[accountId] = (connected: on, lastSync: on ? s?.lastSync : null);
    return const Success(null);
  }

  @override
  Future<Result<void>> recordImport(String accountId, DateTime at) async {
    sources[accountId] = (connected: true, lastSync: at);
    return const Success(null);
  }
}
