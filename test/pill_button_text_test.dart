// The login screen's outlined pill button with large phone text (emulator at 2x, 24 Oct): an
// ellipsis left "Continue with G..."; the label now shrinks to fit on one line.
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:physical_treatment_and_health_support_system/view/login_view/widgets/auth_widgets.dart';

void main() {
  testWidgets('at 2x phone text "Continue with Google" is shown whole', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3; // 360 x 800
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        builder: (c, child) => MediaQuery(
          data: MediaQuery.of(
            c,
          ).copyWith(textScaler: const TextScaler.linear(2)),
          child: child!,
        ),
        home: const Scaffold(
          body: Padding(
            padding: EdgeInsets.all(24),
            child: OutlinedPillButton(
              label: 'Continue with Google',
              icon: GoogleMark(),
            ),
          ),
        ),
      ),
    );
    final paragraph = tester.renderObject<RenderParagraph>(
      find.descendant(
        of: find.text('Continue with Google'),
        matching: find.byType(RichText),
      ),
    );
    expect(paragraph.didExceedMaxLines, isFalse);
    expect(tester.takeException(), isNull);
  });
}
