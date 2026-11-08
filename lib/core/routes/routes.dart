class Routes {
  static const String init = '/';
  static const String loginScreen = '/login';
  static const String register = '/register';
  static const String verifyCode =
      '/verify-code'; // argument: the email address
  static const String resetPassword =
      '/reset-password'; // argument: optional email address
  static const String changePassword = '/change-password';
  static const String accountSetup = '/account-setup';

  /// Terms of Use and Privacy Notice (11 Oct): after registration, and at a
  /// sign-in when the version changed or a guardian must agree.
  static const String terms = '/terms';

  // Elwin's modules (M300.1, M500, M600.1) and the shared home/profile
  static const String home = '/home';
  static const String healthProfile = '/profile';
  static const String treatmentPlanning = '/treatment-planning';

  /// Recommended plans for the next step after a plan (argument: the
  /// PatientTreatmentPlan to move on from).
  static const String nextPlan = '/next-plan';
  static const String physicalTreatment = '/physical-treatment';
  static const String reminders = '/reminders';
  static const String sessionHistory = '/session-history';

  /// Why there is no plan from 65 (Terms of Use, section 2). Argument: the
  /// profile age (int), optional.
  static const String ageLimit = '/age-limit';

  // Jun Ting's modules (M200, M400, M700)
  /// Health Tracking (UC700) on its own, e.g. from a health-logging reminder.
  static const String monitoring = '/monitoring';

  /// Health Report (UC600): forecast, Health Score, risks and anomalies.
  static const String healthReport = '/health-report';

  /// Dietary history (UC800 A5).
  static const String mealHistory = '/meal-history';

  /// Address of the AI server on the laptop, with Test connection (Profile > AI server).
  static const String serverSettings = '/server-settings';

  /// Today's and the weekly diet plan (UC900 A5, A6). Argument: PlanType.weekly for the week.
  static const String dietPlan = '/diet-plan';

  /// Home with the Diet tab open (a tapped meal reminder). It replaces Home instead of opening
  /// above it ([replacesHome]).
  static const String homeDiet = '/home/diet';

  /// Routes that are Home itself with another tab open.
  static bool replacesHome(String route) => route == homeDiet;
}
