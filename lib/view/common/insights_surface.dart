import 'package:flutter/material.dart';
import 'package:physical_treatment_and_health_support_system/core/themes/design_tokens.dart';

/// Matches the established Diet / Tracking surfaces and orange primary actions.
class InsightsSurface extends StatelessWidget {
  final Widget child;
  const InsightsSurface({super.key, required this.child});
  static ButtonStyle get primaryButtonStyle => FilledButton.styleFrom(
    backgroundColor: AppTokens.cta,
    foregroundColor: Colors.white,
    minimumSize: const Size(0, 56),
    shape: const StadiumBorder(),
    textStyle: const TextStyle(
      fontFamily: 'Roboto',
      fontSize: 16,
      fontWeight: FontWeight.w600,
    ),
  );
  @override
  Widget build(BuildContext context) => Theme(
    data: Theme.of(context).copyWith(
      scaffoldBackgroundColor: AppTokens.screenBackground,
      filledButtonTheme: FilledButtonThemeData(style: primaryButtonStyle),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppTokens.brandDeep,
          minimumSize: const Size(0, 48),
          side: const BorderSide(color: AppTokens.outline),
          shape: const StadiumBorder(),
        ),
      ),
      cardTheme: CardThemeData(
        color: AppTokens.surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: AppTokens.cardBorder),
        ),
      ),
    ),
    child: child,
  );
}
