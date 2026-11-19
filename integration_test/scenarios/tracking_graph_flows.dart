import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/enums.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/biometric_reading.dart';
import '../support/tracking_graph_fixture.dart';

void runTrackingGraphFlows() {
  testWidgets('tracking graph shows values and import counts, and clears details in gaps', (t) async {
    final fixture = (await t.runAsync(TrackingGraphFixture.create))!;
    addTearDown(fixture.viewModel.dispose);
    await t.pumpWidget(fixture.app);
    await t.pumpAndSettle();
    final graph = find.byKey(const ValueKey('tracking-metric-chart'));
    final detail = find.byKey(const ValueKey('chart-reading-details'));
    for (final (metric, label) in [
      (MetricType.bloodPressure, 'Pressure'),
      (MetricType.bloodGlucose, 'Glucose'),
      (MetricType.bodyWeight, 'Weight'),
    ]) {
      await t.ensureVisible(find.text(label));
      await t.pumpAndSettle();
      await t.tap(find.text(label));
      await t.pumpAndSettle();
      expect(detail, findsNothing);
      expect(find.text('3 readings · 2 imported'), findsOneWidget);
      expect(find.textContaining('Latest import shown:'), findsOneWidget);
      await t.ensureVisible(graph);
      await t.pumpAndSettle();
      final rect = t.getRect(graph);
      // Oldest real record: plot's left edge. Empty gap: quarter way to the latest.
      await t.tapAt(Offset(rect.left + 40, rect.center.dy));
      await t.pumpAndSettle();
      expect(detail, findsOneWidget);
      final oldest = fixture.environment.biometrics.readings.firstWhere((r) => r.metricType == metric);
      expect(find.descendant(of: detail, matching: find.text('${metric.label}: ${oldest.display()}')), findsOneWidget);
      expect(find.descendant(of: detail, matching: find.textContaining('Recorded:')), findsOneWidget);
      expect(find.descendant(of: detail, matching: find.textContaining('Imported:')), findsOneWidget);
      await t.tapAt(Offset(rect.left + 40 + (rect.width - 48) * .25, rect.center.dy));
      await t.pumpAndSettle();
      expect(detail, findsNothing);
    }
    await t.ensureVisible(graph);
    await t.pumpAndSettle();
    final rect = t.getRect(graph);
    final centre = Offset(rect.left + 40 + (rect.width - 48) / 2, rect.center.dy);
    final first = await t.startGesture(centre - const Offset(30, 0), pointer: 1);
    final second = await t.startGesture(centre + const Offset(30, 0), pointer: 2);
    await t.pump();
    await first.moveTo(centre - const Offset(80, 0));
    await second.moveTo(centre + const Offset(80, 0));
    await t.pumpAndSettle();
    await first.up();
    await second.up();
    await t.pumpAndSettle();
    expect(t.widget<Text>(find.byKey(const ValueKey('chart-zoom-level'))).data, isNot('1.0×'));
    await t.ensureVisible(find.text('Reset zoom'));
    await t.pumpAndSettle();
    await t.tap(find.text('Reset zoom'));
    await t.pumpAndSettle();
    expect(find.text('1.0×'), findsOneWidget);
    final rows = fixture.environment.biometrics.readings;
    for (var i = 0; i < rows.length; i++) {
      rows[i] = BiometricReading.fromJson(rows[i].toJson()..remove('imported_at'));
    }
    await fixture.viewModel.load();
    await t.pumpAndSettle();
    expect(find.text('Import time not recorded for these older readings.'), findsOneWidget);
    final start = DateTime.now().subtract(const Duration(days: 20));
    await fixture.viewModel.loadRange(start, start.add(const Duration(days: 1)));
    await t.pumpAndSettle();
    expect(graph, findsNothing);
    expect(detail, findsNothing);
    expect(t.takeException(), isNull);
  });
}
