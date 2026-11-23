import 'dart:ui' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:physical_treatment_and_health_support_system/view/common/trend_chart.dart';

void main() {
  testWidgets('one-finger vertical swipes still scroll Tracking while pinch zoom is available', (t) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);
    await t.pumpWidget(MaterialApp(home: Scaffold(body: SingleChildScrollView(
      controller: controller,
      child: Column(children: [
        TrendChart(unit: 'kg', inspectable: true, zoomable: true, interactionId: 'scroll-chart', series: [
          ChartSeries('Weight', [ChartPoint(DateTime(2026, 11, 15), 65)], Colors.blue),
        ]),
        const SizedBox(height: 1000),
      ]),
    ))));
    await t.drag(find.byKey(const ValueKey('scroll-chart')), const Offset(0, -120));
    await t.pumpAndSettle();
    expect(controller.offset, greaterThan(50));
  });

  testWidgets('pinch zoom, panning and reset keep inspection tied to visible real records', (t) async {
    final start = DateTime(2026, 11, 15);
    await t.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 360,
            child: TrendChart(
              unit: 'kg',
              inspectable: true,
              zoomable: true,
              interactionId: 'zoom-chart',
              series: [
                ChartSeries('Weight', [
                  for (var i = 0; i <= 4; i++) ChartPoint(start.add(Duration(days: i)), 65 + i.toDouble()),
                ], Colors.blue),
              ],
            ),
          ),
        ),
      ),
    );
    final area = find.byKey(const ValueKey('zoom-chart'));
    final rect = t.getRect(area);
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
    expect((t.widget<Text>(find.byKey(const ValueKey('chart-zoom-level')))).data, isNot('1.0×'));
    await t.tap(find.text('Reset zoom'));
    await t.pumpAndSettle();
    await t.tap(find.byTooltip('Zoom in'));
    await t.pumpAndSettle();
    await t.tapAt(centre);
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('chart-reading-details')), findsOneWidget);
    await t.drag(area, const Offset(100, 0));
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('chart-reading-details')), findsNothing);
    await t.tap(find.text('Reset zoom'));
    await t.pumpAndSettle();
    expect(find.text('1.0×'), findsOneWidget);
    await t.tap(find.byTooltip('Zoom in'));
    await t.pumpAndSettle();
    expect(find.text('2.0×'), findsOneWidget);
    await t.tap(find.byTooltip('Zoom out'));
    await t.pumpAndSettle();
    expect(find.text('1.0×'), findsOneWidget);
    expect(t.takeException(), isNull);
  });

  testWidgets('hover and dragging inspect real points, clear in gaps and leave an empty chart blank', (t) async {
    final start = DateTime(2026, 11, 15);
    List<ChartSeries> lines = [
      ChartSeries('Systolic', [
        ChartPoint(start, 120),
        ChartPoint(start.add(const Duration(days: 4)), 128),
      ], Colors.red),
      ChartSeries('Diastolic', [
        ChartPoint(start, 80),
        ChartPoint(start.add(const Duration(days: 4)), 84),
      ], Colors.blue),
    ];
    Future<void> render() => t.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 320,
            child: TrendChart(series: lines, unit: 'mmHg', inspectable: true, interactionId: 'test-chart'),
          ),
        ),
      ),
    );
    await render();
    final area = find.byKey(const ValueKey('test-chart'));
    final details = find.byKey(const ValueKey('chart-reading-details'));
    final rect = t.getRect(area);
    final mouse = await t.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: rect.topLeft - const Offset(10, 10));
    addTearDown(mouse.removePointer);
    await mouse.moveTo(Offset(rect.left + 40, rect.center.dy));
    await t.pumpAndSettle();
    expect(details, findsOneWidget);
    expect(find.text('Systolic: 120.0 mmHg'), findsOneWidget);
    expect(find.text('Diastolic: 80.0 mmHg'), findsOneWidget);
    await mouse.moveTo(rect.topRight + const Offset(10, 10));
    await t.pumpAndSettle();
    expect(details, findsNothing);
    final finger = await t.startGesture(Offset(rect.left + 40, rect.center.dy));
    await t.pump(const Duration(milliseconds: 150));
    await finger.moveTo(Offset(rect.right - 8.1, rect.center.dy));
    await t.pumpAndSettle();
    expect(find.text('Systolic: 128.0 mmHg'), findsOneWidget);
    await finger.moveTo(rect.center);
    await t.pumpAndSettle();
    expect(details, findsNothing);
    await finger.up();
    lines = [];
    await render();
    await t.tapAt(rect.center);
    await t.pumpAndSettle();
    expect(details, findsNothing);
    expect(t.takeException(), isNull);
  });
}
