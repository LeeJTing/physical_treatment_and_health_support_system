import 'package:physical_treatment_and_health_support_system/model/entity/recovery_check_in.dart';
import 'package:physical_treatment_and_health_support_system/model/repository/recovery_repository/i_recovery_repository.dart';
import 'package:physical_treatment_and_health_support_system/model/result.dart';

class FakeRecoveryRepository implements IRecoveryRepository {
  final List<RecoveryCheckIn> rows;
  FakeRecoveryRepository([List<RecoveryCheckIn>? initial])
    : rows = [...?initial];
  @override
  Future<Result<List<RecoveryCheckIn>>> findBetween(
    String accountId,
    DateTime from,
    DateTime to,
  ) async => Success(
    rows
        .where(
          (r) =>
              r.accountId == accountId &&
              !r.date.isBefore(from) &&
              !r.date.isAfter(to),
        )
        .toList()
      ..sort((a, b) => a.date.compareTo(b.date)),
  );
  @override
  Future<Result<void>> save(RecoveryCheckIn value) async {
    if (!value.valid(DateTime.now())) return const Failure('Invalid check-in');
    rows.removeWhere(
      (r) =>
          r.accountId == value.accountId &&
          r.patientPlanId == value.patientPlanId &&
          r.date == value.date,
    );
    rows.add(value);
    return const Success(null);
  }

  @override
  Future<Result<void>> delete(String accountId, String checkInId) async {
    rows.removeWhere(
      (r) => r.accountId == accountId && r.checkInId == checkInId,
    );
    return const Success(null);
  }
}
