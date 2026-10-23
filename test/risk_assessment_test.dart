// UC1000 Retrieve Profile Information (RiskAssessmentService.retrieve) and the calorie target
// of the safety limits (audit, 23 Oct): every status, and the fail-safe limits where the
// profile cannot be used.
import 'package:flutter_test/flutter_test.dart';

import 'package:physical_treatment_and_health_support_system/model/business_logic/risk_assessment_service/risk_assessment_service.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/enums.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/health_profile.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/safety_limit.dart';
import 'package:physical_treatment_and_health_support_system/model/result.dart';
import 'package:physical_treatment_and_health_support_system/model/repository/auth_repository/fake_auth_repository.dart';
import 'package:physical_treatment_and_health_support_system/model/repository/profile_repository/fake_profile_repository.dart';

void main() {
  late FakeAuthRepository auth;
  late FakeProfileRepository profiles;
  late RiskAssessmentService risk;
  late String id;

  setUp(() async {
    auth = FakeAuthRepository();
    profiles = FakeProfileRepository();
    risk = RiskAssessmentService(auth, profiles);
    id = (await auth.login(
      'demo@apths.test',
      'password123',
    )).dataOrNull!.accountId;
  });

  HealthProfile complete({DateTime? updatedAt}) => HealthProfile(
    profileId: 'p1',
    accountId: id,
    age: 62,
    gender: Gender.male,
    weightKg: 71.2,
    heightCm: 168,
    updatedAt: updatedAt ?? DateTime.now(),
  );

  final failSafe = SafetyLimit.mostRestrictive();

  Future<ProfileSnapshot> snapshot() async =>
      (await risk.retrieve()).dataOrNull!;

  test('no session is the only failure (A3)', () async {
    await auth.signOut();
    final res = await risk.retrieve();
    expect(res, isA<Failure<ProfileSnapshot>>());
    expect((res as Failure).code, 'unauthenticated');
  });

  test(
    'an unreadable profile gives the fail-safe limits, status error (C5)',
    () async {
      profiles.failNext = true;
      final s = await snapshot();
      expect(s.status, ProfileStatus.error);
      expect(s.safetyLimit.maxExerciseIntensity, failSafe.maxExerciseIntensity);
      expect(
        s.safetyLimit.maxSessionDurationMin,
        failSafe.maxSessionDurationMin,
      );
      expect(s.riskLevel, RiskLevel.high); // nothing known: treated with care
    },
  );

  test('no profile yet: not configured, fail-safe limits', () async {
    final s = await snapshot();
    expect(s.status, ProfileStatus.notConfigured);
    expect(s.profile, isNull);
    expect(s.safetyLimit.maxSessionDurationMin, failSafe.maxSessionDurationMin);
  });

  test(
    'a profile with a field missing: incomplete, fail-safe limits',
    () async {
      final p = HealthProfile(
        profileId: 'p1',
        accountId: id,
        age: 62,
        updatedAt: DateTime.now(),
      );
      await profiles.saveProfile(p, p.generateSafetyLimit());
      final s = await snapshot();
      expect(s.status, ProfileStatus.incomplete);
      expect(s.profile, isNotNull);
      expect(
        s.safetyLimit.maxSessionDurationMin,
        failSafe.maxSessionDurationMin,
      );
    },
  );

  test(
    'a complete profile: its stored limit, complete; after 6 months stale',
    () async {
      final p = complete();
      final limit = p.generateSafetyLimit();
      await profiles.saveProfile(p, limit);
      var s = await snapshot();
      expect(s.status, ProfileStatus.complete);
      expect(s.safetyLimit.safetyLimitId, limit.safetyLimitId);
      expect(s.safetyLimit.maxSessionDurationMin, 45); // Low risk

      expect(
        complete(
          updatedAt: DateTime.now().subtract(const Duration(days: 183)),
        ).isStale(),
        isTrue,
      );
      expect(
        complete(
          updatedAt: DateTime.now().subtract(const Duration(days: 181)),
        ).isStale(),
        isFalse,
      );
    },
  );

  test(
    'calorie target: Mifflin-St Jeor x 1.2, fail-safe when a value is missing',
    () {
      // Man: 10 x 71.2 + 6.25 x 168 - 5 x 62 + 5 = 1457; x 1.2 = 1748.4
      expect(complete().generateSafetyLimit().dailyCalorieTarget, 1748);
      // Woman, same numbers: 1457 - 166 = 1291; x 1.2 = 1549.2
      final woman = HealthProfile(
        profileId: 'p2',
        accountId: id,
        age: 62,
        gender: Gender.female,
        weightKg: 71.2,
        heightCm: 168,
        updatedAt: DateTime.now(),
      );
      expect(woman.generateSafetyLimit().dailyCalorieTarget, 1549);
      final noAge = HealthProfile(
        profileId: 'p3',
        accountId: id,
        gender: Gender.male,
        weightKg: 71.2,
        heightCm: 168,
        updatedAt: DateTime.now(),
      );
      expect(
        noAge.generateSafetyLimit().dailyCalorieTarget,
        failSafe.dailyCalorieTarget,
      );
    },
  );
}
