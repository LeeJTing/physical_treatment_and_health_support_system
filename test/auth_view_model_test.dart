import 'package:flutter_test/flutter_test.dart';

import 'package:physical_treatment_and_health_support_system/core/base/result.dart';
import 'package:physical_treatment_and_health_support_system/core/base/ui_state.dart';
import 'package:physical_treatment_and_health_support_system/core/constants/app_constants.dart';
import 'package:physical_treatment_and_health_support_system/core/routes/routes.dart';
import 'package:physical_treatment_and_health_support_system/core/utils/id_utils.dart';
import 'package:physical_treatment_and_health_support_system/data/models/enums.dart';
import 'package:physical_treatment_and_health_support_system/data/models/health_profile.dart';
import 'package:physical_treatment_and_health_support_system/data/repository/fake/fake_auth_repository.dart';
import 'package:physical_treatment_and_health_support_system/data/repository/fake/fake_profile_repository.dart';
import 'package:physical_treatment_and_health_support_system/features/auth/viewmodel/auth_view_model.dart';

void main() {
  late FakeAuthRepository auth;
  late FakeProfileRepository profiles;
  late AuthViewModel vm;

  setUp(() {
    auth = FakeAuthRepository();
    profiles = FakeProfileRepository();
    vm = AuthViewModel(auth, profiles);
  });

  tearDown(() => vm.dispose());

  Future<void> giveDemoACompleteProfile() async {
    final a = (await auth.login('demo@apths.test', 'password123')).dataOrNull!;
    final p = HealthProfile(
      profileId: newId(),
      accountId: a.accountId,
      age: 60,
      gender: Gender.female,
      weightKg: 60,
      heightCm: 160,
      updatedAt: DateTime.now(),
    );
    await profiles.saveProfile(p, p.generateSafetyLimit());
    await auth.signOut();
  }

  test('a wrong password shows the report message (UC200 A2)', () async {
    expect(await vm.login('demo@apths.test', 'wrong-pass1'), isFalse);
    expect((vm.loginState as UiError).message, Messages.incorrectCredentials);
    expect(vm.lastErrorCode, 'invalid_credentials');
  });

  test(
    'login with a complete profile goes home, without one to the profile (FR100_035)',
    () async {
      expect(await vm.login('demo@apths.test', 'password123'), isTrue);
      expect(vm.nextRoute, Routes.healthProfile);
      await auth.signOut();

      await giveDemoACompleteProfile();
      expect(await vm.login('demo@apths.test', 'password123'), isTrue);
      expect(vm.nextRoute, Routes.home);
      expect(vm.loginState, isA<UiSuccess<void>>());
    },
  );

  test(
    'register then verify with the right code leads to the profile screen',
    () async {
      expect(await vm.register('Ali Tan', 'ali@test.com', 'abc12345'), isTrue);
      expect(
        vm.secondsUntilResend,
        AuthViewModel.resendCooldownSeconds,
      ); // the first code was sent
      expect(await vm.verify('ali@test.com', '000000'), isFalse);
      expect((vm.verifyState as UiError).message, Messages.codeIncorrect);
      expect(
        await vm.verify('ali@test.com', FakeAuthRepository.devCode),
        isTrue,
      );
      expect(vm.nextRoute, Routes.healthProfile); // no profile yet
    },
  );

  test(
    'logging in before verifying asks for verification and offers a new code',
    () async {
      await vm.register('Ali Tan', 'ali@test.com', 'abc12345');
      expect(await vm.login('ali@test.com', 'abc12345'), isFalse);
      expect((vm.loginState as UiError).message, Messages.emailNotVerified);
      expect(vm.lastErrorCode, 'email_not_confirmed');
    },
  );

  test('an email that already has an account is refused (UC100 A3)', () async {
    expect(await vm.register('Demo', 'demo@apths.test', 'abc12345'), isFalse);
    expect((vm.registerState as UiError).message, Messages.emailExists);
  });

  test('resending a code starts a 60-second cooldown (FR100_015)', () async {
    expect(vm.canResend, isTrue);
    await vm.resendCode('demo@apths.test');
    expect(vm.secondsUntilResend, 60);
    expect(vm.canResend, isFalse);
    await vm.resendCode('demo@apths.test'); // ignored during the cooldown
    expect(vm.secondsUntilResend, 60);
  });

  test(
    'password reset: neutral reply, wrong code refused, right code works (FR100_038 to 042)',
    () async {
      expect(
        await vm.requestReset('nobody@test.com'),
        isTrue,
      ); // same reply for unknown addresses
      expect(
        await vm.confirmReset('demo@apths.test', '111111', 'newpass99'),
        isFalse,
      );
      expect((vm.resetConfirmState as UiError).message, Messages.codeIncorrect);
      expect(
        await vm.confirmReset(
          'demo@apths.test',
          FakeAuthRepository.devCode,
          'newpass99',
        ),
        isTrue,
      );
      expect(await vm.login('demo@apths.test', 'newpass99'), isTrue);
    },
  );

  test('failure codes map to the report messages', () {
    expect(
      AuthViewModel.messageFor(const Failure<void>('x', code: 'locked')),
      Messages.accountLocked,
    );
    expect(
      AuthViewModel.messageFor(const Failure<void>('x', code: 'offline')),
      Messages.loginUnavailable,
    );
    expect(
      AuthViewModel.messageFor(
        const Failure<void>('x', code: 'timeout'),
        registering: true,
      ),
      Messages.registrationUnavailable,
    );
    expect(
      AuthViewModel.messageFor(const Failure<void>('x', code: 'use_google')),
      Messages.useGoogle,
    );
    expect(
      AuthViewModel.messageFor(
        const Failure<void>('Something else', code: 'weird'),
      ),
      'Something else',
    );
  });

  test('clearErrors resets the error states', () async {
    await vm.login('demo@apths.test', 'wrong-pass1');
    vm.clearErrors();
    expect(vm.loginState, isA<Idle<void>>());
    expect(vm.lastErrorCode, isNull);
  });
}
