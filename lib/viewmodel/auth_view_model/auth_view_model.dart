import 'dart:async';

import 'package:physical_treatment_and_health_support_system/viewmodel/base_view_model.dart';
import 'package:physical_treatment_and_health_support_system/model/result.dart';
import 'package:physical_treatment_and_health_support_system/viewmodel/ui_state.dart';
import 'package:physical_treatment_and_health_support_system/core/constants/app_constants.dart';
import 'package:physical_treatment_and_health_support_system/core/utils/form_validators.dart';
import 'package:physical_treatment_and_health_support_system/core/routes/routes.dart';
import 'package:physical_treatment_and_health_support_system/model/business_logic/local_notification_service/local_notification_service.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/account.dart';
import 'package:physical_treatment_and_health_support_system/model/repository/auth_repository/i_auth_repository.dart';
import 'package:physical_treatment_and_health_support_system/model/repository/profile_repository/i_profile_repository.dart';

/// Register, verify, log in and reset the password (UC100, UC200; Table 4.50).
/// One [UiState] per operation so each screen shows only its own spinner and error.
class AuthViewModel extends BaseViewModel {
  static const int resendCooldownSeconds = 60; // FR100_015

  final IAuthRepository _auth;
  final IProfileRepository _profiles;
  final LocalNotificationService? _notifications;

  AuthViewModel(this._auth, this._profiles, [this._notifications]);

  /// First screen when the app opens (FR100_024, FR100_025, FR100_035): no stored
  /// session -> login; signed in without a complete profile -> profile; else home.
  Future<String> decideStartRoute() async {
    final account = (await _auth.currentAccount()).dataOrNull;
    if (account == null) return Routes.loginScreen;
    // The app was closed during Google account setup: finish it first (FR100_022).
    if ((await _auth.needsAccountSetup()).dataOrNull ?? false) {
      return Routes.accountSetup;
    }
    // Refresh the phone's reminder schedule; it must not hold up start-up.
    _notifications?.sync(account.accountId).ignore();
    return _routeAfterSignIn(account);
  }

  UiState<void> loginState = const Idle();
  UiState<void> registerState = const Idle();
  UiState<void> verifyState = const Idle();
  UiState<void> resendState = const Idle();
  UiState<void> resetRequestState = const Idle();
  UiState<void> resetConfirmState = const Idle();
  UiState<void> changePasswordState = const Idle();
  UiState<void> googleState = const Idle();
  UiState<void> setupState = const Idle();

