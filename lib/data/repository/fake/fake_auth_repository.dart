import 'package:physical_treatment_and_health_support_system/core/utils/id_utils.dart';
import 'package:physical_treatment_and_health_support_system/core/base/result.dart';
import 'package:physical_treatment_and_health_support_system/data/models/account.dart';
import 'package:physical_treatment_and_health_support_system/data/models/enums.dart';
import 'package:physical_treatment_and_health_support_system/data/repository/interfaces/i_auth_repository.dart';

/// In-memory auth for development and unit tests. Every verification and
/// reset code is [devCode].
class FakeAuthRepository implements IAuthRepository {
  static const devCode = '123456';

  final Map<String, Account> _accounts = {};
  final Map<String, String> _passwords = {};
  Account? _current;

  FakeAuthRepository({bool seedDemoUser = true}) {
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

  @override
  Future<Result<Account?>> currentAccount() async => Success(_current);

  @override
  Future<Result<void>> register(String email, String password, String username) async {
    final e = email.trim().toLowerCase();
    final existing = _accounts[e];
    if (existing != null && existing.isActivated()) {
      return const Failure('This email address is already registered.', code: 'email_taken');
    }
    _accounts[e] = Account(accountId: newId(), email: e, username: username, createdAt: DateTime.now());
    _passwords[e] = password;
    return const Success(null);
  }

  @override
  Future<Result<Account>> verify(String email, String code) async {
    final e = email.trim().toLowerCase();
    final a = _accounts[e];
    if (a == null || code != devCode) {
      return const Failure('The code is incorrect or has expired.', code: 'invalid_code');
    }
    final verified = a.copyWith(isEmailVerified: true);
    _accounts[e] = verified;
    _current = verified;
    return Success(verified);
  }

  @override
  Future<Result<void>> resendCode(String email) async => const Success(null);

  @override
  Future<Result<Account>> login(String email, String password) async {
    final e = email.trim().toLowerCase();
    final a = _accounts[e];
    if (a == null || _passwords[e] != password) {
      return const Failure('Incorrect email address or password.', code: 'invalid_credentials');
    }
    if (a.authProvider == AuthProvider.google) {
      return const Failure('This account uses Google Sign-In.', code: 'use_google');
    }
    if (!a.isActivated()) {
      return const Failure('Please verify your email address first.', code: 'email_not_confirmed');
    }
    _current = a;
    return Success(a);
  }

  @override
  Future<Result<void>> signInWithGoogle() async =>
      const Failure('Google Sign-In is not available in offline demo mode.', code: 'unsupported');

  @override
  Future<Result<void>> requestPasswordReset(String email) async => const Success(null);

  @override
  Future<Result<void>> confirmPasswordReset(String email, String code, String newPassword) async {
    final e = email.trim().toLowerCase();
    if (code != devCode || !_accounts.containsKey(e)) {
      return const Failure('The code is incorrect or has expired.', code: 'invalid_code');
    }
    _passwords[e] = newPassword;
    _current = null; // FR100_041: every session is invalidated
    return const Success(null);
  }

  @override
  Future<Result<void>> signOut() async {
    _current = null;
    return const Success(null);
  }
}
