import 'package:physical_treatment_and_health_support_system/core/constants/app_constants.dart';
import 'package:physical_treatment_and_health_support_system/core/utils/id_utils.dart';
import 'package:physical_treatment_and_health_support_system/core/utils/session_policy.dart';
import 'package:physical_treatment_and_health_support_system/model/result.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/account.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/enums.dart';
import 'package:physical_treatment_and_health_support_system/model/repository/auth_repository/i_auth_repository.dart';

/// In-memory auth for development and unit tests. Every verification and
/// reset code is [devCode].
class FakeAuthRepository implements IAuthRepository {
  static const devCode = '123456';

  final Map<String, Account> _accounts = {};
  final Map<String, String> _passwords = {};
  Account? _current;
  DateTime? _lastRenewed;
  final DateTime Function() _now;

  FakeAuthRepository({bool seedDemoUser = true, DateTime Function()? now})
    : _now = now ?? DateTime.now {
    if (seedDemoUser) {
      const email = 'demo@apths.test';
      _accounts[email] = Account(
        accountId: newId(),
        email: email,
        username: 'demo',
        isEmailVerified: true,
        createdAt: DateTime.now(),
      );
      _passwords[email] = 'password123';
    }
  }

  /// The same session rule as the Supabase repository (FR100_034).
  @override
  Future<Result<Account?>> currentAccount() async {
    if (_current != null && SessionPolicy.expired(_lastRenewed, _now())) {
      _current = null;
      _lastRenewed = null;
    }
    if (_current != null) _lastRenewed = _now();
    return Success(_current);
  }

  @override
  Future<Result<void>> register(
    String email,
    String password,
    String username,
  ) async {
    final e = email.trim().toLowerCase();
    final existing = _accounts[e];
    if (existing != null && existing.isActivated()) {
      return const Failure(
        'This email address is already registered.',
        code: 'email_taken',
      );
    }
    _accounts[e] = Account(
      accountId: newId(),
      email: e,
      username: username,
      createdAt: DateTime.now(),
    );
    _passwords[e] = password;
    return const Success(null);
  }

  @override
  Future<Result<Account>> verify(String email, String code) async {
    final e = email.trim().toLowerCase();
    final a = _accounts[e];
    if (a == null || code != devCode) {
      return const Failure(
        'The code is incorrect or has expired.',
        code: 'invalid_code',
      );
    }
    final verified = a.copyWith(isEmailVerified: true);
    _accounts[e] = verified;
    _current = verified;
    _lastRenewed = _now();
    return Success(verified);
  }

  @override
  Future<Result<void>> resendCode(String email) async => const Success(null);

  @override
  Future<Result<Account>> login(String email, String password) async {
    final e = email.trim().toLowerCase();
    final a = _accounts[e];
    if (a == null || _passwords[e] != password) {
      return const Failure(
        'Incorrect email address or password.',
        code: 'invalid_credentials',
      );
    }
    if (a.authProvider == AuthProvider.google) {
      return const Failure(
        'This account uses Google Sign-In.',
        code: 'use_google',
      );
    }
    if (!a.isActivated()) {
      return const Failure(
        'Please verify your email address first.',
        code: 'email_not_confirmed',
      );
    }
    _current = a;
    _lastRenewed = _now();
    return Success(a);
  }

  @override
  Future<Result<void>> signInWithGoogle() async => const Failure(
    'Google Sign-In is not available in offline demo mode.',
    code: 'unsupported',
  );

  @override
  Future<Result<void>> requestPasswordReset(String email) async =>
      const Success(null);

  @override
  Future<Result<void>> confirmPasswordReset(
    String email,
    String code,
    String newPassword,
  ) async {
    final e = email.trim().toLowerCase();
    if (code != devCode || !_accounts.containsKey(e)) {
      return const Failure(
        'The code is incorrect or has expired.',
        code: 'invalid_code',
      );
    }
    _passwords[e] = newPassword;
    _current = null; // FR100_041: every session is invalidated
    return const Success(null);
  }

  @override
  Future<Result<void>> changePassword(
    String currentPassword,
    String newPassword,
  ) async {
    final a = _current;
    if (a == null) {
      return const Failure(Messages.sessionExpired, code: 'no_session');
    }
    if (_passwords[a.email] != currentPassword) {
      return const Failure(
        Messages.currentPasswordIncorrect,
        code: 'wrong_password',
      );
    }
    _passwords[a.email] = newPassword;
    return const Success(null);
  }

  @override
  Future<Result<void>> signOut() async {
    _current = null;
    return const Success(null);
  }
}
