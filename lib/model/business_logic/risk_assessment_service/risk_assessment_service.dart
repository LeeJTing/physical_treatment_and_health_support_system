import 'package:physical_treatment_and_health_support_system/model/result.dart';
import 'package:physical_treatment_and_health_support_system/core/constants/app_constants.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/enums.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/health_profile.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/safety_limit.dart';
import 'package:physical_treatment_and_health_support_system/model/repository/auth_repository/i_auth_repository.dart';
import 'package:physical_treatment_and_health_support_system/model/repository/profile_repository/i_profile_repository.dart';

/// Risk assessment (service layer of the software architecture, M100): assigns the risk
/// level from the declared conditions and limitations (Table 3.3, FR100_054), generates
/// the safety limits (FR100_055), and serves UC1000 Retrieve Profile Information to every
/// module that applies them (UC400 FR500_02, UC500, M700).
///
/// [retrieve] never blocks the caller: a missing, incomplete or unreadable profile is
/// returned with the most restrictive safety limit (C5) and a status the caller can act
/// on. Only a missing session is a [Failure] (A3).
class RiskAssessmentService {
  final IAuthRepository _auth;
  final IProfileRepository _profiles;

  RiskAssessmentService(this._auth, this._profiles);

  /// Risk level of a profile (Table 3.3 rule set, kept on HealthProfile as in Chapter 4).
  RiskLevel assessRisk(HealthProfile p) => p.assignRiskLevel();

  /// Safety limits for a profile about to be saved (FR100_055, FR100_057).
  SafetyLimit generateSafetyLimit(HealthProfile p) => p.generateSafetyLimit();

  Future<Result<ProfileSnapshot>> retrieve() async {
    final account = await _auth.currentAccount();
    final accountId = account.dataOrNull?.accountId;
    if (accountId == null) {
      return const Failure(Messages.sessionExpired, code: 'unauthenticated');
    }

    final failSafe = SafetyLimit.mostRestrictive();
    final profileResult = await _profiles.getProfile(accountId);
    if (profileResult is Failure<HealthProfile?>) {
      return Success(
        ProfileSnapshot(
          accountId: accountId,
          safetyLimit: failSafe,
          status: ProfileStatus.error,
        ),
      );
    }
    final profile = profileResult.dataOrNull;
    if (profile == null) {
      return Success(
        ProfileSnapshot(
          accountId: accountId,
          safetyLimit: failSafe,
          status: ProfileStatus.notConfigured,
        ),
      );
    }
    if (!profile.isComplete) {
      return Success(
        ProfileSnapshot(
          accountId: accountId,
          profile: profile,
          safetyLimit: failSafe,
          status: ProfileStatus.incomplete,
        ),
      );
    }

    final stored = (await _profiles.getCurrentSafetyLimit(
      profile.profileId,
    )).dataOrNull;
    return Success(
      ProfileSnapshot(
        accountId: accountId,
        profile: profile,
        safetyLimit: stored ?? profile.generateSafetyLimit(),
        status: profile.isStale()
            ? ProfileStatus.stale
            : ProfileStatus.complete,
      ),
    );
  }
}
