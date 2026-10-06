import 'dart:async';

import 'package:physical_treatment_and_health_support_system/core/base/base_view_model.dart';
import 'package:physical_treatment_and_health_support_system/core/base/result.dart';
import 'package:physical_treatment_and_health_support_system/core/base/ui_state.dart';
import 'package:physical_treatment_and_health_support_system/core/constants/app_constants.dart';
import 'package:physical_treatment_and_health_support_system/core/routes/routes.dart';
import 'package:physical_treatment_and_health_support_system/data/models/account.dart';
import 'package:physical_treatment_and_health_support_system/data/repository/interfaces/i_auth_repository.dart';
import 'package:physical_treatment_and_health_support_system/data/repository/interfaces/i_profile_repository.dart';

/// Register, verify, log in and reset the password (UC100, UC200; Table 4.50).
/// One [UiState] per operation so each screen shows only its own spinner and error.
class AuthViewModel extends BaseViewModel {
  static const int resendCooldownSeconds = 60; // FR100_015

  final IAuthRepository _auth;
  final IProfileRepository _profiles;

  AuthViewModel(this._auth, this._profiles);

  UiState<void> loginState = const Idle();
  UiState<void> registerState = const Idle();
  UiState<void> verifyState = const Idle();
  UiState<void> resendState = const Idle();
  UiState<void> resetRequestState = const Idle();
  UiState<void> resetConfirmState = const Idle();
  UiState<void> googleState = const Idle();

  /// Where to go after a successful login or verification (FR100_035).
  String? nextRoute;

  /// Code of the last failure, e.g. 'email_not_confirmed' so the login screen can offer "Resend code".
  String? lastErrorCode;

  int _secondsUntilResend = 0;
  int get secondsUntilResend => _secondsUntilResend;
  bool get canResend => _secondsUntilResend == 0;
  Timer? _timer;

  /// Report message for a repository failure (UC100/UC200 MESSAGE rows).
  static String messageFor(Failure<Object?> f, {bool registering = false}) =>
      switch (f.code) {
        'invalid_credentials' => Messages.incorrectCredentials,
        'email_not_confirmed' => Messages.emailNotVerified,
        'locked' => Messages.accountLocked,
        'email_taken' => Messages.emailExists,
        'use_google' => Messages.useGoogle,
        'otp_invalid' || 'invalid_code' => Messages.codeIncorrect,
        'offline' || 'timeout' || 'unknown' =>
          registering
              ? Messages.registrationUnavailable
              : Messages.loginUnavailable,
        _ => f.message,
      };

  /// Complete profile -> home; none or incomplete -> profile screen (FR100_035).
  /// If the profile cannot be read, go home: ProfileInfoService then applies the
  /// conservative default limits (UC1000 C5).
  Future<String> _routeAfterSignIn(Account a) async {
    final res = await _profiles.getProfile(a.accountId);
    if (res case Success(:final data)) {
      return data != null && data.isComplete
          ? Routes.home
          : Routes.healthProfile;
    }
    return Routes.home;
  }

  Future<bool> login(String email, String password) async {
    loginState = const Loading();
    lastErrorCode = null;
    notifyListeners();
    final res = await _auth.login(email, password);
    switch (res) {
      case Success(:final data):
        nextRoute = await _routeAfterSignIn(data);
        loginState = const UiSuccess(null);
      case Failure f:
        lastErrorCode = f.code;
        loginState = UiError(messageFor(f));
    }
    notifyListeners();
    return res.isSuccess;
  }

  Future<bool> register(String username, String email, String password) async {
    registerState = const Loading();
    notifyListeners();
    final res = await _auth.register(email, password, username);
    registerState = switch (res) {
      Success() => const UiSuccess(null),
      Failure f => UiError(messageFor(f, registering: true)),
    };
    if (res.isSuccess) _startCooldown(); // the first code was just sent
    notifyListeners();
    return res.isSuccess;
  }

  Future<bool> verify(String email, String code) async {
    verifyState = const Loading();
    notifyListeners();
    final res = await _auth.verify(email, code);
    switch (res) {
      case Success(:final data):
        nextRoute = await _routeAfterSignIn(data);
        verifyState = const UiSuccess(null);
      case Failure f:
        verifyState = UiError(messageFor(f, registering: true));
    }
    notifyListeners();
    return res.isSuccess;
  }

  Future<void> resendCode(String email) async {
    if (!canResend) return;
    resendState = const Loading();
    notifyListeners();
    final res = await _auth.resendCode(email);
    resendState = switch (res) {
      Success() => const UiSuccess(null),
      Failure f => UiError(
        f.code == 'offline' || f.code == 'timeout'
            ? Messages.verificationEmailFailed
            : f.message,
      ),
    };
    if (res.isSuccess) _startCooldown();
    notifyListeners();
  }

  void _startCooldown() {
    _timer?.cancel();
    _secondsUntilResend = resendCooldownSeconds;
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      _secondsUntilResend = (_secondsUntilResend - 1).clamp(
        0,
        resendCooldownSeconds,
      );
      if (_secondsUntilResend == 0) t.cancel();
      notifyListeners();
    });
  }

  /// Always reports the same neutral message (FR100_038).
  Future<bool> requestReset(String email) async {
    resetRequestState = const Loading();
    notifyListeners();
    final res = await _auth.requestPasswordReset(email);
    resetRequestState = switch (res) {
      Success() => const UiSuccess(null),
      Failure f => UiError(messageFor(f)),
    };
    if (res.isSuccess) _startCooldown();
    notifyListeners();
    return res.isSuccess;
  }

  Future<bool> confirmReset(
    String email,
    String code,
    String newPassword,
  ) async {
    resetConfirmState = const Loading();
    notifyListeners();
    final res = await _auth.confirmPasswordReset(email, code, newPassword);
    resetConfirmState = switch (res) {
      Success() => const UiSuccess(null),
      Failure f => UiError(messageFor(f)),
    };
    notifyListeners();
    return res.isSuccess;
  }

  /// Opens the Google page in the browser (FR100_018). The session arrives when the
  /// browser returns to the app; the login screen then calls [checkSignedIn].
  Future<void> signInWithGoogle() async {
    googleState = const Loading();
    notifyListeners();
    final res = await _auth.signInWithGoogle();
    googleState = switch (res) {
      Success() => const Idle(), // waiting for the redirect
      Failure f => UiError(f.code == 'unsupported' ? f.message : messageFor(f)),
    };
    notifyListeners();
  }

  /// True when a session now exists (after the Google redirect); sets [nextRoute].
  Future<bool> checkSignedIn() async {
    final account = (await _auth.currentAccount()).dataOrNull;
    if (account == null) return false;
    nextRoute = await _routeAfterSignIn(account);
    googleState = const UiSuccess(null);
    notifyListeners();
    return true;
  }

  void clearErrors() {
    if (loginState is UiError) loginState = const Idle();
    if (registerState is UiError) registerState = const Idle();
    if (verifyState is UiError) verifyState = const Idle();
    if (resetConfirmState is UiError) resetConfirmState = const Idle();
    if (googleState is UiError) googleState = const Idle();
    lastErrorCode = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}
