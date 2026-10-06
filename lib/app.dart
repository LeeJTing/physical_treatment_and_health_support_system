import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';
import 'package:physical_treatment_and_health_support_system/core/routes/routes.dart';
import 'package:physical_treatment_and_health_support_system/core/themes/theme_constants.dart';
import 'package:physical_treatment_and_health_support_system/features/auth/view/login_view.dart';
import 'package:physical_treatment_and_health_support_system/features/auth/view/register_view.dart';
import 'package:physical_treatment_and_health_support_system/features/auth/view/reset_password_view.dart';
import 'package:physical_treatment_and_health_support_system/features/auth/view/verify_code_view.dart';
import 'package:physical_treatment_and_health_support_system/features/auth/viewmodel/auth_view_model.dart';
import 'package:physical_treatment_and_health_support_system/features/planning/view/planning_view.dart';
import 'package:physical_treatment_and_health_support_system/features/planning/viewmodel/planning_view_model.dart';
import 'package:physical_treatment_and_health_support_system/features/profile/view/profile_view.dart';
import 'package:physical_treatment_and_health_support_system/features/profile/viewmodel/profile_view_model.dart';
import 'package:physical_treatment_and_health_support_system/features/reminders/view/reminders_view.dart';
import 'package:physical_treatment_and_health_support_system/features/reminders/viewmodel/notification_view_model.dart';
import 'package:physical_treatment_and_health_support_system/features/shell/view/main_shell.dart';
import 'package:physical_treatment_and_health_support_system/features/shell/view/startup_view.dart';
import 'package:physical_treatment_and_health_support_system/features/shell/viewmodel/startup_view_model.dart';
import 'package:physical_treatment_and_health_support_system/features/treatment/view/physical_treatment_view.dart';
import 'package:physical_treatment_and_health_support_system/features/treatment/view/session_history_view.dart';
import 'package:physical_treatment_and_health_support_system/features/treatment/viewmodel/treatment_view_model.dart';
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
      create: (c) => AuthViewModel(c.read(), c.read()),
      child: MaterialApp(
        title: 'APTHS',
        debugShowCheckedModeBanner: false,
        theme: lightTheme,
        darkTheme: darkTheme,
        supportedLocales: L10n.all,
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        initialRoute: Routes.init,
        routes: {
          Routes.init: (_) => ChangeNotifierProvider(
                create: (c) => StartupViewModel(c.read(), c.read(), c.read()),
                child: const StartupView(),
              ),
          Routes.home: (_) => const MainShell(),
          Routes.loginScreen: (_) => const LoginView(),
          Routes.register: (_) => const RegisterView(),
          Routes.verifyCode: (_) => const VerifyCodeView(),
          Routes.resetPassword: (_) => const ResetPasswordView(),
          Routes.healthProfile: (_) => ChangeNotifierProvider(
                create: (c) => ProfileViewModel(c.read(), c.read())..loadProfile(),
                child: const ProfileView(),
              ),
          Routes.treatmentPlanning: (_) => ChangeNotifierProvider(
                create: (c) => PlanningViewModel(c.read(), c.read(), c.read(), c.read(), c.read()),
                child: const PlanningView(),
              ),
          Routes.physicalTreatment: (_) => ChangeNotifierProvider(
                create: (c) => TreatmentViewModel(c.read(), c.read(), c.read(), c.read(), c.read()),
                child: const PhysicalTreatmentView(),
              ),
          Routes.reminders: (_) => ChangeNotifierProvider(
                create: (c) => NotificationViewModel(c.read(), c.read(), c.read()),
                child: const RemindersView(),
              ),
          Routes.sessionHistory: (_) => ChangeNotifierProvider(
                create: (c) => TreatmentViewModel(c.read(), c.read(), c.read(), c.read(), c.read()),
                child: const SessionHistoryView(),
              ),
        },
      ),
    );
  }
}
