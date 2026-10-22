import 'package:flutter_test/flutter_test.dart';

import 'package:physical_treatment_and_health_support_system/model/result.dart';
import 'package:physical_treatment_and_health_support_system/viewmodel/ui_state.dart';
import 'package:physical_treatment_and_health_support_system/core/constants/app_constants.dart';
import 'package:physical_treatment_and_health_support_system/model/business_logic/risk_assessment_service/risk_assessment_service.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/enums.dart';
import 'package:physical_treatment_and_health_support_system/model/repository/auth_repository/fake_auth_repository.dart';
import 'package:physical_treatment_and_health_support_system/model/repository/profile_repository/fake_profile_repository.dart';
import 'package:physical_treatment_and_health_support_system/view/profile_view/profile_view.dart';
import 'package:physical_treatment_and_health_support_system/viewmodel/profile_view_model/profile_view_model.dart';
import 'package:physical_treatment_and_health_support_system/view/profile_view/widgets/profile_widgets.dart';

void main() {
  late FakeAuthRepository auth;
  late FakeProfileRepository profiles;
  late ProfileViewModel vm;

  setUp(() async {
    auth = FakeAuthRepository();
    profiles = FakeProfileRepository();
    await auth.login('demo@apths.test', 'password123');
    vm = ProfileViewModel(profiles, auth, RiskAssessmentService(auth, profiles));
    await vm.loadProfile();
  });

  void fillValid() => vm.updateDraft(
    age: 62,
    gender: Gender.male,
    weightKg: 71.2,
    heightCm: 168,
  );

  test('a new patient without a profile starts in edit mode', () {
    expect(vm.loadState, isA<UiSuccess<void>>());
    expect(vm.profile, isNull);
    expect(vm.isEditing, isTrue);
    expect(vm.draft, isNotNull);
    expect(vm.conditions, hasLength(17)); // 7 + 10 added on 11 Oct
    expect(vm.limitations, hasLength(5));
  });

  test(
    'an empty field is refused with the required-fields message (FR100_049)',
    () async {
      vm.updateDraft(age: 62, weightKg: 70, heightCm: 170); // no gender
      expect(await vm.saveProfile(), isFalse);
      expect((vm.saveState as UiError).message, Messages.requiredFieldsEmpty);
      expect(vm.invalidFields, contains('gender'));
    },
  );

  test('weight and height in range but not together are refused (23 Oct)', () async {
    fillValid();
    vm.updateDraft(weightKg: 20, heightCm: 200); // BMI 5: a slip or the wrong unit
    expect(await vm.saveProfile(), isFalse);
    expect((vm.saveState as UiError).message, Messages.weightHeightMismatch);
    expect(vm.invalidFields, ['weight', 'height']);
    vm.updateDraft(weightKg: 635, heightCm: 80); // BMI 992
    expect(await vm.saveProfile(), isFalse);
    vm.updateDraft(weightKg: 300, heightCm: 180); // BMI 93: rare, but real
    expect(await vm.saveProfile(), isTrue);
  });

  test('age 12 is out of range and the draft is kept (FR100_051)', () async {
    fillValid();
    vm.updateDraft(age: 12);
    expect(await vm.saveProfile(), isFalse);
    expect((vm.saveState as UiError).message, Messages.valueOutOfRange);
    expect(vm.invalidFields, ['age']);
    expect(vm.draft!.age, 12);
    expect(vm.isEditing, isTrue);
  });

  test(
    'a valid save stores version 1 and a current safety limit (FR100_053, FR100_057)',
    () async {
      fillValid();
      expect(await vm.saveProfile(), isTrue);
      expect(vm.isEditing, isFalse);
      expect(vm.profile!.version, 1);
      expect(vm.profile!.age, 62);
      expect(vm.safetyLimit, isNotNull);
      expect(vm.saveState, isA<UiSuccess<void>>());
    },
  );

  test(
    'declaring hypertension gives risk High and the strictest limits (Table 3.3)',
    () async {
      fillValid();
      vm.toggleCondition(1); // HYPERTENSION
      vm.setConditionControlled(1, true); // "Is it under control?" Yes
      expect(await vm.saveProfile(), isTrue);
      expect(vm.profile!.assignRiskLevel(), RiskLevel.high);
      expect(vm.safetyLimit!.maxExerciseIntensity, ExerciseIntensity.low);
      expect(vm.safetyLimit!.dailySodiumLimitMg, 1500);
    },
  );

  test('Cancel restores the saved values (FR100_052)', () async {
    fillValid();
    await vm.saveProfile();
    vm.startEdit();
    vm.updateDraft(weightKg: 90);
    vm.toggleLimitation(3);
    expect(vm.hasUnsavedChanges, isTrue);
    vm.cancelEdit();
    expect(vm.isEditing, isFalse);
    expect(vm.shown!.weightKg, 71.2);
    expect(vm.shown!.limitations, isEmpty);
  });

  test(
    'the None chip clears every limitation; chips do nothing outside edit mode',
    () async {
      fillValid();
      vm.toggleLimitation(1);
      vm.toggleLimitation(5);
      expect(vm.draft!.limitations, hasLength(2));
      vm.clearLimitations();
      expect(vm.draft!.limitations, isEmpty);
      await vm.saveProfile();
      vm.toggleCondition(2); // not editing any more
      expect(vm.shown!.conditions, isEmpty);
    },
  );

  test(
    'a failed save keeps the draft and shows the save-failed message',
    () async {
      fillValid();
      await vm.saveProfile();
      final failing = ProfileViewModel(_FailingSave(profiles), auth, RiskAssessmentService(auth, profiles));
      await failing.loadProfile();
      failing.startEdit();
      failing.updateDraft(weightKg: 75);
      expect(await failing.saveProfile(), isFalse);
      expect(
        (failing.saveState as UiError).message,
        Messages.profileSaveFailed,
      );
      expect(failing.draft!.weightKg, 75);
    },
  );

  test('a load failure shows the load-failed message', () async {
    profiles.failNext = true;
    await vm.loadProfile();
    expect((vm.loadState as UiError).message, Messages.profileLoadFailed);
  });

  test('logout ends the session', () async {
    expect(await vm.logout(), isTrue);
    expect((await auth.currentAccount()).dataOrNull, isNull);
  });

  test('labels, initials and BMI categories match the Figma', () {
    expect(limitationLabel(vm.limitations[2]), 'Left Leg Mobility');
    expect(conditionLabel(vm.conditions[0]), 'Hypertension');
    expect(IdentityCard.initials('Lee Jun Ting'), 'LT');
    expect(IdentityCard.initials('demo'), 'DE');
    expect(BmiRow.category(25.2), 'Overweight');
    expect(BmiRow.category(22), 'Normal');
    expect(BmiRow.category(17), 'Underweight');
    expect(BmiRow.category(31), 'Obese');
  });
}

/// Delegates to the fake but fails every save.
class _FailingSave extends FakeProfileRepository {
  final FakeProfileRepository inner;
  _FailingSave(this.inner);

  @override
  getProfile(String accountId) => inner.getProfile(accountId);

  @override
  getCurrentSafetyLimit(String profileId) =>
      inner.getCurrentSafetyLimit(profileId);

  @override
  saveProfile(p, limit) async =>
      const Failure<void>('lost connection', code: 'offline');
}
