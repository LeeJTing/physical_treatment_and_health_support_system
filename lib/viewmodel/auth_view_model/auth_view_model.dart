import 'dart:async';

import 'package:physical_treatment_and_health_support_system/viewmodel/base_view_model.dart';
import 'package:physical_treatment_and_health_support_system/model/result.dart';
import 'package:physical_treatment_and_health_support_system/viewmodel/ui_state.dart';
import 'package:physical_treatment_and_health_support_system/core/constants/app_constants.dart';
import 'package:physical_treatment_and_health_support_system/core/utils/form_validators.dart';
import 'package:physical_treatment_and_health_support_system/core/routes/routes.dart';
import 'package:physical_treatment_and_health_support_system/model/business_logic/local_notification_service/local_notification_service.dart';
import 'package:physical_treatment_and_health_support_system/model/business_logic/local_notification_service/reminder_tap.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/enums.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/account.dart';
import 'package:physical_treatment_and_health_support_system/model/repository/auth_repository/i_auth_repository.dart';
import 'package:physical_treatment_and_health_support_system/model/repository/profile_repository/i_profile_repository.dart';
import 'package:physical_treatment_and_health_support_system/model/repository/terms_repository/i_terms_repository.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/terms_acceptance.dart';
import 'package:physical_treatment_and_health_support_system/core/utils/id_utils.dart';

/// Why the terms screen is shown (11 Oct): never accepted, a new version, or
/// the profile says the patient is under 18 but no guardian agreed.
enum TermsReason {
  firstTime,
  updated,
  guardianNeeded,

  /// Opened from the profile: the age entered does not match the age group
  /// chosen before (14 Oct). The screen goes back to the profile afterwards.
  ageChanged,
}

/// Register, verify, log in and reset the password (UC100, UC200; Table 4.50).
/// One [UiState] per operation so each screen shows only its own spinner and error.
class AuthViewModel extends BaseViewModel {
  static const int resendCooldownSeconds = 60; // FR100_015

  final IAuthRepository _auth;
  final IProfileRepository _profiles;
  final LocalNotificationService? _notifications;

  /// Terms of Use acceptances; null = no terms step (tests of other screens).
  final ITermsRepository? _terms;

  AuthViewModel(
    this._auth,
    this._profiles, [
    this._notifications,
    this._terms,
  ]) {
    _tapSub = _notifications?.taps().listen(_onReminderTap);
  }

  StreamSubscription<ReminderTap>? _tapSub;
  ({String route, Object? argument})? _reminderOpen;

  /// A tapped reminder while the app runs: the app root opens what it is about.
  Future<void> _onReminderTap(ReminderTap tap) async {
    final open = await _destinationFor(tap);
    if (open == null || isDisposed) return;
    _reminderOpen = open;
    notifyListeners();
  }

  /// An exercise reminder opens its plan, a health-logging reminder the Tracking screen and a
  /// health alert the Health Report. Nothing is opened
  /// for a signed-out patient or an unfinished Google account (they see login or setup first).
  Future<({String route, Object? argument})?> _destinationFor(
    ReminderTap tap,
  ) async {
    final String route;
    if (tap.alert) {
      route = Routes.healthReport; // a health alert (FR600_010)
    } else if (tap.type == ReminderType.healthLog) {
      route = Routes.monitoring; // record a reading (FR600_002)
    } else if (tap.type == ReminderType.exercise && tap.patientPlanId != null) {
      route = Routes.physicalTreatment;
    } else {
      return null;
    }
    if ((await _auth.currentAccount()).dataOrNull == null) return null;
    if ((await _auth.needsAccountSetup()).dataOrNull ?? false) return null;
    return (
      route: route,
      argument: route == Routes.physicalTreatment ? tap.patientPlanId : null,
    );
  }

  /// The screen a tapped reminder asked for, once (then null).
  ({String route, Object? argument})? takeReminderOpen() {
    final open = _reminderOpen;
    _reminderOpen = null;
    return open;
  }

