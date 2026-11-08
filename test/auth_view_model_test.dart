import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:physical_treatment_and_health_support_system/model/result.dart';
import 'package:physical_treatment_and_health_support_system/viewmodel/ui_state.dart';
import 'package:physical_treatment_and_health_support_system/core/constants/app_constants.dart';
import 'package:physical_treatment_and_health_support_system/core/routes/routes.dart';
import 'package:physical_treatment_and_health_support_system/core/utils/id_utils.dart';
import 'package:physical_treatment_and_health_support_system/core/utils/session_policy.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/enums.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/health_profile.dart';
import 'package:physical_treatment_and_health_support_system/model/repository/auth_repository/fake_auth_repository.dart';
import 'package:physical_treatment_and_health_support_system/model/repository/profile_repository/fake_profile_repository.dart';
import 'package:physical_treatment_and_health_support_system/viewmodel/auth_view_model/auth_view_model.dart';
import 'package:physical_treatment_and_health_support_system/device_platform/notification_scheduler/notification_scheduler.dart';
import 'package:physical_treatment_and_health_support_system/model/business_logic/local_notification_service/local_notification_service.dart';
import 'package:physical_treatment_and_health_support_system/model/repository/notification_repository/fake_notification_repository.dart';
import 'package:physical_treatment_and_health_support_system/model/repository/treatment_repository/fake_treatment_repository.dart';

