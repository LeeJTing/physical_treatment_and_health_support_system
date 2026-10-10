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

/// The five bottom tabs from the Figma screens (Home, Tracking, Treatment, Diet, Profile).
/// An IndexedStack keeps each tab's state when switching. Tracking and Diet belong to
/// Jun Ting's modules (M200, M700) and are placeholders here.
class MainShell extends StatefulWidget {
  /// Tab to open first, e.g. 2 for Treatment.
  final int initialTab;
  const MainShell({super.key, this.initialTab = 0});

  static const int treatmentTab = 2;
  static const int profileTab = 4;

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
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
              ProfileViewModel(c.read(), c.read(), c.read(), c.read())
                ..loadProfile(),
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
    if (i == 0) context.read<HomeViewModel>().load();
    if (i == MainShell.treatmentTab) {
      context.read<TreatmentViewModel>().loadPlan();
    }
  }

  Widget _scaffold(BuildContext context) {
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
          ComingSoonView('Tracking'),
          TreatmentTabView(),
          ComingSoonView('Diet'),
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
