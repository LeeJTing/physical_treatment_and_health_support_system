import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';
import 'package:physical_treatment_and_health_support_system/core/routes/routes.dart';
import 'package:physical_treatment_and_health_support_system/core/themes/theme_constants.dart';
import 'package:physical_treatment_and_health_support_system/view/login_view/login_view.dart';
import 'package:physical_treatment_and_health_support_system/view/login_view/register_view.dart';
import 'package:physical_treatment_and_health_support_system/view/login_view/change_password_view.dart';
import 'package:physical_treatment_and_health_support_system/view/login_view/reset_password_view.dart';
import 'package:physical_treatment_and_health_support_system/view/login_view/verify_code_view.dart';
import 'package:physical_treatment_and_health_support_system/viewmodel/auth_view_model/auth_view_model.dart';
import 'package:physical_treatment_and_health_support_system/view/planning_view/planning_view.dart';
import 'package:physical_treatment_and_health_support_system/viewmodel/planning_view_model/planning_view_model.dart';
import 'package:physical_treatment_and_health_support_system/view/profile_view/profile_view.dart';
import 'package:physical_treatment_and_health_support_system/viewmodel/profile_view_model/profile_view_model.dart';
import 'package:physical_treatment_and_health_support_system/view/notification_view/notification_view.dart';
import 'package:physical_treatment_and_health_support_system/viewmodel/notification_view_model/notification_view_model.dart';
import 'package:physical_treatment_and_health_support_system/view/home_view/main_shell.dart';
import 'package:physical_treatment_and_health_support_system/view/login_view/startup_view.dart';
import 'package:physical_treatment_and_health_support_system/view/treatment_view/treatment_view.dart';
import 'package:physical_treatment_and_health_support_system/view/treatment_view/session_history_view.dart';
import 'package:physical_treatment_and_health_support_system/viewmodel/treatment_view_model/treatment_view_model.dart';
import 'package:physical_treatment_and_health_support_system/l10n/l10n.dart';

/// Root widget: theme, locales and routes. Each module registers its View
/// here as it is built.
class MainApp extends StatelessWidget {
  const MainApp({super.key});

  @override
  Widget build(BuildContext context) {
    // One AuthViewModel for all the sign-in screens, so the resend-code cooldown
    // started on Register carries over to the code screen (FR100_015).
    return ChangeNotifierProvider(
      create: (c) => AuthViewModel(c.read(), c.read(), c.read()),
      child: MaterialApp(
        title: 'HealthGuide',
        debugShowCheckedModeBanner: false,
        theme: lightTheme,
        darkTheme: darkTheme,
        // The Figma screens are light-only and hard-code light backgrounds; following
        // the phone's dark mode made theme-coloured text white on them.
        themeMode: ThemeMode.light,
        supportedLocales: L10n.all,
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        initialRoute: Routes.init,
        routes: {
          Routes.init: (_) => const StartupView(), // uses the app-wide AuthViewModel
          Routes.home: (_) => const MainShell(),
          Routes.loginScreen: (_) => const LoginView(),
          Routes.register: (_) => const RegisterView(),
          Routes.verifyCode: (_) => const VerifyCodeView(),
          Routes.resetPassword: (_) => const ResetPasswordView(),
          Routes.changePassword: (_) => const ChangePasswordView(),
          Routes.healthProfile: (_) => ChangeNotifierProvider(
            create: (c) => ProfileViewModel(c.read(), c.read(), c.read())..loadProfile(),
            child: const ProfileView(),
          ),
          Routes.treatmentPlanning: (_) => ChangeNotifierProvider(
            create: (c) => PlanningViewModel(
              c.read(),
              c.read(),
              c.read(),
              c.read(),
              c.read(),
            ),
            child: const PlanningView(),
          ),
          Routes.physicalTreatment: (_) => ChangeNotifierProvider(
            create: (c) => TreatmentViewModel(
              c.read(),
              c.read(),
              c.read(),
              c.read(),
              c.read(),
              c.read(),
            ),
            child: const TreatmentView(),
          ),
          Routes.reminders: (_) => ChangeNotifierProvider(
            create: (c) => NotificationViewModel(c.read(), c.read(), c.read()),
            child: const NotificationView(),
          ),
          Routes.sessionHistory: (_) => ChangeNotifierProvider(
            create: (c) => TreatmentViewModel(
              c.read(),
              c.read(),
              c.read(),
              c.read(),
              c.read(),
              c.read(),
            ),
            child: const SessionHistoryView(),
          ),
        },
      ),
    );
  }
}