/// Only the parts of the phone's scheduler that tapping a reminder uses.
class _TapScheduler implements NotificationScheduler {
  final tapController = StreamController<String>.broadcast();
  String? launch;
  @override
  Future<void> init() async {}
  @override
  Future<bool> requestPermission() async => true;
  @override
  Future<bool> isPermitted() async => true;
  @override
  Future<bool> openSettings() async => true;
  @override
  Future<void> scheduleOnce(
    int id,
    String title,
    String body,
    DateTime at, {
    String? payload,
  }) async {}
  @override
  Future<void> cancel(int id) async {}
  @override
  Future<void> cancelAll() async {}
  @override
  Stream<String> get taps => tapController.stream;
  @override
  Future<String?> launchPayload() async => launch;
  @override
  Future<bool> canRingOnTime() async => true;
  @override
  Future<void> openExactAlarmSettings() async {}
}

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

  test(
    'bad input is refused before the server is asked (audit, 23 Oct)',
    () async {
      expect(await vm.register('Ali', 'ali@test.com', 'short'), isFalse);
      expect((vm.registerState as UiError).message, Messages.passwordInvalid);
      expect(await vm.register('!!!', 'ali@test.com', 'abc12345'), isFalse);
      expect(
        (vm.registerState as UiError).message,
        Messages.usernameNeedsLetter,
      );
      // Nothing was created: the address is still free.
      expect(await vm.register('Ali', 'ali@test.com', 'abc12345'), isTrue);

      expect(await vm.login('not-an-email', 'password123'), isFalse);
      expect((vm.loginState as UiError).message, Messages.emailInvalid);
      expect(await vm.login('demo@apths.test', ''), isFalse);
      expect((vm.loginState as UiError).message, Messages.passwordEmpty);

      expect(await vm.verify('ali@test.com', '12ab'), isFalse);
      expect(vm.verifyState, isA<UiError<void>>());
      // A malformed code is not one of the five wrong tries (FR100_016).
      for (var i = 0; i < AppConstants.maxCodeAttempts - 1; i++) {
        await vm.verify('ali@test.com', '000000');
      }
      expect(
        await vm.verify('ali@test.com', FakeAuthRepository.devCode),
        isTrue,
      );
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

  test(
    'reset: a weak new password is refused before the server (23 Oct)',
    () async {
      expect(
        await vm.confirmReset(
          'demo@apths.test',
          FakeAuthRepository.devCode,
          'short1',
        ),
        isFalse,
      );
      expect(
        (vm.resetConfirmState as UiError).message,
        Messages.passwordInvalid,
      );
      expect(
        await vm.confirmReset('demo@apths.test', '12a456', 'newpass99'),
        isFalse,
      );
      expect(
        await vm.login('demo@apths.test', 'password123'),
        isTrue,
      ); // unchanged
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

  test(
    'Google sign-in explains itself while it is not set up (no broken browser page)',
    () async {
      final off = AuthViewModel(
        FakeAuthRepository(googleEmail: null),
        profiles,
      );
      await off.signInWithGoogle();
      expect((off.googleState as UiError).message, Messages.googleNotAvailable);
      off.dispose();
    },
  );

  test(
    'coming back to the app with a session already present continues sign-in',
    () async {
      await auth.login(
        'demo@apths.test',
        'password123',
      ); // stands in for the Google redirect
      expect(await vm.completeGoogleSignIn(), isTrue);
      expect(vm.nextRoute, Routes.healthProfile);
      expect(vm.googleState, isA<UiSuccess<void>>());
    },
  );

  test(
    'coming back without a session (not waiting for Google) stays on login quietly',
    () async {
      expect(await vm.completeGoogleSignIn(), isFalse);
      expect(vm.googleState, isA<Idle<void>>());
    },
  );

  group('Change password from Profile (FR100_061)', () {
    setUp(() async => auth.login('demo@apths.test', 'password123'));

    test('the current password must be right', () async {
      expect(
        await vm.changePassword('wrong-one1', 'newPass123', 'newPass123'),
        isFalse,
      );
      expect(
        vm.changePasswordState,
        isA<UiError<void>>().having(
          (e) => e.message,
          'message',
          Messages.currentPasswordIncorrect,
        ),
      );
    });

    test(
      'the new password follows the registration rule and must match',
      () async {
        expect(
          await vm.changePassword('password123', 'short', 'short'),
          isFalse,
        );
        expect(
          (vm.changePasswordState as UiError<void>).message,
          Messages.passwordInvalid,
        );
        expect(
          await vm.changePassword('password123', 'newPass123', 'newPass124'),
          isFalse,
        );
        expect(
          await vm.changePassword('password123', 'password123', 'password123'),
          isFalse,
        );
        expect(
          (vm.changePasswordState as UiError<void>).message,
          Messages.passwordSameAsCurrent,
        );
      },
    );

    test('a valid change replaces the password', () async {
      expect(
        await vm.changePassword('password123', 'newPass123', 'newPass123'),
        isTrue,
      );
      expect(vm.changePasswordState, isA<UiSuccess<void>>());
      await auth.signOut();
      expect(
        await auth.login('demo@apths.test', 'password123'),
        isA<Failure<Object?>>(),
      );
      expect(
        await auth.login('demo@apths.test', 'newPass123'),
        isA<Success<Object?>>(),
      );
    });
  });

  group('A session ends after 3 days without use (FR100_034)', () {
    test('the rule', () {
      final t = DateTime(2026, 10, 9, 9);
      expect(SessionPolicy.expired(null, t), isFalse);
      expect(
        SessionPolicy.expired(
          t.subtract(const Duration(days: 2, hours: 23)),
          t,
        ),
        isFalse,
      );
      expect(
        SessionPolicy.expired(
          t.subtract(const Duration(days: 3, minutes: 1)),
          t,
        ),
        isTrue,
      );
    });

    test(
      'using the app keeps the session; four idle days lead to login',
      () async {
        var clock = DateTime(2026, 10, 9, 9);
        final a = FakeAuthRepository(now: () => clock);
        final model = AuthViewModel(a, profiles);
        await a.login('demo@apths.test', 'password123');
        clock = clock.add(const Duration(days: 2));
        expect((await a.currentAccount()).dataOrNull, isNotNull); // renewed
        clock = clock.add(const Duration(days: 2));
        expect(
          (await a.currentAccount()).dataOrNull,
          isNotNull,
        ); // 2 days since
        clock = clock.add(const Duration(days: 4));
        expect(await model.decideStartRoute(), Routes.loginScreen);
        model.dispose();
      },
    );
  });

  group('Google account setup (FR100_019 to FR100_023)', () {
    test('a new Google address goes to Complete Account Setup', () async {
      await vm.signInWithGoogle();
      expect(vm.googleState, isA<UiSuccess<void>>());
      expect(vm.nextRoute, Routes.accountSetup);
      final a = (await auth.currentAccount()).dataOrNull!;
      expect(a.isEmailVerified, isTrue); // FR100_019
      expect(a.authProvider, AuthProvider.google); // FR100_020
      // Closing the app half-way: setup comes first next time.
      expect(await vm.decideStartRoute(), Routes.accountSetup);
    });

    test(
      'setup uses the registration rules, then the patient can log in by email',
      () async {
        await vm.signInWithGoogle();
        expect(
          await vm.completeAccountSetup('  ', 'newPass123', 'newPass123'),
          isFalse,
        );
        expect((vm.setupState as UiError).message, Messages.usernameBlank);
        expect(await vm.completeAccountSetup('Ali', 'short', 'short'), isFalse);
        expect((vm.setupState as UiError).message, Messages.passwordInvalid);
        expect(
          await vm.completeAccountSetup('Ali', 'newPass123', 'newPass124'),
          isFalse,
        );
        expect((vm.setupState as UiError).message, Messages.passwordMismatch);

        expect(
          await vm.completeAccountSetup(' Ali ', 'newPass123', 'newPass123'),
          isTrue,
        );
        expect(vm.setupState, isA<UiSuccess<void>>());
        expect(vm.nextRoute, Routes.healthProfile); // no health profile yet
        expect((await auth.currentAccount()).dataOrNull!.username, 'Ali');
        expect((await auth.needsAccountSetup()).dataOrNull, isFalse);

        await auth.signOut();
        expect(
          await auth.login(FakeAuthRepository.defaultGoogleEmail, 'newPass123'),
          isA<Success<Object?>>(),
        );
      },
    );

    test(
      'cancelling removes the unfinished account and returns to login',
      () async {
        await vm.signInWithGoogle();
        await vm.cancelAccountSetup();
        expect(vm.nextRoute, Routes.loginScreen);
        expect((await auth.currentAccount()).dataOrNull, isNull);
        // Removed: the same Google address is a new account again.
        await vm.signInWithGoogle();
        expect(vm.nextRoute, Routes.accountSetup);
      },
    );

    test(
      'an address that already has an account is linked, with M12',
      () async {
        final a = FakeAuthRepository(googleEmail: 'demo@apths.test');
        final m = AuthViewModel(a, profiles);
        await m.signInWithGoogle();
        expect(
          m.nextRoute,
          Routes.healthProfile,
        ); // no setup: username and password exist
        expect(m.notice, Messages.googleLinked);
        expect(
          (await a.currentAccount()).dataOrNull!.authProvider,
          AuthProvider.both,
        );
        expect((await a.googleJustLinked()).dataOrNull, isFalse); // told once
        m.dispose();
      },
    );
  });

  group('Verification attempt limit (FR100_016)', () {
    test('five wrong codes end the code; a new code works', () async {
      expect(await vm.register('Mei', 'mei@apths.test', 'goodPass1'), isTrue);
      for (var i = 0; i < AppConstants.maxCodeAttempts; i++) {
        expect(await vm.verify('mei@apths.test', '000000'), isFalse);
        expect((vm.verifyState as UiError).message, Messages.codeIncorrect);
      }
      expect(
        await vm.verify('mei@apths.test', FakeAuthRepository.devCode),
        isFalse,
      );
      expect((vm.verifyState as UiError).message, Messages.codeExpired);

      await auth.resendCode('mei@apths.test');
      expect(
        await vm.verify('mei@apths.test', FakeAuthRepository.devCode),
        isTrue,
      );
    });

    test('a new code clears the old "expired" message', () async {
      // Emulator test, 9 Oct: after Resend the screen showed "expired" and
      // "A new code has been sent" together.
      expect(await vm.register('Mei', 'mei@apths.test', 'goodPass1'), isTrue);
      // A second model past the register cooldown, on the same accounts.
      final later = AuthViewModel(auth, profiles);
      addTearDown(later.dispose);
      for (var i = 0; i <= AppConstants.maxCodeAttempts; i++) {
        await later.verify('mei@apths.test', '000000');
      }
      expect(later.verifyState, isA<UiError>());
      await later.resendCode('mei@apths.test');
      expect(later.resendState, isA<UiSuccess<void>>());
      expect(later.verifyState, isA<Idle<void>>());
    });
  });

  group('Tapping a reminder opens its plan (6.1)', () {
    late _TapScheduler device;
    late AuthViewModel m;

    setUp(() {
      device = _TapScheduler();
      final notes = LocalNotificationService(
        FakeNotificationRepository(),
        FakeTreatmentRepository(const []),
        scheduler: device,
      );
      m = AuthViewModel(auth, profiles, notes);
    });
    tearDown(() => m.dispose());

    test('while the app runs', () async {
      await auth.login('demo@apths.test', 'password123');
      device.tapController.add('EXERCISE|pp9');
      await pumpEventQueue();
      final open = m.takeReminderOpen();
      expect(open?.route, Routes.physicalTreatment);
      expect(open?.argument, 'pp9');
      expect(m.takeReminderOpen(), isNull); // once

      device.tapController.add('HEALTH_LOG|');
      await pumpEventQueue();
      // A health-logging reminder opens the Tracking screen (M600, FR600_002).
      expect(m.takeReminderOpen()?.route, Routes.monitoring);

      await auth.signOut();
      device.tapController.add('EXERCISE|pp9');
      await pumpEventQueue();
      expect(m.takeReminderOpen(), isNull); // signed out: login first
    });

    test('when the tap started the app', () async {
      await giveDemoACompleteProfile();
      await auth.login('demo@apths.test', 'password123');
      device.launch = 'EXERCISE|pp7';
      expect(await m.decideStartRoute(), Routes.home);
      expect(m.takeReminderOpen()?.argument, 'pp7');
    });
  });
}
