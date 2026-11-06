import 'package:physical_treatment_and_health_support_system/model/entity/enums.dart';

/// App-wide constants. Values marked TO CONFIRM are not fixed by the report.
class AppConstants {
  AppConstants._();

  // ---- AI server (FastAPI) --------------------------------------------------
  /// The AI server on the laptop (Cloudflare tunnel). The tunnel address changes each time it
  /// starts: set the new one in the app (Profile > AI server), or build with
  /// --dart-define=AI_BASE_URL=... The emulator reaches a server on the same PC at http://10.0.2.2:8000.
  static const String aiBaseUrl = String.fromEnvironment(
    'AI_BASE_URL',
    defaultValue: 'https://billion-rehab-marker-uploaded.trycloudflare.com',
  );

  // ---- Supabase ---------------------------------------------------------------
  /// The team's Supabase project. The publishable key is meant to ship inside the app (RLS
  /// protects the data); the secret / service-role key never goes here. Override with
  /// --dart-define=SUPABASE_URL=... --dart-define=SUPABASE_ANON_KEY=... for another project.
  static const String supabaseUrl = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'https://whiyswvipvjajxkgppfj.supabase.co',
  );
  static const String supabaseAnonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
    defaultValue: 'sb_publishable_rDnBbYMBaPgqTSvtBDdiBQ_QcMhEtpe',
  );

  /// In-memory fakes instead of Supabase: only on request (--dart-define=USE_FAKES=true), e.g. a
  /// demo without internet. Every normal run uses the real Supabase project above.
  static const bool useFakes = bool.fromEnvironment(
    'USE_FAKES',
    defaultValue: false,
  );

  /// Continue with Google (FR100_018) is on. The app asks the Supabase project whether the
  /// Google provider is switched on before opening the browser, and explains when it is not.
  /// --dart-define=GOOGLE_SIGN_IN=false hides it on purpose (e.g. a demo without internet).
  static const bool googleSignInEnabled = bool.fromEnvironment(
    'GOOGLE_SIGN_IN',
    defaultValue: true,
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

  /// The slowest upload a clip is given time for (2 Mbit/s), added to [poseTimeout] per byte (bug
  /// list #5, 1 Nov): the 60 s used to cover the whole upload, so a 50 MB gallery clip on mobile
  /// data timed out as "temporarily unavailable" before the server saw it.
  static const int slowestUploadBytesPerSecond = 250000;

  // ---- Account (Table 3.3) -------------------------------------------------
  static const int usernameMin = 3;
  static const int usernameMax = 30;
  static const int passwordMin = 8;

  /// Supabase Auth (bcrypt) refuses longer passwords; not in Table 3.3 (PROJECT_STATE §11).
  static const int passwordMax = 72;
  static const int otpLength = 6;
  static const int maxLoginFailures = 5; // FR100_031
  static const int maxCodeAttempts =
      5; // FR100_016, UC100 C13: wrong codes per issued code
  static const Duration loginLockout = Duration(minutes: 15);

  // ---- Profile accepted ranges (Table 3.3) ---------------------------------
  static const int ageMin = 13, ageMax = 120;

  /// No exercise plan from this age (Terms of Use, section 2): the programmes
  /// proven for older adults were set up and followed by health
  /// professionals, and this app has none. Existing plans are paused.
  /// Same number as PLAN_AGE_LIMIT on the AI server.
  static const int planAgeLimit = 65;

  /// Under this age a parent or guardian agrees to the terms too (Age of
  /// Majority Act 1971; Contracts Act 1950 s.11; PDP Regulations 2013).
  static const int adultAge = 18;

  /// Version of the Terms of Use and Privacy Notice (assets/legal/terms.json,
  /// same "version"). Raising it asks every user to accept again at login.
  static const String termsVersion = '1.0';
  // Upper limits = the largest ever recorded (Elwin, 14 Oct; Guinness World
  // Records): tallest, Robert Wadlow 272 cm; heaviest, Jon Brower Minnoch
  // about 635 kg. Same limits in Supabase (20261014120000_profile_limits.sql).
  static const double weightMin = 20, weightMax = 635;
  static const double heightMin = 80, heightMax = 272;

  /// Weight and height together (23 Oct): each can be in range while the pair is not, e.g.
  /// 20 kg at 200 cm (BMI 5) or 635 kg at 80 cm. Outside BMI 7 to 200, beyond anything ever
  /// recorded (Minnoch about 185), it is a typing slip or the wrong unit. Not in Table 3.3.
  static const double bmiMin = 7, bmiMax = 200;
  static const Duration profileStaleAfter = Duration(
    days: 182,
  ); // UC1000 C3, TO CONFIRM

  // ---- Exercise video (UC500 C4, C5) ---------------------------------------
  static const int minVideoSeconds = 10;
  static const int maxVideoSeconds = 30;

  /// The recorder stops itself here, one second short of [maxVideoSeconds] (bug list #10, 1 Nov):
  /// the once-a-second timer is never early and stopping the camera takes a moment more, so a clip
  /// stopped at 30 could run past 30.5 s and be refused as too long by the app and the server.
  static const int autoStopSeconds = maxVideoSeconds - 1;

  /// Saved tries below 80% after which the plan moves on anyway (Elwin, 23 Oct), so nobody is
  /// stuck on one exercise. Below 80% the plan otherwise stays on it. Not in the report.
  static const int triesBeforeMovingOn = 3;

  /// Recording bitrate (NFR_07: the upload is most of the wait). 9 Oct test on 60 own clips at 720p
  /// (training/experiment_bitrate.py): 2.5 Mbps gave the same pass / fail as 5 Mbps on 60 of 60 at half
  /// the size; 3 Mbps leaves room for a phone encoder, which does a little worse per bit.
  static const int recordingBitrate = 3000000;
  static const int maxVideoBytes = 100 * 1024 * 1024;
  static const int minVideoHeightPx = 720;
  static const List<String> allowedVideoExtensions = ['mp4', 'mov'];

  // ---- Recommendation -------------------------------------------------------
  static const int topPlanCount = 3; // FR500_07

  // ---- Jun Ting's modules: M200, M400, M700 (AI server endpoints, Table 4.2.4) ----
  static const String forecastPath = '/forecast';
  static const String analysePath = '/analyse';
  static const String recognisePath = '/recognise';
  static const String planPath = '/plan';
  static const String alternativesPath = '/plan/alternatives';

  static const Duration recogniseTimeout = Duration(seconds: 15); // FR700_048
  static const Duration planTimeout = Duration(seconds: 20); // FR700_049
  static const Duration analysisTimeout = Duration(seconds: 30); // FR400_038

  // ---- M200 Health Monitoring (UC700) -----------------------------------------
  /// Plausible data-entry bounds (UC700 C7, FR200_004). Not clinical thresholds.
  static const double systolicMin = 70, systolicMax = 250;
  static const double diastolicMin = 40, diastolicMax = 150;
  static const double glucoseMin = 2.0, glucoseMax = 30.0;
  static const double bodyWeightMin = 20, bodyWeightMax = 300;

  static (double, double) plausibleRange(MetricType m) => switch (m) {
    MetricType.bloodPressure => (systolicMin, systolicMax),
    MetricType.bloodGlucose => (glucoseMin, glucoseMax),
    MetricType.bodyWeight => (bodyWeightMin, bodyWeightMax),
  };

  /// An imported reading within 5 minutes of a stored one is a duplicate (UC700 C11).
  static const Duration duplicateWindow = Duration(minutes: 5);

  /// No successful import for this long: the patient is told (UC700 C12, FR200_013).
  static const Duration importOverdueAfter = Duration(hours: 24);

  /// Background import interval (UC700 C10).
  static const Duration importInterval = Duration(hours: 6);

  /// While the app is open, Health Connect is checked this often for new readings, and again each
  /// time the app comes back to the front, so the patient never has to press Import readings.
  static const Duration autoSyncEvery = Duration(minutes: 1);

  /// Default and selectable trend ranges (UC700 C1, C13).
  static const int defaultRangeDays = 30;
  static const List<int> rangeChoices = [7, 30, 90];

  // ---- M400 Predictive Health Analysis (UC600) -----------------------------------
  static const int forecastMinReadings = 14; // C1
  static const int analysisPeriodDays = 7;

  // ---- M700 Diet Support (UC800, UC900) ------------------------------------------
  static const double recognitionConfidenceFloor = 0.60; // C6, FR700_005
  static const int maxImageBytes = 10 * 1024 * 1024; // C3
  static const int minImageSidePx = 224; // C3
  static const int uploadLongEdgePx = 384; // C4
  static const int uploadJpegQuality = 80; // C4

  /// WHO daily limits (UC900 C2, C6, C10) and the one-item share (C2).
  static const double whoSodiumMg = 2000;
  static const double whoSugarG = 25;
  static const double itemShare = 0.30;
  static const double cautionFrom = 0.80; // C8

  // ---- Reminders --------------------------------------------------------------
  static const String timezone = 'Asia/Kuala_Lumpur';
  static const int defaultReminderHour = 9; // TO CONFIRM
  static const int defaultReminderMinute = 0;
}

