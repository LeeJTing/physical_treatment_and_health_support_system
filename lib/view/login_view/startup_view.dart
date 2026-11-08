import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:physical_treatment_and_health_support_system/core/constants/app_constants.dart';
import 'package:physical_treatment_and_health_support_system/core/routes/routes.dart';
import 'package:physical_treatment_and_health_support_system/core/themes/design_tokens.dart';
import 'package:physical_treatment_and_health_support_system/viewmodel/auth_view_model/auth_view_model.dart';
import 'package:physical_treatment_and_health_support_system/view/common/status_bar_strip.dart';

/// Splash shown while the stored session is checked; then replaced by the first
/// real screen so Back does not return here.
class StartupView extends StatefulWidget {
  const StartupView({super.key});

  @override
  State<StartupView> createState() => _StartupViewState();
}

class _StartupViewState extends State<StartupView> {
  /// The stored session could not be checked: no connection (Elwin, 23 Oct).
  bool _offline = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _start());
  }

  Future<void> _start() async {
    if (_offline) setState(() => _offline = false);
    final vm = context.read<AuthViewModel>();
    final route = await vm.decideStartRoute();
    if (!mounted) return;
    if (route == null) {
      setState(() => _offline = true); // still signed in: try again when online
      return;
    }
    final nav = Navigator.of(context)..pushReplacementNamed(route);
    // Started by tapping a reminder: its plan opens above Home, so Back goes Home.
    final open = vm.takeReminderOpen();
    if (open != null) nav.pushNamed(open.route, arguments: open.argument);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final vm = context.read<AuthViewModel>();
      final route = await vm.decideStartRoute();
      if (!mounted) return;
      final open = vm.takeReminderOpen();
      final nav = Navigator.of(context);
      // A meal reminder: Home opens on the Diet tab.
      if (open != null && route == Routes.home && Routes.replacesHome(open.route)) {
        nav.pushReplacementNamed(open.route);
        return;
      }
      nav.pushReplacementNamed(route);
      // Started by tapping a reminder: its plan opens above Home, so Back goes Home.
      if (open != null) nav.pushNamed(open.route, arguments: open.argument);
    });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: const StatusBarStrip(), // light icons on the green splash
    backgroundColor: AppTokens.brandDeep,
    body: Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.monitor_heart, color: Colors.white, size: 56),
            const SizedBox(height: 16),
            const Text(
              'HealthGuide',
              style: TextStyle(
                color: Colors.white,
                fontSize: 28,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 28),
            if (_offline) ...[
              const Text(
                Messages.noConnectionAtStart,
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white, fontSize: 17),
              ),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: _start,
                style: FilledButton.styleFrom(
                  backgroundColor: AppTokens.cta,
                  foregroundColor: Colors.white,
                  minimumSize: const Size(160, AppTokens.minTarget),
                  shape: const StadiumBorder(),
                ),
                child: const Text('Try again'),
              ),
            ] else
              const SizedBox(
                width: 28,
                height: 28,
                child: CircularProgressIndicator(
                  color: Colors.white,
                  strokeWidth: 3,
                ),
              ),
          ],
        ),
      ),
    ),
  );
}
