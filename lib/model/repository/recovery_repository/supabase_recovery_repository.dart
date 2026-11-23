import 'package:physical_treatment_and_health_support_system/model/entity/recovery_check_in.dart';
import 'package:physical_treatment_and_health_support_system/model/repository/recovery_repository/i_recovery_repository.dart';
import 'package:physical_treatment_and_health_support_system/model/repository/supabase_guard.dart';
import 'package:physical_treatment_and_health_support_system/model/result.dart';
import 'package:physical_treatment_and_health_support_system/shared_client/supabase_provider/supabase_provider.dart';

class SupabaseRecoveryRepository implements IRecoveryRepository {
  final SupabaseProvider _sb;
  SupabaseRecoveryRepository(this._sb);
  @override
  Future<Result<List<RecoveryCheckIn>>> findBetween(
    String accountId,
    DateTime from,
    DateTime to,
  ) => supabaseGuard(
    () async =>
        (await _sb
                .from('recovery_check_in')
                .select()
                .eq('account_id', accountId)
                .gte('check_in_date', from.toIso8601String().substring(0, 10))
                .lte('check_in_date', to.toIso8601String().substring(0, 10))
                .order('check_in_date'))
            .map(RecoveryCheckIn.fromJson)
            .toList(),
    failMessage:
        'Recovery check-ins could not be loaded. Retry when connected.',
  );
  @override
  Future<Result<void>> save(RecoveryCheckIn value) {
    if (!value.valid(DateTime.now())) {
      return Future.value(
        const Failure(
          'Choose valid symptom scores and a date no later than today.',
        ),
      );
    }
    return supabaseGuard(
      () async {
        // Stable row identity when the same plan/day is edited. RLS checks account and plan ownership.
        await _sb
            .from('recovery_check_in')
            .upsert(
              value.toJson(),
              onConflict: 'account_id,patient_plan_id,check_in_date',
            );
      },
      failMessage:
          'Your check-in was not saved. Check your connection and try again.',
    );
  }

  @override
  Future<Result<void>> delete(String accountId, String checkInId) =>
      supabaseGuard(() async {
        await _sb
            .from('recovery_check_in')
            .delete()
            .eq('account_id', accountId)
            .eq('check_in_id', checkInId);
      }, failMessage: 'Your check-in could not be deleted. Please retry.');
}
