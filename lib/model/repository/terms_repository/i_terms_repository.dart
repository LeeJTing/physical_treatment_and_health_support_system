import 'package:physical_treatment_and_health_support_system/model/result.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/terms_acceptance.dart';

/// Acceptances of the Terms of Use and Privacy Notice (11 Oct).
abstract interface class ITermsRepository {
  /// The account's most recent acceptance, or null when it never accepted.
  Future<Result<TermsAcceptance?>> latestAcceptance(String accountId);

  /// Records an acceptance (a new row each time; rows are never changed).
  Future<Result<void>> saveAcceptance(TermsAcceptance a);
}
