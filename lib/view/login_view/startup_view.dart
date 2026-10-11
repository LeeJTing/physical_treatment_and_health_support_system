import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:physical_treatment_and_health_support_system/core/themes/design_tokens.dart';
import 'package:physical_treatment_and_health_support_system/viewmodel/auth_view_model/auth_view_model.dart';

/// Splash shown while the stored session is checked; then replaced by the first
/// real screen so Back does not return here.
class StartupView extends StatefulWidget {
  const StartupView({super.key});

  @override
  State<StartupView> createState() => _StartupViewState();
}

class _StartupViewState extends State<StartupView> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final vm = context.read<AuthViewModel>();
      final route = await vm.decideStartRoute();
      if (!mounted) return;
      final nav = Navigator.of(context)..pushReplacementNamed(route);
      // Started by tapping a reminder: its plan opens above Home, so Back goes Home.
      final open = vm.takeReminderOpen();
      if (open != null) nav.pushNamed(open.route, arguments: open.argument);
    });
  }

  @override
  Widget build(BuildContext context) => const Scaffold(
    backgroundColor: AppTokens.brandDeep,
    body: Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.monitor_heart, color: Colors.white, size: 56),
          SizedBox(height: 16),
          Text(
            'HealthGuide',
            style: TextStyle(
              color: Colors.white,
              fontSize: 28,
              fontWeight: FontWeight.w700,
            ),
          ),
          SizedBox(height: 28),
          SizedBox(
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
  );
}