/// User-facing messages copied verbatim from the use case MESSAGE rows.
class Messages {
  Messages._();

  // UC600 reminders (not in the report's message list, PROJECT_STATE section 11)
  // Not a report message (FR600_008 asks for the permission; this says what a refusal means).
  static const notificationsOff =
      'Notifications are turned off for HealthGuide, so your reminders cannot ring. Tap Turn on '
      'notifications, switch them on, then come back to the app.';
  // Not a report message: Android 14+ without "Alarms & reminders" may deliver up to an hour late.
  static const remindersMayBeLate =
      'This phone may deliver reminders up to an hour late to save battery. For reminders on '
      'time, turn on Alarms & reminders for HealthGuide.';
  static const reminderNeedsADay =
      'Keep at least one day. To stop this reminder, switch it off.';

  // UC100 Register Account
  static const registrationUnavailable =
      'Registration service is temporarily unavailable. Please try again later.';
  static const usernameBlank =
      'Username cannot be blank. Please enter your name.';
  static const emailInvalid = 'Email address is invalid.';

  /// Not a report message (Elwin, 23 Oct): Table 3.3 only says 3 to 30 characters.
  static const usernameNeedsLetter =
      'Username must contain at least one letter.';
  static const passwordInvalid =
      'Password must be at least 8 characters and contain at least one letter and one number.';

