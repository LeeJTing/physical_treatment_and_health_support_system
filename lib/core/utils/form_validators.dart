import 'package:physical_treatment_and_health_support_system/core/constants/app_constants.dart';

/// Client-side validation rules from Table 3.3 (NFR_05). Each returns null
/// when the value is valid, or the message to show under the field.
class FormValidators {
  FormValidators._();

  // local@domain.tld: exactly one @, >=1 char before it, >=2 chars after the last dot.
  static final RegExp _email = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s.]{2,}$');

  static String? username(String? v) {
    final s = (v ?? '').trim();
    if (s.isEmpty) return Messages.usernameBlank;
    if (s.length < AppConstants.usernameMin || s.length > AppConstants.usernameMax) {
      return 'Username must be 3 to 30 characters.';
    }
    return null;
  }

  static String? email(String? v) {
    final s = (v ?? '').trim();
    if (s.isEmpty) return Messages.emailEmpty;
    if (!_email.hasMatch(s)) return Messages.emailInvalid;
    return null;
  }

  static String? password(String? v) {
    final s = v ?? '';
    if (s.isEmpty) return Messages.passwordEmpty;
    // Table 3.3 password rule, as worded in UC100 M4: 8+ characters with a letter and a number.
    if (s.length < AppConstants.passwordMin || !s.contains(RegExp(r'[A-Za-z]')) || !s.contains(RegExp(r'\d'))) {
      return Messages.passwordInvalid;
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

  static String? doubleInRange(String? v, double min, double max, String label) {
    final n = double.tryParse((v ?? '').trim());
    if (n == null) return '$label is required.';
    if (n < min || n > max) return Messages.valueOutOfRange;
    return null;
  }
}
