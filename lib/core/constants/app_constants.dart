/// App-wide constants. Values marked TO CONFIRM are not fixed by the report.
class AppConstants {
  AppConstants._();

  // ---- AI server (FastAPI) --------------------------------------------------
  /// Overridden at build time: flutter run --dart-define=AI_BASE_URL=https://xxx.trycloudflare.com
  static const String aiBaseUrl = String.fromEnvironment(
    'AI_BASE_URL',
    defaultValue: 'http://10.0.2.2:8000',
  );

  static const String supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const String supabaseAnonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
  );

  /// Runs the app on in-memory fakes instead of Supabase (dev before Supabase is ready).
  static const bool useFakes = bool.fromEnvironment(
    'USE_FAKES',
    defaultValue: true,
  );

  /// Google sign-in needs a Google OAuth client and the provider switched on in Supabase
  /// (NEXT_STEPS Step 0 item 4). Until then the button explains instead of opening a
  /// browser page that cannot work. Build with --dart-define=GOOGLE_SIGN_IN=true once set up.
  static const bool googleSignInEnabled = bool.fromEnvironment(
    'GOOGLE_SIGN_IN',
    defaultValue: false,
  );

  // Endpoint paths (Table 4.2.4) used by Elwin's modules.
  static const String recommendPath = '/recommend';
  static const String chatPath = '/chat';
  static const String chatCategoriesPath = '/chat/categories';
  static const String posePath = '/pose';

  // Per-call timeouts.
  static const Duration defaultTimeout = Duration(
    seconds: 30,
  ); // FR100_011, FR100_032
  static const Duration recommendTimeout = Duration(seconds: 30); // NFR_08
  static const Duration poseTimeout = Duration(seconds: 60);

  // ---- Account (Table 3.3) -------------------------------------------------
  static const int usernameMin = 3;
  static const int usernameMax = 30;
  static const int passwordMin = 8;
  static const int otpLength = 6;
  static const int maxLoginFailures = 5; // FR100_031
  static const int maxCodeAttempts = 5; // FR100_016, UC100 C13: wrong codes per issued code
  static const Duration loginLockout = Duration(minutes: 15);

  // ---- Profile accepted ranges (Table 3.3) ---------------------------------
  static const int ageMin = 13, ageMax = 120;
  static const double weightMin = 20, weightMax = 300;
  static const double heightMin = 80, heightMax = 250;
  static const Duration profileStaleAfter = Duration(
    days: 182,
  ); // UC1000 C3, TO CONFIRM

  // ---- Exercise video (UC500 C4, C5) ---------------------------------------
  static const int minVideoSeconds = 10;
  static const int maxVideoSeconds = 30;
  static const int maxVideoBytes = 100 * 1024 * 1024;
  static const int minVideoHeightPx = 720;
  static const List<String> allowedVideoExtensions = ['mp4', 'mov'];

  // ---- Recommendation -------------------------------------------------------
  static const int topPlanCount = 3; // FR500_07

  // ---- Reminders --------------------------------------------------------------
  static const String timezone = 'Asia/Kuala_Lumpur';
  static const int defaultReminderHour = 9; // TO CONFIRM
  static const int defaultReminderMinute = 0;
}

/// User-facing messages copied verbatim from the use case MESSAGE rows.
class Messages {
  Messages._();

  // UC600 reminders (not in the report's message list, PROJECT_STATE section 11)
  static const reminderNeedsADay =
      'Keep at least one day. To stop this reminder, switch it off.';

  // UC100 Register Account
  static const registrationUnavailable =
      'Registration service is temporarily unavailable. Please try again later.';
  static const usernameBlank =
      'Username cannot be blank. Please enter your name.';
  static const emailInvalid = 'Email address is invalid.';
  static const passwordInvalid =
      'Password must be at least 8 characters and contain at least one letter and one number.';
  static const passwordMismatch =
      'Confirm password does not match your password. Please check both fields.';
  static const emailExists =
      'The entered email already has an account. Please log in instead.';
  static const useGoogle =
      'This email was registered with Google. Please continue with Google.';
  static const codeIncorrect = 'The verification code entered is incorrect.';
  static const codeExpired =
      'The verification code has expired. Please request a new code.';
  static const verificationEmailFailed =
      'We could not send the verification email. Please check your address and try again.';
  static const discardRegistration =
      'Cancel registration? The information you have entered will not be saved.';
  static const googleLinked =
      'Your Google account has been linked to your existing account.';
  static const registrationFailed =
      'Unable to create your account. Please try again.';

