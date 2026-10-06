import 'package:physical_treatment_and_health_support_system/core/base/result.dart';
import 'package:physical_treatment_and_health_support_system/core/constants/app_constants.dart';
import 'package:physical_treatment_and_health_support_system/data/models/enums.dart';
import 'package:physical_treatment_and_health_support_system/data/models/health_profile.dart';
import 'package:physical_treatment_and_health_support_system/data/models/safety_limit.dart';
import 'package:physical_treatment_and_health_support_system/data/repository/interfaces/i_auth_repository.dart';
import 'package:physical_treatment_and_health_support_system/data/repository/interfaces/i_profile_repository.dart';

/// UC1000 Retrieve Profile Information, included by every use case that
/// applies the patient's profile (UC400 FR500_02, UC500, M700).
///
/// Never blocks the caller: a missing, incomplete or unreadable profile is
/// returned with the most restrictive safety limit (C5) and a status the
/// caller can act on. Only a missing session is a [Failure] (A3).
class ProfileInfoService {
  final IAuthRepository _auth;
  final IProfileRepository _profiles;

  ProfileInfoService(this._auth, this._profiles);

  Future<Result<ProfileSnapshot>> retrieve() async {
    final account = await _auth.currentAccount();
    final accountId = account.dataOrNull?.accountId;
    if (accountId == null) {
      return const Failure(Messages.sessionExpired, code: 'unauthenticated');
    }

    final failSafe = SafetyLimit.mostRestrictive();
    final profileResult = await _profiles.getProfile(accountId);
    if (profileResult is Failure<HealthProfile?>) {
      return Success(ProfileSnapshot(accountId: accountId, safetyLimit: failSafe, status: ProfileStatus.error));
    }
    final profile = profileResult.dataOrNull;
    if (profile == null) {
      return Success(ProfileSnapshot(accountId: accountId, safetyLimit: failSafe, status: ProfileStatus.notConfigured));
    }
    if (!profile.isComplete) {
      return Success(ProfileSnapshot(
          accountId: accountId, profile: profile, safetyLimit: failSafe, status: ProfileStatus.incomplete));
    }

    final stored = (await _profiles.getCurrentSafetyLimit(profile.profileId)).dataOrNull;
    return Success(ProfileSnapshot(
      accountId: accountId,
      profile: profile,
      safetyLimit: stored ?? profile.generateSafetyLimit(),
      status: profile.isStale() ? ProfileStatus.stale : ProfileStatus.complete,
    ));
  }
}
