import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:physical_treatment_and_health_support_system/core/themes/design_tokens.dart';
import 'package:physical_treatment_and_health_support_system/view/home_view/home_view.dart';
import 'package:physical_treatment_and_health_support_system/viewmodel/home_view_model/home_view_model.dart';
import 'package:physical_treatment_and_health_support_system/view/profile_view/profile_view.dart';
import 'package:physical_treatment_and_health_support_system/viewmodel/profile_view_model/profile_view_model.dart';
import 'package:physical_treatment_and_health_support_system/view/treatment_view/treatment_tab_view.dart';
import 'package:physical_treatment_and_health_support_system/viewmodel/treatment_view_model/treatment_view_model.dart';
import 'package:physical_treatment_and_health_support_system/view/common/status_bar_strip.dart';
import 'package:physical_treatment_and_health_support_system/view/common/user_guide.dart';
import 'package:physical_treatment_and_health_support_system/view/diet_view/diet_view.dart';
import 'package:physical_treatment_and_health_support_system/view/monitoring_view/monitoring_view.dart';
import 'package:physical_treatment_and_health_support_system/viewmodel/analysis_view_model/analysis_view_model.dart';
import 'package:physical_treatment_and_health_support_system/viewmodel/diet_plan_view_model/diet_plan_view_model.dart';
import 'package:physical_treatment_and_health_support_system/viewmodel/meal_log_view_model/meal_log_view_model.dart';
import 'package:physical_treatment_and_health_support_system/viewmodel/monitoring_view_model/monitoring_view_model.dart';

/// The five bottom tabs from the Figma screens (Home, Tracking, Treatment, Diet, Profile).
/// An IndexedStack keeps each tab's state when switching. Tracking (M200, with the M400 Health
/// Report) and Diet (M700) are Jun Ting's modules. One AnalysisViewModel serves Home's score card
/// and the Health Report, so both show the same analysis.
class MainShell extends StatefulWidget {
  /// Tab to open first, e.g. 2 for Treatment.
  final int initialTab;
  const MainShell({super.key, this.initialTab = 0});

  static const int trackingTab = 1;
  static const int treatmentTab = 2;
  static const int dietTab = 3;
  static const int profileTab = 4;

  /// The shell around [context], e.g. for Home's quick actions to open a tab.
  static MainShellState? of(BuildContext context) =>
      context.findAncestorStateOfType<MainShellState>();

  @override
  State<MainShell> createState() => MainShellState();
}