  /// One-time message for the next screen, e.g. UC100 M12 after Google was linked to the
  /// existing account. The screen that shows it sets it back to null.
  String? notice;

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
        'code_attempts' => Messages.codeExpired,
        'offline' || 'timeout' || 'unknown' =>
          registering
              ? Messages.registrationUnavailable
              : Messages.loginUnavailable,
        _ => f.message,
      };

  /// Complete profile -> home; none or incomplete -> profile screen (FR100_035).
  /// If the profile cannot be read, go home: RiskAssessmentService then applies the
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

  /// Changes the password from Profile (FR100_061): the current password is re-entered and the
  /// new one follows the same rule as registration.
  Future<bool> changePassword(
    String current,
    String newPassword,
    String confirm,
  ) async {
    final invalid = current.isEmpty
        ? Messages.passwordEmpty
        : FormValidators.password(newPassword) ??
              FormValidators.confirmPassword(newPassword, confirm) ??
              (newPassword == current ? Messages.passwordSameAsCurrent : null);
    if (invalid != null) {
      changePasswordState = UiError(invalid);
      notifyListeners();
      return false;
    }
    changePasswordState = const Loading();
    notifyListeners();
    final res = await _auth.changePassword(current, newPassword);
    changePasswordState = switch (res) {
      Success() => const UiSuccess(null),
      Failure f => UiError(messageFor(f)),
    };
    notifyListeners();
    return res.isSuccess;
  }

  /// Opens the Google page in the browser (FR100_018). The session arrives when the
  /// browser returns to the app; the login screen then calls [checkSignedIn].
  /// The repository says when Google is not set up yet ('unsupported').
  Future<void> signInWithGoogle() async {
    googleState = const Loading();
    notifyListeners();
    final res = await _auth.signInWithGoogle();
    if (res case Failure f) {
      googleState = UiError(
        f.code == 'unsupported' ? f.message : messageFor(f),
      );
      notifyListeners();
      return;
    }
    // On success the browser is open; the spinner stays until the patient comes back.
    // (Without a browser, as in the offline demo, the session is already here.)
    _awaitingGoogle = true;
    if (await checkSignedIn()) {
      _awaitingGoogle = false;
      return;
    }
    googleState = const Loading();
    notifyListeners();
  }

  bool _awaitingGoogle = false;

  /// Called when the app comes back to the front. After the Google page, Supabase
  /// receives the sign-in link a moment later, so this waits up to [wait] for the
  /// session before saying the sign-in did not finish (cancelled or failed).
  Future<bool> completeGoogleSignIn({
    Duration wait = const Duration(seconds: 10),
    Duration every = const Duration(milliseconds: 500),
  }) async {
    if (!_awaitingGoogle) return checkSignedIn();
    final deadline = DateTime.now().add(wait);
    while (true) {
      if (await checkSignedIn()) {
        _awaitingGoogle = false;
        return true;
      }
      if (isDisposed || DateTime.now().isAfter(deadline)) break;
      await Future<void>.delayed(every);
    }
    _awaitingGoogle = false;
    googleState = const UiError(Messages.googleNotFinished);
    notifyListeners();
    return false;
  }

  /// True when a session now exists (after the Google redirect); sets [nextRoute].
  Future<bool> checkSignedIn() async {
    final account = (await _auth.currentAccount()).dataOrNull;
    if (account == null) return false;
    if ((await _auth.needsAccountSetup()).dataOrNull ?? false) {
      nextRoute = Routes.accountSetup; // FR100_022
    } else {
      if ((await _auth.googleJustLinked()).dataOrNull ?? false) {
        notice = Messages.googleLinked; // FR100_021, UC100 M12
      }
      nextRoute = await _routeAfterSignIn(account);
    }
    googleState = const UiSuccess(null);
    notifyListeners();
    return true;
  }

  /// Complete Account Setup (FR100_022): the same username and password rules as manual
  /// registration (UC100 A1.1 to A1.3).
  Future<bool> completeAccountSetup(
    String username,
    String password,
    String confirm,
  ) async {
    final invalid =
        FormValidators.username(username) ??
        FormValidators.password(password) ??
        FormValidators.confirmPassword(password, confirm);
    if (invalid != null) {
      setupState = UiError(invalid);
      notifyListeners();
      return false;
    }
    setupState = const Loading();
    notifyListeners();
    final res = await _auth.completeAccountSetup(username.trim(), password);
    switch (res) {
      case Success(:final data):
        nextRoute = await _routeAfterSignIn(data);
        _notifications?.sync(data.accountId).ignore();
        setupState = const UiSuccess(null);
      case Failure f:
        setupState = UiError(messageFor(f, registering: true));
    }
    notifyListeners();
    return res.isSuccess;
  }

  /// UC100 A1.4 (FR100_023): signs out, removes the unfinished account and goes back to
  /// the login screen, where Google sign-in started.
  Future<void> cancelAccountSetup() async {
    setupState = const Loading();
    notifyListeners();
    await _auth.discardIncompleteAccount();
    nextRoute = Routes.loginScreen;
    setupState = const Idle();
    googleState = const Idle();
    notifyListeners();
  }

  void clearErrors() {
    if (loginState is UiError) loginState = const Idle();
    if (registerState is UiError) registerState = const Idle();
    if (verifyState is UiError) verifyState = const Idle();
    if (resetConfirmState is UiError) resetConfirmState = const Idle();
    if (changePasswordState is UiError) changePasswordState = const Idle();
    if (googleState is UiError) googleState = const Idle();
    if (setupState is UiError) setupState = const Idle();
    lastErrorCode = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}
