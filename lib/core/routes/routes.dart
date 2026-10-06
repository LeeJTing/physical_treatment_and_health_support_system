class Routes {
  static const String init = '/';
  static const String loginScreen = '/login';
  static const String register = '/register';
  static const String verifyCode =
      '/verify-code'; // argument: the email address
  static const String resetPassword =
      '/reset-password'; // argument: optional email address

  // Elwin's modules (M300.1, M500, M600.1) and the shared home/profile
  static const String home = '/home';
  static const String healthProfile = '/profile';
  static const String treatmentPlanning = '/treatment-planning';
  static const String physicalTreatment = '/physical-treatment';
  static const String reminders = '/reminders';
  static const String sessionHistory = '/session-history';
}