  // UC200 Login / reset password
  static const loginUnavailable =
      'Login service is temporarily unavailable. Please try again later.';
  static const emailEmpty = 'Please fill in your email address.';
  static const passwordEmpty = 'Please fill in your password.';
  static const resetCodeSent =
      'If an account exists for this email, a 6-digit reset code has been sent to it.';
  static const passwordResetDone =
      'Your password has been reset. Please log in with your new password.';
  static const googleOnlyAccount =
      'This account signs in with Google. Please use Continue with Google.';
  static const incorrectCredentials =
      'The email or password you entered is incorrect.';
  static const emailNotVerified =
      'Please verify your email address before logging in.';
  static const accountLocked =
      'Too many failed attempts. Your account is locked for 15 minutes.';
  static const googleNotAvailable =
      'Google sign-in is not available yet. Please log in with your email and password.'; // not a report message
  static const googleNotFinished =
      'Google sign-in did not finish. Please try again, or log in with your email and password.'; // not a report message

  // UC300 Manage Profile
  static const valueOutOfRange =
      'The value entered is outside the accepted range. Please check your entry.';
  static const requiredFieldsEmpty =
      'Please complete every required field before saving.';
  static const profileSaveFailed =
      'Unable to save your profile. Please try again.';
  static const profileSaved = 'Your health profile has been saved.';
  static const highRiskAdvisory =
      'Based on the conditions you declared, please consult a healthcare professional before starting any exercise programme.';
  static const passwordChanged =
      'Your password has been updated. You have been signed out of your other devices.';
  static const currentPasswordIncorrect =
      'The current password you entered is incorrect.';
  static const passwordSameAsCurrent =
      'Your new password must be different from your current password.';
  static const confirmLogout = 'Log out of your account?';
  static const discardChanges = 'Discard your unsaved changes?';
  static const profileLoadFailed =
      'Unable to load your profile. Please try again.';

  // UC400 (M500)
  static const conditionNotMet =
      'No suitable treatment plan is available based on your current health condition.';
  static const onlyOnePlan =
      'Only one suitable treatment plan has been identified based on your condition.';
  static const healthInfoFailed =
      'Unable to retrieve your health information. Please try again later.';
  static const recommendFailed =
      'Unable to generate a suitable treatment plan at this time. Please try again later.';
  static const dbUnavailable =
      'The service is temporarily unavailable. Please try again later.';
  static const planSaved = 'The Plan has been saved successfully.';
  static const confirmReject =
      "Are you sure that you don't want to select any plan?";
  static const questionNotRecognised =
      'The question is not recognised, please try asking other question.';

  // UC500 (M300)
  static const cameraFailed =
      'Camera access is unavailable. Please enable camera permission and try again.';
  static const planRetrieveFailed =
      'Unable to retrieve Treatment plan. Please try again later.';
  static const exerciseRetrieveFailed =
      'Unable to retrieve exercise details. Please try again later.';
  static const poseDetectFailed =
      'Unable to detect body posture from the captured video. Please adjust your position and try again.';
  static const postureAnalyseFailed =
      'Unable to analyse your exercise posture. Please try recording the exercise again.';
  static const deviceCompatibility =
      'Please Make Sure Your Device is having camera resolution of at least 720p.';
  static const videoInvalid =
      'Please Make Sure the video captured is between 10 - 30 seconds and under 100MB';
  static const progressSaveFailed =
      'Unable to save your exercise progress. Please try again later.';
  static const fullBodyNotVisible =
      'Unable to detect full body in the frame. Please position yourself so that your entire body is visible.';

  // UC1000
  static const profileNotConfigured =
      'Please complete your health profile to receive personalised guidance.';
  static const sessionExpired =
      'Your session has expired. Please log in again.';
  static const profileStale =
      'Your health profile has not been updated for over 6 months. Please review it.';
  static const profileUnavailable =
      'Unable to load your health profile. Conservative default limits have been applied.';
}
