import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:physical_treatment_and_health_support_system/core/themes/design_tokens.dart';

/// A zero-height app bar: only the status-bar area, filled with the header green and
/// with light icons. Screens with a green header band that scrolls away use it so the
/// clock and battery stay readable and content never slides under them.
class StatusBarStrip extends StatelessWidget implements PreferredSizeWidget {
  final Color color;
  const StatusBarStrip({super.key, this.color = AppTokens.brandDeep});

  @override
  Size get preferredSize => Size.zero;

  @override
  Widget build(BuildContext context) => AppBar(
    toolbarHeight: 0,
    elevation: 0,
    scrolledUnderElevation: 0,
    automaticallyImplyLeading: false,
    backgroundColor: color,
    surfaceTintColor: color,
    systemOverlayStyle: SystemUiOverlayStyle.light,
  );
}