  /// First screen when the app opens (FR100_024, FR100_025, FR100_035): no stored
  /// session -> login; signed in without a complete profile -> profile; else home.
  /// Null when the server cannot be reached to check a stored session (Elwin, 23 Oct): the
  /// patient stays signed in and the start screen offers Try again, instead of a Login page
  /// whose log in would fail offline too.
  Future<String?> decideStartRoute() async {
    final res = await _auth.currentAccount();
    if (res case Failure(:final code) when code == 'offline' || code == 'timeout') {
      return null;
    }
    final account = res.dataOrNull;
    if (account == null) return Routes.loginScreen;
    // The app was closed during Google account setup: finish it first (FR100_022).
    if ((await _auth.needsAccountSetup()).dataOrNull ?? false) {
      return Routes.accountSetup;
    }
    final route = await _routeAfterSignIn(account);
    // Started by tapping a reminder: its plan opens above Home (takeReminderOpen).
    final tap = await _notifications?.launchTap();
    if (tap != null && route == Routes.home) {
      _reminderOpen = await _destinationFor(tap);
    }
    return route;
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
  UiState<void> termsState = const Idle();

  /// Set when sign-in leads to the terms screen.
  TermsReason? termsReason;

  /// The profile age, when known, so a user under 18 cannot choose "18 or older".
  int? termsProfileAge;

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

  /// The terms first when they are needed (at registration, and at any sign-in
  /// after the version changed or a guardian is needed; 11 Oct), then
  /// [_profileRoute].
  Future<String> _routeAfterSignIn(Account a) async {
    // Every way in (app start, log in, code, Google, account setup) puts this account's
    // reminders on the phone again: logging out takes them off (Elwin, 23 Oct). Not awaited,
    // so it never holds up the next screen.
    _syncing = _notifications?.sync(a.accountId).then((_) {}, onError: (_) {});
    termsReason = await _termsNeeded(a);
    return termsReason != null ? Routes.terms : _profileRoute(a);
  }

  /// The reminder sync started at the last sign-in, so declining the terms can wait for it.
  Future<void>? _syncing;

  /// Null when the current terms are accepted. When the acceptances cannot be
  /// read (offline, or the table not created yet) the patient is not locked
  /// out, as with the profile.
  Future<TermsReason?> _termsNeeded(Account a) async {
    final terms = _terms;
    if (terms == null) return null;
    final res = await terms.latestAcceptance(a.accountId);
    if (res is! Success<TermsAcceptance?>) return null;
    final last = res.data;
    termsProfileAge = (await _profiles.getProfile(a.accountId)).dataOrNull?.age;
    if (last == null) return TermsReason.firstTime;
    if (last.termsVersion != AppConstants.termsVersion) return TermsReason.updated;
    final age = termsProfileAge;
    if (last.ageGroup == TermsAgeGroup.adult &&
        age != null &&
        age < AppConstants.adultAge) {
      return TermsReason.guardianNeeded;
    }
    return null;
  }

  /// The profile's new [age] does not match the age group accepted before:
  /// the terms are accepted again for it (adult from 18, else with a parent or
  /// guardian), then the profile is saved.
  void startAgeReview(int age) {
    termsReason = TermsReason.ageChanged;
    termsProfileAge = age;
    termsState = const Idle();
    notifyListeners();
  }

  /// Records the acceptance of the current terms, with the explicit consent
  /// for health data and, for a user aged 13 to 17, the parent or guardian
  /// who agreed; then sets [nextRoute].
  Future<bool> acceptTerms({
    required String language,
    required bool minor,
    String? guardianName,
    String? guardianRelationship,
  }) async {
    final terms = _terms;
    final account = (await _auth.currentAccount()).dataOrNull;
    if (terms == null || account == null) {
      termsState = const UiError(Messages.sessionExpired);
      notifyListeners();
      return false;
    }
    termsState = const Loading();
    notifyListeners();
    final res = await terms.saveAcceptance(
      TermsAcceptance(
        acceptanceId: newId(),
        accountId: account.accountId,
        termsVersion: AppConstants.termsVersion,
        acceptedAt: DateTime.now(),
        language: language,
        healthDataConsent: true,
        ageGroup: minor ? TermsAgeGroup.minor : TermsAgeGroup.adult,
        guardianName: minor ? guardianName?.trim() : null,
        guardianRelationship: minor ? guardianRelationship : null,
      ),
    );
    if (res.isSuccess) {
      final review = termsReason == TermsReason.ageChanged;
      termsReason = null;
      // From the profile: back to it (the view pops), no new route.
      nextRoute = review ? null : await _profileRoute(account);
      termsState = const UiSuccess(null);
    } else {
      termsState = const UiError(Messages.termsSaveFailed);
    }
    notifyListeners();
    return res.isSuccess;
  }

  /// The terms were declined: the app cannot be used, so sign out. Signing in put the
  /// account's reminders on the phone; they come off again, as at log out (audit, 23 Oct).
  Future<void> declineTerms() async {
    await _auth.signOut();
    await _syncing;
    await _notifications?.cancelEverything();
    termsReason = null;
    termsState = const Idle();
    nextRoute = Routes.loginScreen;
    notifyListeners();
  }

  /// Complete profile -> home; none or incomplete -> profile screen (FR100_035).
  /// If the profile cannot be read, go home: RiskAssessmentService then applies the
  /// conservative default limits (UC1000 C5).
  Future<String> _profileRoute(Account a) async {
    final res = await _profiles.getProfile(a.accountId);
    if (res case Success(:final data)) {
      return data != null && data.isComplete
          ? Routes.home
          : Routes.healthProfile;
    }
    return Routes.home;
  }

  Future<bool> login(String email, String password) async {
    lastErrorCode = null;
    // Checked here too, not only by the screen, as at registration and reset (audit, 23 Oct).
    // Only that a password was typed: the strength rule is for new passwords.
    final invalid =
        FormValidators.email(email) ??
        (password.isEmpty ? Messages.passwordEmpty : null);
    if (invalid != null) {
      loginState = UiError(invalid);
      notifyListeners();
      return false;
    }
    loginState = const Loading();
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
    // The same rules as the screen, checked here too (audit, 23 Oct).
    final invalid =
        FormValidators.username(username) ??
        FormValidators.email(email) ??
        FormValidators.password(password);
    if (invalid != null) {
      registerState = UiError(invalid);
      notifyListeners();
      return false;
    }
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
    // Checked here too, not only by the screen (audit, 23 Oct).
    final invalid = FormValidators.otp(code.trim());
    if (invalid != null) {
      verifyState = UiError(invalid);
      notifyListeners();
      return false;
    }
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
    if (res.isSuccess) {
      // The old "incorrect" or "expired" message is about the previous code.
      verifyState = const Idle();
      _startCooldown();
    }
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
    // The same rule as registration, checked here too and not only by the screen (23 Oct).
    final invalid =
        FormValidators.otp(code) ?? FormValidators.password(newPassword);
    if (invalid != null) {
      resetConfirmState = UiError(invalid);
      notifyListeners();
      return false;
    }
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
      // USE_FAKES build: the fake repository signs in a test Google account at once, so say why
      // no Google page appeared (real Google needs the Supabase build, supabase/HANDOFF.md 2a).
      if (AppConstants.useFakes) notice ??= Messages.googleDemoMode;
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
    if (termsState is UiError) termsState = const Idle();
    lastErrorCode = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _tapSub?.cancel();
    super.dispose();
  }
}
