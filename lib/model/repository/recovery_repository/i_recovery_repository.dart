import 'package:physical_treatment_and_health_support_system/model/entity/recovery_check_in.dart';
import 'package:physical_treatment_and_health_support_system/model/result.dart';

abstract interface class IRecoveryRepository {
  Future<Result<List<RecoveryCheckIn>>> findBetween(
    String accountId,
    DateTime from,
    DateTime to,
  );
  Future<Result<void>> save(RecoveryCheckIn value);
  Future<Result<void>> delete(String accountId, String checkInId);
}
