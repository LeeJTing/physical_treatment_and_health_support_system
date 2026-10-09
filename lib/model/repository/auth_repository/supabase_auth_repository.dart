import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:physical_treatment_and_health_support_system/model/result.dart';
import 'package:physical_treatment_and_health_support_system/core/constants/app_constants.dart';
import 'package:physical_treatment_and_health_support_system/core/utils/session_policy.dart';
import 'package:physical_treatment_and_health_support_system/shared_client/supabase_provider/supabase_provider.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/account.dart';
import 'package:physical_treatment_and_health_support_system/model/repository/auth_repository/i_auth_repository.dart';
import 'package:physical_treatment_and_health_support_system/model/repository/supabase_guard.dart';

/// Supabase Auth behind [IAuthRepository] (Table 4.54). The account row is
/// created by the sign-up trigger (private.handle_new_user) from the user
/// metadata {"username": ...}; the app only ever reads it here.
class SupabaseAuthRepository implements IAuthRepository {
  /// Deep link Google sign-in returns to (AndroidManifest intent-filter).
  static const String oauthRedirect = 'my.edu.tarumt.apths://login-callback';

  final SupabaseProvider _sb;

  /// Failed logins per email, for the lockout (FR100_031). Kept in memory:
  /// Supabase also rate-limits sign-ins on the server.
  final Map<String, List<DateTime>> _failures = {};

  /// Wrong verification codes per email since the code was issued (FR100_016). After
  /// AppConstants.maxCodeAttempts the app stops sending that code; "Resend code" issues a new
  /// one, which replaces the old code in Supabase.
  final Map<String, int> _codeRejections = {};
  final DateTime Function() _now;

  SupabaseAuthRepository(this._sb, {DateTime Function()? now})
    : _now = now ?? DateTime.now;

  GoTrueClient get _auth => _sb.client.auth;

  /// When the session was last used on this phone (FR100_034). Kept in the app's own preferences,
  /// which other apps cannot read (FR100_033); Supabase keeps the session itself the same way.
  static const _lastRenewedKey = 'apths.session.last_renewed';

