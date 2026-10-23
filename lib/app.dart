import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';
import 'package:physical_treatment_and_health_support_system/core/routes/routes.dart';
import 'package:physical_treatment_and_health_support_system/core/themes/design_tokens.dart';
import 'package:physical_treatment_and_health_support_system/core/themes/theme_constants.dart';
import 'package:physical_treatment_and_health_support_system/view/login_view/login_view.dart';
import 'package:physical_treatment_and_health_support_system/view/login_view/register_view.dart';
import 'package:physical_treatment_and_health_support_system/view/login_view/change_password_view.dart';
import 'package:physical_treatment_and_health_support_system/view/login_view/account_setup_view.dart';
import 'package:physical_treatment_and_health_support_system/view/login_view/terms_view.dart';
import 'package:physical_treatment_and_health_support_system/view/login_view/reset_password_view.dart';
import 'package:physical_treatment_and_health_support_system/view/login_view/verify_code_view.dart';
import 'package:physical_treatment_and_health_support_system/viewmodel/auth_view_model/auth_view_model.dart';
import 'package:physical_treatment_and_health_support_system/view/planning_view/planning_view.dart';
import 'package:physical_treatment_and_health_support_system/view/planning_view/age_limit_view.dart';
import 'package:physical_treatment_and_health_support_system/view/planning_view/recommended_plans_view.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/patient_treatment_plan.dart';
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

  static final _navigator = GlobalKey<NavigatorState>();

  @override
  Widget build(BuildContext context) {
    // One AuthViewModel for all the sign-in screens, so the resend-code cooldown
    // started on Register carries over to the code screen (FR100_015).
    return ChangeNotifierProvider(
      create: (c) => AuthViewModel(c.read(), c.read(), c.read(), c.read()),
      child: MaterialApp(
        title: 'HealthGuide',
        debugShowCheckedModeBanner: false,
        // Flutter's own widgets (dialog buttons, time picker, spinners, text cursor) take the
        // theme's primary colour; the yellow AppColors.primaryLight gives about 1.9:1 contrast on
        // white, so they use the Figma brand green. Jun Ting's theme files are unchanged.
        theme: lightTheme.copyWith(
          colorScheme: lightTheme.colorScheme.copyWith(
            primary: AppTokens.brandDeep,
            onPrimary: Colors.white,
            // Time picker: the hour / minute box and the AM / PM switch (were yellow and purple).
            primaryContainer: AppTokens.accentContainer,
            onPrimaryContainer: AppTokens.brandDeep,
            tertiaryContainer: AppTokens.accentContainer,
            onTertiaryContainer: AppTokens.brandDeep,
          ),
          // Selected ChoiceChips (the health condition Yes / No) were the default purple; the
          // same light teal and dark green tick as the plan and chat topic chips (22 Oct).
          chipTheme: lightTheme.chipTheme.copyWith(
            selectedColor: AppTokens.accentContainer,
            checkmarkColor: AppTokens.brandDeep,
          ),
          // Segmented choices (Terms: language, age, guardian) were the default purple too;
          // the body map's own style for all of them (audit, 23 Oct).
          segmentedButtonTheme: SegmentedButtonThemeData(
            style: SegmentedButton.styleFrom(
              selectedBackgroundColor: AppTokens.primary,
              selectedForegroundColor: Colors.white,
              foregroundColor: AppTokens.primary,
              side: const BorderSide(color: AppTokens.primary),
            ),
          ),
        ),
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
        navigatorKey: _navigator,
        // A reminder tapped while the app runs opens its plan (AuthViewModel.takeReminderOpen).
        // Dark clock and battery icons by default, for the light screens; the screens with a
        // green band set light icons with StatusBarStrip, which wins over this (audit, 23 Oct:
        // the light icons of the last green screen stayed, so the clock vanished on cream).
        builder: (context, child) => AnnotatedRegion<SystemUiOverlayStyle>(
          value: SystemUiOverlayStyle.dark,
          child: _ReminderOpener(navigator: _navigator, child: child!),
        ),
        initialRoute: Routes.init,
        routes: {
          Routes.init: (_) =>
              const StartupView(), // uses the app-wide AuthViewModel
          Routes.home: (_) => const MainShell(),
          Routes.loginScreen: (_) => const LoginView(),
          Routes.register: (_) => const RegisterView(),
          Routes.verifyCode: (_) => const VerifyCodeView(),
          Routes.resetPassword: (_) => const ResetPasswordView(),
          Routes.changePassword: (_) => const ChangePasswordView(),
          Routes.accountSetup: (_) => const AccountSetupView(),
          Routes.terms: (_) => const TermsView(),
          Routes.healthProfile: (_) => ChangeNotifierProvider(
            create: (c) => ProfileViewModel(
              c.read(),
              c.read(),
              c.read(),
              c.read(),
              c.read(),
            )..loadProfile(),
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
          // Argument: the patient plan to move on from (complete, or too hard at the moment).
          Routes.nextPlan: (ctx) => ChangeNotifierProvider(
            create: (c) =>
                PlanningViewModel(
                  c.read(),
                  c.read(),
                  c.read(),
                  c.read(),
                  c.read(),
                )..recommendNext(
                  ModalRoute.of(ctx)!.settings.arguments!
                      as PatientTreatmentPlan,
                ),
            child: const RecommendedPlansView(),
          ),
          // Argument: the patient plan to show first (a tapped reminder, "Open this plan").
          Routes.physicalTreatment: (ctx) => ChangeNotifierProvider(
            create: (c) => TreatmentViewModel(
              c.read(),
              c.read(),
              c.read(),
              c.read(),
              c.read(),
              c.read(),
            )..preferPlan(ModalRoute.of(ctx)?.settings.arguments as String?),
            child: const TreatmentView(),
          ),
          Routes.ageLimit: (ctx) =>
              AgeLimitView(age: ModalRoute.of(ctx)?.settings.arguments as int?),
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

/// Opens what a tapped reminder is about when the app is already running; at start-up the
/// StartupView does it.
class _ReminderOpener extends StatefulWidget {
  final GlobalKey<NavigatorState> navigator;
  final Widget child;
  const _ReminderOpener({required this.navigator, required this.child});

  @override
  State<_ReminderOpener> createState() => _ReminderOpenerState();
}

class _ReminderOpenerState extends State<_ReminderOpener> {
  late final AuthViewModel _auth = context.read<AuthViewModel>();

  @override
  void initState() {
    super.initState();
    _auth.addListener(_open);
  }

  @override
  void dispose() {
    _auth.removeListener(_open);
    super.dispose();
  }

  void _open() {
    final open = _auth.takeReminderOpen();
    if (open == null) return;
    widget.navigator.currentState?.pushNamed(
      open.route,
      arguments: open.argument,
    );
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
