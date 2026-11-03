// FR100_016 across app starts (bug list #12, 1 Nov): wrong codes were counted only in memory.
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:physical_treatment_and_health_support_system/core/utils/code_attempts.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('wrong codes are still counted after the app restarts', () async {
    final first = CodeAttempts();
    for (var i = 0; i < 3; i++) {
      await first.add('a@x.com');
    }
    expect(
      await CodeAttempts().count('a@x.com'),
      3,
    ); // a new instance, as after a restart
  });

  test(
    'the sign-up and reset codes are counted apart; a new code clears its count',
    () async {
      final c = CodeAttempts();
      await c.add('a@x.com');
      await c.add('reset:a@x.com');
      await c.add('reset:a@x.com');
      await c.clear('a@x.com');
      expect(await c.count('a@x.com'), 0);
      expect(await c.count('reset:a@x.com'), 2);
    },
  );
}
