// Health Tracking at phone size (phone test, 9 Nov): the "g" of "Tracking" broke onto a second line
// between the Health Report and help buttons, and the last letter of "Pressure" and "Glucose"
// dropped onto a second line when the button was chosen.
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:physical_treatment_and_health_support_system/device_platform/health_connect/health_data_source.dart';
import 'package:physical_treatment_and_health_support_system/model/business_logic/health_connect_service/health_connect_service.dart';
import 'package:physical_treatment_and_health_support_system/model/repository/auth_repository/fake_auth_repository.dart';
import 'package:physical_treatment_and_health_support_system/model/repository/biometric_repository/fake_biometric_repository.dart';
import 'package:physical_treatment_and_health_support_system/model/repository/treatment_repository/fake_treatment_repository.dart';
import 'package:physical_treatment_and_health_support_system/view/monitoring_view/monitoring_view.dart';
import 'package:physical_treatment_and_health_support_system/viewmodel/monitoring_view_model/monitoring_view_model.dart';

/// All of [text] is on one line.
void expectOneLine(WidgetTester tester, String text) {
  final p = tester.renderObject<RenderParagraph>(
    find.descendant(of: find.text(text), matching: find.byType(RichText)).first,
  );
  final tops = p.getBoxesForSelection(TextSelection(baseOffset: 0, extentOffset: text.length)).map((b) => b.top);
  expect(tops.toSet(), hasLength(1), reason: '"$text" is on one line');
}

void main() {
  for (final scale in [1.0, 1.3]) {
    testWidgets('Health Tracking header and the reading buttons stay on one line (text x$scale)', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 3; // 360 x 800, like the reference phone
      addTearDown(tester.view.reset);
      final auth = FakeAuthRepository();
      await tester.runAsync(() => auth.login('demo@apths.test', 'password123'));
      final vm = MonitoringViewModel(
        FakeBiometricRepository(),
        HealthConnectService(FakeHealthDataSource()),
        auth,
        FakeTreatmentRepository(const []),
      );
      await tester.pumpWidget(
        MaterialApp(
          builder: (c, child) => MediaQuery(
            data: MediaQuery.of(c).copyWith(textScaler: TextScaler.linear(scale)),
            child: child!,
          ),
          home: Scaffold(
            body: ChangeNotifierProvider.value(value: vm, child: const MonitoringView()),
          ),
        ),
      );
      await tester.runAsync(vm.load);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expectOneLine(tester, 'Health Tracking');
      // "How to use this screen" sits above the Health Report button.
      final help = tester.getCenter(find.byTooltip('How to use this screen'));
      final report = tester.getCenter(find.text('Health Report'));
      expect(help.dy, lessThan(report.dy));

      for (final name in ['Pressure', 'Glucose', 'Weight']) {
        await tester.ensureVisible(find.text(name));
        await tester.pump();
        await tester.tap(find.text(name));
        await tester.pump();
        for (final other in ['Pressure', 'Glucose', 'Weight']) {
          expectOneLine(tester, other);
        }
      }
      expect(tester.takeException(), isNull);
    });
  }
}
