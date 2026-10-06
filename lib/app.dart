import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';
import 'package:physical_treatment_and_health_support_system/core/routes/routes.dart';
import 'package:physical_treatment_and_health_support_system/core/themes/theme_constants.dart';
import 'package:physical_treatment_and_health_support_system/features/home/view/home_view.dart';
import 'package:physical_treatment_and_health_support_system/features/planning/view/planning_view.dart';
import 'package:physical_treatment_and_health_support_system/features/planning/viewmodel/planning_view_model.dart';
import 'package:physical_treatment_and_health_support_system/l10n/l10n.dart';

/// Root widget: theme, locales and routes. Each module registers its View
/// here as it is built.
class MainApp extends StatelessWidget {
  const MainApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
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
      initialRoute: Routes.home,
      routes: {
        Routes.home: (_) => const HomeView(),
        Routes.loginScreen: (_) => const ComingSoonView('Login'),
        Routes.healthProfile: (_) => const ComingSoonView('Health Profile'),
        Routes.treatmentPlanning: (_) => ChangeNotifierProvider(
              create: (c) => PlanningViewModel(c.read(), c.read(), c.read(), c.read()),
              child: const PlanningView(),
            ),
        Routes.physicalTreatment: (_) => const ComingSoonView('Physical Treatment'),
        Routes.reminders: (_) => const ComingSoonView('Reminders'),
      },
    );
  }
}