  Future<void> _renew() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_lastRenewedKey, _now().toIso8601String());
    } catch (_) {
      // Preferences unavailable: the session simply does not expire on this phone.
    }
  }

  /// Ends the session when it was not used for SessionPolicy.lifetime (FR100_034).
  Future<bool> _expiredSession() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      var last = DateTime.tryParse(prefs.getString(_lastRenewedKey) ?? '');
      // Any sign-in (password, code, Google) after the last record renews the session.
      final signedIn = DateTime.tryParse(_auth.currentUser?.lastSignInAt ?? '');
      if (signedIn != null && (last == null || signedIn.isAfter(last))) {
        last = signedIn;
      }
      if (!SessionPolicy.expired(last, _now())) return false;
      await prefs.remove(_lastRenewedKey);
      await _auth.signOut();
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<Account> _accountRow(String uid) async {
    final row = await _sb
        .from('account')
        .select()
        .eq('account_id', uid)
        .single();
    return Account.fromJson(row);
  }

  @override
  Future<Result<Account?>> currentAccount() => supabaseGuard(() async {
    final uid = _sb.currentAccountId;
    if (uid == null) return null;
    if (await _expiredSession()) return null; // log in again (FR100_034)
    await _renew();
    final row = await _sb
        .from('account')
        .select()
        .eq('account_id', uid)
        .maybeSingle();
    return row == null ? null : Account.fromJson(row);
  });

  @override
  Future<Result<void>> register(
    String email,
    String password,
    String username,
  ) async {
    _codeRejections.remove(email.trim().toLowerCase());
    final res = await supabaseGuard(
      () => _auth.signUp(
        email: email.trim().toLowerCase(),
        password: password,
        data: {'username': username.trim()},
        // If the email holds a confirmation LINK (Supabase's default template) instead of the
        // 6-digit code, the link opens the app and signs the patient in, rather than a dead
        // localhost page. Needs this address in Supabase -> URL Configuration -> Redirect URLs.
        emailRedirectTo: oauthRedirect,
      ),
      failMessage: Messages.registrationUnavailable,
    );
    return switch (res) {
      // An existing address comes back as a user with no identities, so
      // Supabase does not reveal it to strangers; the app still says so (UC100 A3).
      Success(:final data) when (data.user?.identities ?? const []).isEmpty =>
        const Failure(Messages.emailExists, code: 'email_taken'),
      Success() => const Success(null),
      Failure(:final code)
          when code == 'user_already_exists' || code == 'email_exists' =>
        const Failure(Messages.emailExists, code: 'email_taken'),
      Failure f => f.cast<void>(),
    };
  }

  @override
  Future<Result<Account>> verify(String email, String code) async {
    final e = email.trim().toLowerCase();
    if ((_codeRejections[e] ?? 0) >= AppConstants.maxCodeAttempts) {
      return const Failure(Messages.codeExpired, code: 'code_attempts');
    }
    final res = await supabaseGuard(
      () => _auth.verifyOTP(email: e, token: code.trim(), type: OtpType.signup),
    );
    if (res case Failure(
      :final code,
    ) when code == 'otp_expired' || code == 'otp_invalid') {
      // Supabase uses otp_expired for wrong AND expired codes.
      _codeRejections[e] = (_codeRejections[e] ?? 0) + 1;
      return const Failure(Messages.codeIncorrect, code: 'otp_invalid');
    }
    _codeRejections.remove(e);
    if (res case Failure f) return f.cast<Account>();
    final uid =
        (res as Success<AuthResponse>).data.user?.id ?? _sb.currentAccountId;
    if (uid == null) {
      return const Failure(Messages.codeIncorrect, code: 'otp_invalid');
    }
    return supabaseGuard(() => _accountRow(uid));
  }

  @override
  Future<Result<void>> resendCode(String email) async {
    final e = email.trim().toLowerCase();
    final res = await supabaseGuard(
      () => _auth.resend(
        type: OtpType.signup,
        email: e,
        emailRedirectTo: oauthRedirect,
      ),
      failMessage: Messages.verificationEmailFailed,
    );
    if (res.isSuccess) _codeRejections.remove(e); // a new code: five new tries
    return res;
  }

  bool _locked(String email) {
    final cutoff = _now().subtract(AppConstants.loginLockout);
    final recent = (_failures[email] ?? const <DateTime>[])
        .where((t) => t.isAfter(cutoff))
        .toList();
    _failures[email] = recent;
    return recent.length >= AppConstants.maxLoginFailures;
  }

  @override
  Future<Result<Account>> login(String email, String password) async {
    final e = email.trim().toLowerCase();
    if (_locked(e)) {
      return const Failure(Messages.accountLocked, code: 'locked');
    }
    final res = await supabaseGuard(
      () => _auth.signInWithPassword(email: e, password: password),
      failMessage: Messages.loginUnavailable,
    );
    if (res case Failure(:final code) when code == 'invalid_credentials') {
      (_failures[e] ??= []).add(_now());
      return _locked(e)
          ? const Failure(Messages.accountLocked, code: 'locked')
          : const Failure(
              Messages.incorrectCredentials,
              code: 'invalid_credentials',
            );
    }
    if (res case Failure(:final code) when code == 'email_not_confirmed') {
      return const Failure(
        Messages.emailNotVerified,
        code: 'email_not_confirmed',
      );
    }
    if (res case Failure f) return f.cast<Account>();
    _failures.remove(e);
    await _renew();
    final uid = res.dataOrNull?.user?.id;
    if (uid == null) {
      return const Failure(Messages.loginUnavailable, code: 'unknown');
    }
    return supabaseGuard(
      () => _accountRow(uid),
      failMessage: Messages.loginUnavailable,
    );
  }

  /// Needs a Google OAuth client and the provider switched on in Supabase; until then the
  /// app explains instead of opening a browser page that cannot work (GOOGLE_SIGN_IN).
  @override
  Future<Result<void>> signInWithGoogle() async {
    if (!AppConstants.googleSignInEnabled) {
      return const Failure(Messages.googleNotAvailable, code: 'unsupported');
    }
    return supabaseGuard(
      () => _auth.signInWithOAuth(
        OAuthProvider.google,
        redirectTo: oauthRedirect,
      ),
      failMessage: Messages.loginUnavailable,
    );
  }

  /// Created by Google (first provider) and no username chosen by the patient: manual
  /// registration always stores one in the user metadata, Google never does.
  @override
  Future<Result<bool>> needsAccountSetup() async {
    final u = _auth.currentUser;
    if (u == null) return const Success(false);
    final chosen = (u.userMetadata?['username'] as String?)?.trim() ?? '';
    return Success(u.appMetadata['provider'] == 'google' && chosen.isEmpty);
  }

  /// FR100_022. The account row first, then the password and the username marker, so a
  /// failure part-way leaves the setup screen to be completed again.
  @override
  Future<Result<Account>> completeAccountSetup(
    String username,
    String password,
  ) async {
    final uid = _sb.currentAccountId;
    if (uid == null) {
      return const Failure(Messages.sessionExpired, code: 'no_session');
    }
    final name = username.trim();
    final account = await supabaseGuard(() async {
      final row = await _sb
          .from('account')
          .update({'username': name})
          .eq('account_id', uid)
          .select()
          .single();
      return Account.fromJson(row);
    }, failMessage: Messages.registrationUnavailable);
    if (account is Failure) return account;
    final updated = await supabaseGuard(
      () => _auth.updateUser(
        UserAttributes(password: password, data: {'username': name}),
      ),
      failMessage: Messages.registrationUnavailable,
    );
    if (updated case Failure f) return f.cast<Account>();
    await _renew();
    return account;
  }

  /// FR100_023. The database function removes the account only while it is still an
  /// unfinished Google sign-up (supabase/proposed/20261009130000_discard_incomplete_google_account.sql,
  /// not applied yet). Until it is applied the call fails and the patient is only signed out;
  /// the next Google sign-in then shows this setup screen again.
  @override
  Future<Result<void>> discardIncompleteAccount() async {
    await supabaseGuard(
      () => _sb.client.rpc('discard_incomplete_google_account'),
    );
    await signOut(); // the session on this phone is removed even when offline
    return const Success(null);
  }

  /// Supabase links a Google identity to the account with the same verified email by
  /// itself (FR100_021); this only tells whether that happened at this sign-in.
  @override
  Future<Result<bool>> googleJustLinked() async {
    final u = _auth.currentUser;
    if (u == null) return const Success(false);
    final providers = (u.appMetadata['providers'] as List?) ?? const [];
    if (!providers.contains('email') || !providers.contains('google')) {
      return const Success(false);
    }
    final google = [
      for (final i in u.identities ?? const <UserIdentity>[])
        if (i.provider == 'google') i,
    ];
    final linkedAt = google.isEmpty
        ? null
        : DateTime.tryParse(google.first.createdAt ?? '');
    return Success(
      linkedAt != null &&
          _now().difference(linkedAt).abs() < const Duration(minutes: 5),
    );
  }

  /// Always succeeds for a well-formed request, so the reply does not reveal
  /// whether the address has an account (FR100_038).
  @override
  Future<Result<void>> requestPasswordReset(String email) async {
    final res = await supabaseGuard(
      () => _auth.resetPasswordForEmail(email.trim().toLowerCase()),
    );
    if (res case Failure(
      :final code,
    ) when code == 'offline' || code == 'timeout') {
      return res;
    }
    return const Success(null);
  }

  @override
  Future<Result<void>> confirmPasswordReset(
    String email,
    String code,
    String newPassword,
  ) async {
    final verified = await supabaseGuard(
      () => _auth.verifyOTP(
        email: email.trim().toLowerCase(),
        token: code.trim(),
        type: OtpType.recovery,
      ),
    );
    if (verified case Failure(
      :final code,
    ) when code == 'otp_expired' || code == 'otp_invalid') {
      return const Failure(Messages.codeIncorrect, code: 'otp_invalid');
    }
    if (verified case Failure f) return f.cast<void>();
    final updated = await supabaseGuard(
      () => _auth.updateUser(UserAttributes(password: newPassword)),
    );
    if (updated case Failure f) return f.cast<void>();
    // FR100_041: every session ends; the patient logs in with the new password.
    return supabaseGuard(() => _auth.signOut(scope: SignOutScope.global));
  }

  /// FR100_061: the current password is checked by signing in with it again, then replaced.
  /// Other devices are signed out; this one stays signed in.
  @override
  Future<Result<void>> changePassword(
    String currentPassword,
    String newPassword,
  ) async {
    final email = _auth.currentUser?.email;
    if (email == null) {
      return const Failure(Messages.sessionExpired, code: 'no_session');
    }
    final check = await supabaseGuard(
      () => _auth.signInWithPassword(email: email, password: currentPassword),
    );
    if (check case Failure(:final code) when code == 'invalid_credentials') {
      return const Failure(
        Messages.currentPasswordIncorrect,
        code: 'wrong_password',
      );
    }
    if (check case Failure f) return f.cast<void>();
    final updated = await supabaseGuard(
      () => _auth.updateUser(UserAttributes(password: newPassword)),
    );
    if (updated case Failure f) return f.cast<void>();
    return supabaseGuard(() => _auth.signOut(scope: SignOutScope.others));
  }

  @override
  Future<Result<void>> signOut() => supabaseGuard(() async {
    await _auth.signOut();
    try {
      await (await SharedPreferences.getInstance()).remove(_lastRenewedKey);
    } catch (_) {
      // Nothing recorded: nothing to clear.
    }
  });
}
