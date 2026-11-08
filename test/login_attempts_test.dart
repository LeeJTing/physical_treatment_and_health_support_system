// FR100_031 across app starts (audit, 23 Oct): the failed log-ins were held only in memory, so
// closing and opening the app reset the count. LoginAttempts keeps them in the app's preferences.
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:physical_treatment_and_health_support_system/core/constants/app_constants.dart';
import 'package:physical_treatment_and_health_support_system/core/utils/login_attempts.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
    'five wrong passwords lock the email, also after the app restarts',
    () async {
      var now = DateTime(2026, 10, 23, 9);
      final first = LoginAttempts(now: () => now);
      for (var i = 1; i < AppConstants.maxLoginFailures; i++) {
        expect(await first.recordFailure('a@x.com'), isFalse, reason: 'try $i');
      }
      expect(await first.recordFailure('a@x.com'), isTrue);
      // A new LoginAttempts, as after closing and opening the app.
      final restarted = LoginAttempts(now: () => now);
      expect(await restarted.locked('a@x.com'), isTrue);
      expect(
        await restarted.locked('b@x.com'),
        isFalse,
      ); // other emails are not locked
      now = now.add(AppConstants.loginLockout + const Duration(seconds: 1));
      expect(await restarted.locked('a@x.com'), isFalse); // 15 minutes later
    },
  );

  test('a successful log-in clears the count', () async {
    final a = LoginAttempts(now: () => DateTime(2026, 10, 23, 9));
    for (var i = 0; i < AppConstants.maxLoginFailures - 1; i++) {
      await a.recordFailure('a@x.com');
    }
    await a.clear('a@x.com');
    expect(await a.recordFailure('a@x.com'), isFalse); // counting starts again
  });

  test(
    'the lock lasts 15 minutes from the fifth failure, however spread out (bug list #1)',
    () async {
      var now = DateTime(2026, 11, 1, 9);
      final a = LoginAttempts(now: () => now);
      for (var i = 0; i < AppConstants.maxLoginFailures; i++) {
        if (i > 0) now = now.add(const Duration(minutes: 3));
        await a.recordFailure('a@x.com');
      }
      final lockedAt = now; // 9:12
      now = lockedAt.add(const Duration(minutes: 14, seconds: 59));
      expect(await a.locked('a@x.com'), isTrue); // was unlocked at 9:15 before
      expect(await LoginAttempts(now: () => now).locked('a@x.com'), isTrue);
      now = lockedAt.add(AppConstants.loginLockout);
      expect(await a.locked('a@x.com'), isFalse);
      // After the lock, one more wrong password does not lock again at once.
      expect(await a.recordFailure('a@x.com'), isFalse);
    },
  );
}
