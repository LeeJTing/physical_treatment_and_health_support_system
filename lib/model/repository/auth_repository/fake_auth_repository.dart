import 'package:physical_treatment_and_health_support_system/core/constants/app_constants.dart';
import 'package:physical_treatment_and_health_support_system/core/utils/id_utils.dart';
import 'package:physical_treatment_and_health_support_system/core/utils/session_policy.dart';
import 'package:physical_treatment_and_health_support_system/model/result.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/account.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/enums.dart';
import 'package:physical_treatment_and_health_support_system/model/repository/auth_repository/i_auth_repository.dart';

/// In-memory auth for development and unit tests. Every verification and
/// reset code is [devCode]. "Continue with Google" signs in as [googleEmail] at once
/// (no browser): a new address needs account setup, an existing one is linked.
class FakeAuthRepository implements IAuthRepository {
  static const devCode = '123456';
  static const defaultGoogleEmail = 'google.user@apths.test';

  final Map<String, Account> _accounts = {};
  final Map<String, String> _passwords = {};
  Account? _current;
  DateTime? _lastRenewed;
  final DateTime Function() _now;

  /// The address the simulated Google sign-in returns; null = Google not available.
  final String? googleEmail;
  final Set<String> _setupPending = {};
  bool _justLinked = false;
  final Map<String, int> _codeRejections = {};

  FakeAuthRepository({
    bool seedDemoUser = true,
    DateTime Function()? now,
    this.googleEmail = defaultGoogleEmail,
  }) : _now = now ?? DateTime.now {
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
    _codeRejections.remove(e);
    return const Success(null);
  }

  @override
  Future<Result<Account>> verify(String email, String code) async {
    final e = email.trim().toLowerCase();
    final a = _accounts[e];
    // FR100_016: after five wrong codes this code no longer works; a new one must be sent.
    if ((_codeRejections[e] ?? 0) >= AppConstants.maxCodeAttempts) {
      return const Failure(Messages.codeExpired, code: 'code_attempts');
    }
    if (a == null || code != devCode) {
      _codeRejections[e] = (_codeRejections[e] ?? 0) + 1;
      return const Failure(
        'The code is incorrect or has expired.',
        code: 'invalid_code',
      );
    }
    _codeRejections.remove(e);
    final verified = a.copyWith(isEmailVerified: true);
    _accounts[e] = verified;
    _current = verified;
    _lastRenewed = _now();
    return Success(verified);
  }

  @override
  Future<Result<void>> resendCode(String email) async {
    _codeRejections.remove(email.trim().toLowerCase());
    return const Success(null);
  }

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
  Future<Result<void>> signInWithGoogle() async {
    final e = googleEmail;
    if (e == null) {
      return const Failure(Messages.googleNotAvailable, code: 'unsupported');
    }
    final existing = _accounts[e];
    final Account a;
    if (existing == null) {
      // FR100_019, FR100_020: a new, verified account; username from the address for now.
      a = Account(
        accountId: newId(),
        email: e,
        username: e.split('@').first.padRight(3, '_'),
        authProvider: AuthProvider.google,
        isEmailVerified: true,
        createdAt: _now(),
      );
      _setupPending.add(e);
    } else if (existing.authProvider == AuthProvider.email) {
      a = existing.copyWith(
        authProvider: AuthProvider.both,
        isEmailVerified: true,
      ); // FR100_021
      _justLinked = true;
    } else {
      a = existing;
    }
    _accounts[e] = a;
    _current = a;
    _lastRenewed = _now();
    return const Success(null);
  }

  @override
  Future<Result<bool>> needsAccountSetup() async =>
      Success(_current != null && _setupPending.contains(_current!.email));

  @override
  Future<Result<Account>> completeAccountSetup(
    String username,
    String password,
  ) async {
    final a = _current;
    if (a == null) {
      return const Failure(Messages.sessionExpired, code: 'no_session');
    }
    // With a password of its own the account can also log in by email.
    final done = a.copyWith(
      username: username.trim(),
      authProvider: AuthProvider.both,
    );
    _accounts[a.email] = done;
    _passwords[a.email] = password;
    _setupPending.remove(a.email);
    _current = done;
    return Success(done);
  }

  @override
  Future<Result<void>> discardIncompleteAccount() async {
    final a = _current;
    if (a != null && _setupPending.remove(a.email)) {
      _accounts.remove(a.email);
      _passwords.remove(a.email);
    }
    _current = null;
    _lastRenewed = null;
    return const Success(null);
  }

  @override
  Future<Result<bool>> googleJustLinked() async {
    final linked = _justLinked;
    _justLinked = false;
    return Success(linked);
  }

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
