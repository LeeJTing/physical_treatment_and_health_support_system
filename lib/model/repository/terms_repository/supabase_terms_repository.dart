import 'package:physical_treatment_and_health_support_system/model/result.dart';
import 'package:physical_treatment_and_health_support_system/shared_client/supabase_provider/supabase_provider.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/terms_acceptance.dart';
import 'package:physical_treatment_and_health_support_system/model/repository/terms_repository/i_terms_repository.dart';
import 'package:physical_treatment_and_health_support_system/model/repository/supabase_guard.dart';

/// terms_acceptance (supabase/proposed/20261011120000_terms_and_account_deletion.sql).
class SupabaseTermsRepository implements ITermsRepository {
  final SupabaseProvider _sb;

  SupabaseTermsRepository(this._sb);

  @override
  Future<Result<TermsAcceptance?>> latestAcceptance(String accountId) =>
      supabaseGuard(() async {
        final rows = await _sb
            .from('terms_acceptance')
            .select()
            .eq('account_id', accountId)
            .order('accepted_at', ascending: false)
            .limit(1);
        return rows.isEmpty ? null : TermsAcceptance.fromJson(rows.first);
      });

  @override
  Future<Result<void>> saveAcceptance(TermsAcceptance a) =>
      supabaseGuard(() async {
        await _sb.from('terms_acceptance').insert(a.toJson());
      });
}