  /// Not a report message (23 Oct): Supabase refuses passwords over 72 bytes.
  static const passwordTooLong = 'Password must be at most 72 characters.';
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

  /// Not a report message (Elwin, 23 Oct): the app opens signed in but cannot reach the server.
  static const noConnectionAtStart =
      'No connection to the server. Please check your internet connection and try again.';
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
  static const googleDemoMode =
      'Demo mode (USE_FAKES): signed in with a test Google account, so no Google page was shown. '
      'Run with --dart-define-from-file=config/dev.json to use real Google sign-in.'; // not a report message
  static const googleNoBrowser =
      'Could not open the Google sign-in page. Please check that a web browser is installed.'; // not a report message
  static const googleNotFinished =
      'Google sign-in did not finish. Please try again, or log in with your email and password.'; // not a report message

  // UC300 Manage Profile
  /// The profile age does not match the age group chosen in the Terms
  /// (14 Oct): review the Terms first.
  static const ageAboveTermsGroup =
      'In the Terms of Use you chose "13 to 17". If you are now 18 or older, '
      'review the Terms and choose "18 or older" first.';
  static const ageBelowTermsGroup =
      'In the Terms of Use you chose "18 or older". Under 18, a parent or '
      'guardian must agree to the Terms first: review the Terms.';

  /// Not a report message (23 Oct): weight and height that cannot belong to one person.
  static const weightHeightMismatch =
      'Your weight and height do not fit together. Please check both: weight in kilograms, '
      'height in centimetres.';
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

  // Health conditions (11 Oct; not in the report's message lists)
  static const conditionQuestionUnanswered =
      'Please answer the question under each health condition you selected.';
  static const otherConditionNote = 'Please say what the other condition is.';
  static const clearanceNeeded =
      'Before an exercise plan, please check with your doctor about the conditions below. When they '
      'agree, change your answer in your health profile.';

  // Terms of Use and account deletion (11 Oct; not in the report's message lists)
  static const termsSaveFailed =
      'Your agreement could not be saved. Please check your connection and try again.';
  static const confirmDeleteAccount =
      'Delete your account and all your data? Your health profile, plans, exercise results, '
      'reminders and chat messages are deleted for good. This cannot be undone.';
  static const accountDeleted =
      'Your account and all your data have been deleted.';
  static const accountDeleteFailed =
      'Your account could not be deleted. Please check your connection and try again, or '
      'email elwinksy-wm23@student.tarc.edu.my.';
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

  /// Not a report message (audit, 23 Oct): the plan was saved but its reminder was not.
  static const planSavedNoReminder =
      'The Plan has been saved, but its daily reminder could not be set. Please check your '
      'connection.';
  static const confirmReject =
      "Are you sure that you don't want to select any plan?";

  /// Report an answer (Elwin, 11 Oct; not in the report's message list, §11).
  static const chatReportSent =
      'Thank you. Your report will help us improve the chatbot.';
  static const chatReportFailed =
      'The report could not be sent. Please try again later.';

  static const questionNotRecognised =
      'The question is not recognised, please try asking other question.';

