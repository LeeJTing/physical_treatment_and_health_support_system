import 'package:physical_treatment_and_health_support_system/model/result.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/terms_acceptance.dart';
import 'package:physical_treatment_and_health_support_system/model/repository/terms_repository/i_terms_repository.dart';

class FakeTermsRepository implements ITermsRepository {
  final List<TermsAcceptance> rows = [];

  /// Makes the next call fail, as when the table is not there yet or offline.
  bool failNext = false;

  Result<T>? _fail<T>() {
    if (!failNext) return null;
    failNext = false;
    return const Failure('down', code: 'offline');
  }

  @override
  Future<Result<TermsAcceptance?>> latestAcceptance(String accountId) async {
    final f = _fail<TermsAcceptance?>();
    if (f != null) return f;
    final mine = rows.where((r) => r.accountId == accountId).toList()
      ..sort((a, b) => a.acceptedAt.compareTo(b.acceptedAt));
    return Success(mine.lastOrNull);
  }

  @override
  Future<Result<void>> saveAcceptance(TermsAcceptance a) async {
    final f = _fail<void>();
    if (f != null) return f;
    rows.add(a);
    return const Success(null);
  }
}
