import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:physical_treatment_and_health_support_system/core/themes/design_tokens.dart';
import 'package:physical_treatment_and_health_support_system/features/home/view/home_view.dart';
import 'package:physical_treatment_and_health_support_system/features/profile/view/profile_view.dart';
import 'package:physical_treatment_and_health_support_system/features/profile/viewmodel/profile_view_model.dart';
import 'package:physical_treatment_and_health_support_system/features/treatment/view/treatment_tab_view.dart';
import 'package:physical_treatment_and_health_support_system/features/treatment/viewmodel/treatment_view_model.dart';

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
    return Scaffold(
      body: IndexedStack(index: _index, children: [
        const HomeView(),
        const ComingSoonView('Tracking'),
        ChangeNotifierProvider(
          create: (c) => TreatmentViewModel(c.read(), c.read(), c.read(), c.read(), c.read()),
          child: const TreatmentTabView(),
        ),
        const ComingSoonView('Diet'),
        ChangeNotifierProvider(
          create: (c) => ProfileViewModel(c.read(), c.read())..loadProfile(),
          child: const ProfileView(),
        ),
      ]),
      bottomNavigationBar: NavigationBarTheme(
        data: NavigationBarThemeData(
          backgroundColor: AppTokens.surface,
          indicatorColor: AppTokens.tint,
          height: 72,
          labelTextStyle: WidgetStateProperty.resolveWith((s) => TextStyle(
                fontSize: 13,
                fontWeight: s.contains(WidgetState.selected) ? FontWeight.w600 : FontWeight.w500,
                color: s.contains(WidgetState.selected) ? AppTokens.brandDeep : AppTokens.inkMuted,
              )),
          iconTheme: WidgetStateProperty.resolveWith((s) =>
              IconThemeData(size: 26, color: s.contains(WidgetState.selected) ? AppTokens.brandDeep : AppTokens.inkMuted)),
        ),
        child: NavigationBar(
          selectedIndex: _index,
          onDestinationSelected: (i) => setState(() => _index = i),
          destinations: const [
            NavigationDestination(icon: Icon(Icons.home_outlined), label: 'Home'),
            NavigationDestination(icon: Icon(Icons.show_chart), label: 'Tracking'),
            NavigationDestination(icon: Icon(Icons.fitness_center), label: 'Treatment'),
            NavigationDestination(icon: Icon(Icons.restaurant), label: 'Diet'),
            NavigationDestination(icon: Icon(Icons.person_outline), label: 'Profile'),
          ],
        ),
      ),
    );
  }
}
