import 'package:physical_treatment_and_health_support_system/model/result.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/health_profile.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/lookups.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/safety_limit.dart';

/// Contract for the profile, its declared lists and its safety limits (Table 4.59).
abstract interface class IProfileRepository {
  /// Null data means no profile has been saved yet.
  Future<Result<HealthProfile?>> getProfile(String accountId);

  /// Persists the profile, its three declaration lists and the regenerated
  /// safety limit together (FR100_053, FR100_057).
  Future<Result<void>> saveProfile(HealthProfile p, SafetyLimit limit);

  Future<Result<SafetyLimit?>> getCurrentSafetyLimit(String profileId);

  Future<Result<List<HealthCondition>>> getConditions();
  Future<Result<List<PhysicalLimitation>>> getLimitations();
  Future<Result<List<DietaryRestriction>>> getRestrictions();
}
