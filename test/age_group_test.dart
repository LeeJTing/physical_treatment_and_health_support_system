// The profile age must agree with the age group accepted in the Terms (14 Oct), and the
// height and weight limits are the largest ever recorded (272 cm, 635 kg).
import 'package:flutter_test/flutter_test.dart';

import 'package:physical_treatment_and_health_support_system/core/constants/app_constants.dart';
import 'package:physical_treatment_and_health_support_system/model/business_logic/risk_assessment_service/risk_assessment_service.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/enums.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/health_profile.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/terms_acceptance.dart';
import 'package:physical_treatment_and_health_support_system/model/repository/auth_repository/fake_auth_repository.dart';
import 'package:physical_treatment_and_health_support_system/model/repository/profile_repository/fake_profile_repository.dart';
import 'package:physical_treatment_and_health_support_system/model/repository/terms_repository/fake_terms_repository.dart';
import 'package:physical_treatment_and_health_support_system/viewmodel/auth_view_model/auth_view_model.dart';
import 'package:physical_treatment_and_health_support_system/viewmodel/profile_view_model/profile_view_model.dart';
import 'package:physical_treatment_and_health_support_system/viewmodel/ui_state.dart';

void main() {
  late FakeAuthRepository auth;
  late FakeProfileRepository profiles;
  late FakeTermsRepository terms;
  late ProfileViewModel vm;
  late String id;

  void accepted(TermsAgeGroup group) => terms.rows.add(
    TermsAcceptance(
      acceptanceId: 't${terms.rows.length}',
      accountId: id,
      termsVersion: AppConstants.termsVersion,
      acceptedAt: DateTime(2026, 10, 14, 9, terms.rows.length),
      language: 'en',
      healthDataConsent: true,
      ageGroup: group,
      guardianName: group == TermsAgeGroup.minor ? 'Tan Mei Ling' : null,
      guardianRelationship: group == TermsAgeGroup.minor ? 'PARENT' : null,
    ),
  );

  setUp(() async {
    auth = FakeAuthRepository();
    profiles = FakeProfileRepository();
    terms = FakeTermsRepository();
    id = (await auth.login('demo@apths.test', 'password123')).dataOrNull!.accountId;
    vm = ProfileViewModel(profiles, auth, RiskAssessmentService(auth, profiles), null, terms);
    await vm.loadProfile();
    vm.updateDraft(gender: Gender.female, weightKg: 50, heightCm: 155);
  });

  test('chose 13 to 17 in the Terms: 18 is not saved until the Terms are reviewed', () async {
    accepted(TermsAgeGroup.minor);
    vm.updateDraft(age: 18);
    expect(await vm.saveProfile(), isFalse);
    expect(vm.ageReviewNeeded, isTrue);
    expect(vm.invalidFields, ['age']);
    expect((vm.saveState as UiError).message, Messages.ageAboveTermsGroup);

    vm.updateDraft(age: 16);
    expect(await vm.saveProfile(), isTrue);
    expect(vm.ageReviewNeeded, isFalse);
  });

  test('chose 18 or older: under 18 needs a parent or guardian first', () async {
    accepted(TermsAgeGroup.adult);
    vm.updateDraft(age: 15);
    expect(await vm.saveProfile(), isFalse);
    expect((vm.saveState as UiError).message, Messages.ageBelowTermsGroup);
  });

  test('reviewing the Terms for the new age: adult only, back to the profile, then it saves', () async {
    accepted(TermsAgeGroup.minor);
    vm.updateDraft(age: 18);
    expect(await vm.saveProfile(), isFalse);

    final authVm = AuthViewModel(auth, profiles, null, terms);
    authVm.startAgeReview(18);
    expect(authVm.termsReason, TermsReason.ageChanged);
    expect(await authVm.acceptTerms(language: 'en', minor: false), isTrue);
    expect(authVm.nextRoute, isNull); // the Terms screen pops back to the profile
    expect(terms.rows.last.ageGroup, TermsAgeGroup.adult);

    expect(await vm.saveProfile(), isTrue);
    expect(vm.profile!.age, 18);
  });

  test('no Terms record (offline or not created yet): the age is not held back', () async {
    vm.updateDraft(age: 30);
    expect(await vm.saveProfile(), isTrue);
  });

  test('height and weight up to the largest ever recorded', () {
    HealthProfile p(double h, double w) => HealthProfile(
      profileId: 'p',
      accountId: id,
      age: 30,
      gender: Gender.male,
      weightKg: w,
      heightCm: h,
      updatedAt: DateTime(2026, 10, 14),
    );
    expect(AppConstants.heightMax, 272);
    expect(AppConstants.weightMax, 635);
    expect(p(272, 635).validate(), isEmpty);
    expect(p(272.1, 70).validate(), isNotEmpty);
    expect(p(180, 635.1).validate(), isNotEmpty);
  });
}
