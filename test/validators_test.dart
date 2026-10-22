import 'package:physical_treatment_and_health_support_system/core/utils/form_validators.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:physical_treatment_and_health_support_system/core/constants/app_constants.dart';

void main() {
  test('username 3-30 chars (FR100_002)', () {
    expect(FormValidators.username('ab'), isNotNull);
    expect(FormValidators.username('abc'), isNull);
    expect(FormValidators.username('a' * 31), isNotNull);
  });
  test('email format local@domain.tld (FR100_003)', () {
    expect(FormValidators.email('a@b.co'), isNull);
    expect(FormValidators.email('a@b.c'), isNotNull);
    expect(FormValidators.email('a@@b.com'), isNotNull);
    expect(FormValidators.email('@b.com'), isNotNull);
  });
  test(
    'password: 8+ characters with a letter and a number (FR100_004, UC100 M4)',
    () {
      expect(FormValidators.password('abc1234'), isNotNull);
      expect(FormValidators.password('12345678'), isNotNull);
      expect(FormValidators.password('abcdefgh'), isNotNull);
      expect(FormValidators.password('abcd1234'), isNull);
    },
  );
  test('confirm must match (FR100_005)', () {
    expect(FormValidators.confirmPassword('abcdefgh', 'abcdefgx'), isNotNull);
    expect(FormValidators.confirmPassword('abcdefgh', 'abcdefgh'), isNull);
  });
  test('otp is 6 digits', () {
    expect(FormValidators.otp('12345'), isNotNull);
    expect(FormValidators.otp('123456'), isNull);
  });
  test(
    'email: no stray dots or hyphens, a real ending, RFC lengths (23 Oct)',
    () {
      for (final ok in [
        'a@b.co',
        'first.last@example.com',
        'ksy+fyp@gmail.com',
        'a_b-c@sub.domain.edu.my',
      ]) {
        expect(FormValidators.email(ok), isNull, reason: ok);
      }
      for (final bad in [
        'a..b@x.com',
        '.a@x.com',
        'a.@x.com',
        'a@-x.com',
        'a@x-.com',
        'a@x..com',
        'a@.com',
        'a@x.c0m',
        'a b@x.com',
        '${'a' * 65}@x.com',
        'a@${'b' * 250}.com',
      ]) {
        expect(FormValidators.email(bad), isNotNull, reason: bad);
      }
    },
  );
  test('password: at most 72 bytes, as Supabase accepts (23 Oct)', () {
    expect(FormValidators.password('a1${'x' * 70}'), isNull); // 72
    expect(
      FormValidators.password('a1${'x' * 71}'),
      Messages.passwordTooLong,
    ); // 73
    // Counted in bytes: 'a1' and 23 three-byte characters are 71 bytes; 24 make 74.
    expect(FormValidators.password('a1${'中' * 23}'), isNull);
    expect(FormValidators.password('a1${'中' * 24}'), isNotNull);
  });
}