class MainShellState extends State<MainShell> with WidgetsBindingObserver {
  BuildContext? _inner;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Back in front (e.g. after adding a reading in another health app): look in Health Connect at
  /// once instead of waiting for the next minute.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    final c = _inner;
    if (c != null && c.mounted) c.read<MonitoringViewModel>().syncNow();
  }

  /// Opens a tab (Home's quick actions).
  void selectTab(int i) {
    final c = _inner;
    if (c != null) _select(c, i);
  }

  late int _index = widget.initialTab;

  @override
  Widget build(BuildContext context) {
    // The tab ViewModels live above the IndexedStack so switching tabs can refresh them.
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(
          create: (c) => HomeViewModel(c.read(), c.read(), c.read(), c.read()),
        ),
        ChangeNotifierProvider(
          create: (c) => TreatmentViewModel(
            c.read(),
            c.read(),
            c.read(),
            c.read(),
            c.read(),
            c.read(),
          ),
        ),
        ChangeNotifierProvider(
          create: (c) =>
              ProfileViewModel.withHealthSource(
                c.read(),
                c.read(),
                c.read(),
                c.read(),
                c.read(),
                c.read(),
              )
                ..loadProfile(),
        ),
        // Jun Ting's modules
        ChangeNotifierProvider(
          // Health Connect is kept in step all the time the app is open (not only on the
          // Tracking tab, and without pressing Import readings).
          create: (c) => MonitoringViewModel(c.read(), c.read(), c.read(), c.read(), c.read())
            ..startAutoSync(),
          lazy: false,
        ),
        ChangeNotifierProvider(
          create: (c) => AnalysisViewModel(
            c.read(),
            c.read(),
            c.read(),
            c.read(),
            c.read(),
            c.read(),
            c.read(),
            c.read(),
            c.read(),
          ),
        ),
        ChangeNotifierProvider(
          create: (c) => MealLogViewModel(c.read(), c.read(), c.read(), c.read(), c.read(), c.read(), c.read()),
        ),
        ChangeNotifierProvider(
          create: (c) => DietPlanViewModel(c.read(), c.read(), c.read(), c.read(), c.read()),
        ),
      ],
      child: Builder(builder: _scaffold),
    );
  }

  /// Data on Home and Treatment changes on other tabs (a finished exercise, a new plan,
  /// an edited profile), so they reload when opened again.
  void _select(BuildContext context, int i) {
    if (i == _index) return;
    setState(() => _index = i);
    if (i == 0) {
      context.read<HomeViewModel>().load();
      context.read<MealLogViewModel>().load();
      context.read<AnalysisViewModel>().loadAnalysis();
    }
    if (i == MainShell.treatmentTab) {
      context.read<TreatmentViewModel>().loadPlan();
    }
    if (i == MainShell.trackingTab) context.read<MonitoringViewModel>().load();
    if (i == MainShell.dietTab) {
      context.read<MealLogViewModel>().load();
      context.read<DietPlanViewModel>().loadRecommendations();
    }
    _guideFor(context, i);
  }

  /// The picture guide of a tab opens by itself the first time the tab is shown (the IndexedStack
  /// builds every tab at start, so the tabs cannot do this themselves).
  void _guideFor(BuildContext context, int i) {
    final guide = switch (i) {
      MainShell.trackingTab => Guides.tracking,
      MainShell.dietTab => Guides.diet,
      _ => null,
    };
    if (guide == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (context.mounted) showGuideOnce(context, guide);
    });
  }

  Widget _scaffold(BuildContext context) {
    if (_inner == null) _guideFor(context, _index); // opened straight on Tracking or Diet
    _inner = context;
    return Scaffold(
      appBar: StatusBarStrip(
        // Treatment's header is the darker planning green (Figma Treatment screen).
        color: _index == MainShell.treatmentTab
            ? AppTokens.primary
            : AppTokens.brandDeep,
      ),
      body: IndexedStack(
        index: _index,
        children: const [
          HomeView(),
          MonitoringView(),
          TreatmentTabView(),
          DietView(),
          ProfileView(),
        ],
      ),
      bottomNavigationBar: NavigationBarTheme(
        data: NavigationBarThemeData(
          backgroundColor: AppTokens.surface,
          indicatorColor: AppTokens.tint,
          height: 72,
          labelTextStyle: WidgetStateProperty.resolveWith(
            (s) => TextStyle(
              fontSize: 13,
              fontWeight: s.contains(WidgetState.selected)
                  ? FontWeight.w600
                  : FontWeight.w500,
              color: s.contains(WidgetState.selected)
                  ? AppTokens.brandDeep
                  : AppTokens.inkMuted,
            ),
          ),
          iconTheme: WidgetStateProperty.resolveWith(
            (s) => IconThemeData(
              size: 26,
              color: s.contains(WidgetState.selected)
                  ? AppTokens.brandDeep
                  : AppTokens.inkMuted,
            ),
          ),
        ),
        child: NavigationBar(
          selectedIndex: _index,
          onDestinationSelected: (i) => _select(context, i),
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.home_outlined),
              label: 'Home',
            ),
            NavigationDestination(
              icon: Icon(Icons.show_chart),
              label: 'Tracking',
            ),
            NavigationDestination(
              icon: Icon(Icons.fitness_center),
              label: 'Treatment',
            ),
            NavigationDestination(icon: Icon(Icons.restaurant), label: 'Diet'),
            NavigationDestination(
              icon: Icon(Icons.person_outline),
              label: 'Profile',
            ),
          ],
        ),
      ),
    );
  }
}
