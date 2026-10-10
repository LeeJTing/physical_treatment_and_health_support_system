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
}
