import 'package:physical_treatment_and_health_support_system/model/result.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/health_profile.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/lookups.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/safety_limit.dart';
import 'package:physical_treatment_and_health_support_system/model/repository/profile_repository/i_profile_repository.dart';

class FakeProfileRepository implements IProfileRepository {
  final Map<String, HealthProfile> _profiles = {};
  final Map<String, SafetyLimit> _limits = {};
  bool failNext = false; // lets tests simulate a lost connection

  @override
  Future<Result<HealthProfile?>> getProfile(String accountId) async {
    if (failNext) {
      failNext = false;
      return const Failure(
        'Unable to retrieve your health information.',
        code: 'offline',
      );
    }
    return Success(_profiles[accountId]);
  }

  @override
  Future<Result<void>> saveProfile(HealthProfile p, SafetyLimit limit) async {
    final prev = _profiles[p.accountId];
    _profiles[p.accountId] = p.copyWith(
      version: (prev?.version ?? 0) + 1,
      updatedAt: DateTime.now(),
    );
    _limits[p.profileId] = limit;
    return const Success(null);
  }

  @override
  Future<Result<SafetyLimit?>> getCurrentSafetyLimit(String profileId) async =>
      Success(_limits[profileId]);

  @override
  Future<Result<List<HealthCondition>>> getConditions() async =>
      const Success(LookupSeed.conditions);

  @override
  Future<Result<List<PhysicalLimitation>>> getLimitations() async =>
      const Success(LookupSeed.limitations);

  @override
  Future<Result<List<DietaryRestriction>>> getRestrictions() async =>
      const Success(<DietaryRestriction>[]);
}
