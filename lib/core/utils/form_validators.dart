import 'dart:convert';

import 'package:physical_treatment_and_health_support_system/core/constants/app_constants.dart';

/// Client-side validation rules from Table 3.3 (NFR_05). Each returns null
/// when the value is valid, or the message to show under the field.
class FormValidators {
  FormValidators._();

  // local@domain.tld (23 Oct, tightened): the local part is dot-separated words with no dot at
  // either end or two in a row; each domain label is letters, digits and inner hyphens; the
  // ending is 2+ letters. a..b@x.com, .a@x.com, a@-x.com and a@x.c0m were accepted before.
  static final RegExp _email = RegExp(
    r"^[A-Za-z0-9!#$%&'*+/=?^_`{|}~-]+(\.[A-Za-z0-9!#$%&'*+/=?^_`{|}~-]+)*"
    r'@([A-Za-z0-9]([A-Za-z0-9-]*[A-Za-z0-9])?\.)+[A-Za-z]{2,}$',
  );

  static final RegExp _letter = RegExp(r'\p{L}', unicode: true);

  static String? username(String? v) {
    final s = (v ?? '').trim();
    if (s.isEmpty) return Messages.usernameBlank;
    if (s.length < AppConstants.usernameMin ||
        s.length > AppConstants.usernameMax) {
      return 'Username must be 3 to 30 characters.';
    }
    // Elwin, 23 Oct: at least one letter, in any language ("!!!" or "..." was accepted).
    if (!_letter.hasMatch(s)) return Messages.usernameNeedsLetter;
    return null;
  }

  static String? email(String? v) {
    final s = (v ?? '').trim();
    if (s.isEmpty) return Messages.emailEmpty;
    // RFC 5321: at most 64 characters before the @ and 254 in all.
    if (s.length > 254 || s.indexOf('@') > 64 || !_email.hasMatch(s)) {
      return Messages.emailInvalid;
    }
    return null;
  }

  static String? password(String? v) {
    final s = v ?? '';
    if (s.isEmpty) return Messages.passwordEmpty;
    // Table 3.3 password rule, as worded in UC100 M4: 8+ characters with a letter and a number.
    if (s.length < AppConstants.passwordMin ||
        !s.contains(RegExp(r'[A-Za-z]')) ||
        !s.contains(RegExp(r'\d'))) {
      return Messages.passwordInvalid;
    }
    // Supabase refuses a password over 72 bytes (bcrypt), after the form had accepted it.
    if (utf8.encode(s).length > AppConstants.passwordMax) {
      return Messages.passwordTooLong;
    }
    return null;
  }

  static String? confirmPassword(String? pw, String? confirm) {
    if ((confirm ?? '').isEmpty) return 'Please confirm your password.';
    if (pw != confirm) return Messages.passwordMismatch;
    return null;
  }

  static String? otp(String? v) {
    final s = (v ?? '').trim();
    if (!RegExp(r'^\d{6}$').hasMatch(s)) return 'Enter the 6-digit code.';
    return null;
  }

  static String? intInRange(String? v, int min, int max, String label) {
    final n = int.tryParse((v ?? '').trim());
    if (n == null) return '$label is required.';
    if (n < min || n > max) return Messages.valueOutOfRange;
    return null;
  }

  static String? doubleInRange(
    String? v,
    double min,
    double max,
    String label,
  ) {
    final n = double.tryParse((v ?? '').trim());
    if (n == null) return '$label is required.';
    if (n < min || n > max) return Messages.valueOutOfRange;
    return null;
  }
}