  /// The camera did not finish the clip (seen on Android 15 after leaving a
  /// recording). Not in the UC500 list (PROJECT_STATE §11).
  static const recordingFailed =
      'The recording could not be saved. Please record again.';

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
  // UC500 M8, word for word.
  static const fullBodyNotVisible =
      'Unable to detect full body in the frame. Please position yourself so that your entire body '
      '(head to feet) is clearly visible within the camera frame.';

  // UC600 View Health Report (Table 3.6 MESSAGE), word for word
  static const analysisDisclaimer =
      'This forecast, score and risk indication are generated for information only. They are not a '
      'medical diagnosis and do not replace advice from a qualified healthcare professional.';
  static const insufficientData =
      'At least 14 readings are needed before a forecast can be generated for this metric.';
  static const consultProfessional =
      'This reading is significantly outside your usual range. Please consult a healthcare professional.';
  static const healthRetrievalFailed =
      'Unable to load your health records. Please try again.';
  static const analysisUnavailable =
      'Your analysis could not be updated. Showing your last available forecast and score.';
  static const withinRange = 'Your recent readings are within your usual range.';
  static const notificationPermissionRequired =
      'Allow notifications so that reminders and health alerts can reach you. Alerts will still be '
      'recorded in your notification history.';
  static const coverageBelowMinimum =
      'Your Health Score needs at least 7 readings and 3 days of activity or meals. Keep recording '
      'and it will appear here.';
  static String riskInputAbsent(String condition, String metric) =>
      'A risk indication for $condition needs $metric readings. Record one to see it here.';

  // UC700 Track Health (Table 3.7 MESSAGE)
  static const healthPermissionRequired =
      'Permission to read your health data is required before readings can be imported.';
  static const importOverdue =
      'No readings have been imported for more than 24 hours.';
  static const emptyField = 'Please enter a value for every required field.';
  static const readingSaved = 'Your reading has been recorded.';
  static const implausibleValue =
      'The value entered is outside the accepted range. Please check your reading.';
  static const noData = 'No records were found for the selected period.';
  static const invalidDateRange =
      'The start date cannot be later than the end date.';
  static const confirmDeleteEntry =
      'Delete this entry? This action cannot be undone.';
  static const historyRetrievalFailed =
      'Unable to load your history. Please try again.';
  static const readingSaveFailed =
      'Unable to save your reading. Please try again.';
  static const importFailed =
      'Unable to import readings. The application will retry automatically.';
  static const deletionFailed =
      'Unable to delete the entry. Please try again.';
  // Not report messages (Health Connect missing; systolic rule; future time).
  static const healthConnectInstall =
      'Health Connect needs to be installed or updated on this phone. Tap Fix to open the Play Store, '
      'then connect again.'; // not a report message
  static const healthPermissionSteps =
      'HealthGuide was not allowed to read your health data. Tap Fix, then allow Blood pressure, '
      'Blood glucose and Weight for HealthGuide, and connect again.'; // not a report message
  static const healthConnectMissing =
      'Health Connect is not available on this phone. Install it from the Play Store to import readings.';
  static const systolicNotAboveDiastolic =
      'The systolic (top) value must be higher than the diastolic (bottom) value.';
  static const futureReading = 'The reading time cannot be later than now.';

  // UC800 View Food Information (Table 3.8 MESSAGE)
  static const invalidImage =
      'The selected image could not be read. Please choose a clear photograph of your meal.';
  static const lowConfidence =
      'We could not identify this meal confidently. Please select or enter the food item.';
  static const portionUpdated =
      'Nutrition values have been updated for the selected portion size.';
  static const cameraPermissionRequired =
      'Camera and photo access are required to log a meal.';
  static const mealLogged = 'Your meal has been recorded.';
  static const confirmDeleteMeal =
      'Delete this meal entry? This action cannot be undone.';
  static const recognitionUnavailable =
      'Food recognition is temporarily unavailable. You may enter your meal manually.';
  static const mealSaveFailed = 'Unable to save your meal. Please try again.';

  // UC900 View Food Recommendation (Table 3.9 MESSAGE)
  static String itemFlagged(String nutrient, String condition, String verdict, String amount) =>
      'This item is high in $nutrient. You have declared $condition, so it is $verdict. '
      'It exceeds your limit by $amount.';
  static const dietDisclaimer =
      'Dietary recommendations and plans are general guidance only and are not medical advice. Please '
      'consult a healthcare professional before making significant dietary changes.';
  static const allItemsSuitable =
      "None of today's logged meals exceed your recommended limits.";
  static const dietProfileUnavailable =
      'Unable to load your health profile. Conservative dietary limits have been applied.';
  static const plannerUnavailable =
      'The planner is temporarily unavailable. You can still build a plan by choosing meals yourself.';

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
