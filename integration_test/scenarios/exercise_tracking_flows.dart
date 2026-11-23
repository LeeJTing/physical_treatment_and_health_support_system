import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/exercise_session.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/enums.dart';
import 'package:physical_treatment_and_health_support_system/view/monitoring_view/exercise_tracking_panel.dart';
import 'package:physical_treatment_and_health_support_system/view/common/trend_chart.dart';
import '../support/tracking_graph_fixture.dart';

void runExerciseTrackingFlows({
  Future<void> Function(WidgetTester, String)? capture,
}) {
  testWidgets(
    'exercise tracking inspects records, zooms, clears gaps and aggregates days',
    (t) async {
      if (t.binding is AutomatedTestWidgetsFlutterBinding) {
        t.view.physicalSize = const Size(390, 844);
        t.view.devicePixelRatio = 1;
        addTearDown(t.view.resetPhysicalSize);
        addTearDown(t.view.resetDevicePixelRatio);
      }
      final f = (await t.runAsync(TrackingGraphFixture.create))!;
      addTearDown(f.viewModel.dispose);
      await t.pumpWidget(
        RepaintBoundary(
          key: const ValueKey('exercise-tracking-evidence'),
          child: f.app,
        ),
      );
      await t.pumpAndSettle();
      await Scrollable.ensureVisible(
        t.element(find.text('Exercise')),
        alignment: .4,
      );
      await t.pumpAndSettle();
      await t.tap(find.text('Exercise'));
      await t.pumpAndSettle();
      expect(find.text('3 completed sessions · 2 days'), findsOneWidget);
      expect(find.text('Recorded exercise time: 6.0 minutes'), findsOneWidget);
      expect(find.text('Open treatment'), findsOneWidget);
      expect(find.text('Add Reading'), findsNothing);
      final graph = find.byKey(const ValueKey('tracking-exercise-chart'));
      final details = find.byKey(const ValueKey('chart-reading-details'));
      await Scrollable.ensureVisible(t.element(graph), alignment: .5);
      await t.pumpAndSettle();
      var rect = t.getRect(graph);
      await t.tapAt(Offset(rect.left + 40, rect.center.dy));
      await t.pumpAndSettle();
      expect(details, findsOneWidget);
      expect(
        find.descendant(of: details, matching: find.text('2 min 0 sec')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: details, matching: find.text('Repetitions: 8')),
        findsOneWidget,
      );
      await capture?.call(t, 'exercise-session-details');
      await t.tapAt(
        Offset(rect.left + 40 + (rect.width - 48) * .25, rect.center.dy),
      );
      await t.pumpAndSettle();
      expect(details, findsNothing);
      final zoom = find.descendant(
        of: find.byType(ExerciseTrackingPanel),
        matching: find.byTooltip('Zoom in'),
      );
      await Scrollable.ensureVisible(t.element(zoom), alignment: .5);
      await t.pumpAndSettle();
      await t.tap(zoom);
      await t.pumpAndSettle();
      expect(find.text('2.0×'), findsOneWidget);
      await capture?.call(t, 'exercise-zoomed');
      await t.tap(find.text('Reset zoom'));
      await t.pumpAndSettle();
      await Scrollable.ensureVisible(
        t.element(find.text('Daily total')),
        alignment: .4,
      );
      await t.pumpAndSettle();
      await t.tap(find.text('Daily total'));
      await t.pumpAndSettle();
      final chart = t.widget<TrendChart>(
        find.descendant(
          of: find.byType(ExerciseTrackingPanel),
          matching: find.byType(TrendChart),
        ),
      );
      expect(chart.series.single.points, hasLength(2));
      expect(chart.series.single.points.last.y, 4);
      await Scrollable.ensureVisible(t.element(graph), alignment: .5);
      await t.pumpAndSettle();
      rect = t.getRect(graph);
      await t.tapAt(Offset(rect.right - 9, rect.center.dy));
      await t.pumpAndSettle();
      expect(
        find.descendant(
          of: details,
          matching: find.text('2 completed sessions · 4.0 recorded minutes'),
        ),
        findsOneWidget,
      );
      await capture?.call(t, 'exercise-daily-total');
      final at = DateTime.now().subtract(const Duration(days: 20));
      await f.viewModel.loadRange(at, at.add(const Duration(days: 1)));
      await t.pumpAndSettle();
      expect(graph, findsNothing);
      expect(details, findsNothing);
      expect(
        find.textContaining('No completed exercise sessions in this period.'),
        findsOneWidget,
      );
      expect(t.takeException(), isNull);
    },
  );
  testWidgets(
    'missing exercise durations stay unknown and appear in session details',
    (t) async {
      final f = (await t.runAsync(TrackingGraphFixture.create))!;
      addTearDown(f.viewModel.dispose);
      final first = f.environment.treatments.sessions.first;
      f.environment.treatments.sessions
        ..clear()
        ..add(
          ExerciseSession(
            sessionId: 'unknown-duration',
            accountId: first.accountId,
            patientPlanId: first.patientPlanId,
            exerciseId: first.exerciseId,
            completedAt: first.completedAt,
            completionStatus: CompletionStatus.completed,
          ),
        );
      await t.pumpWidget(f.app);
      await t.pumpAndSettle();
      await Scrollable.ensureVisible(
        t.element(find.text('Exercise')),
        alignment: .5,
      );
      await t.pumpAndSettle();
      await t.tap(find.text('Exercise'));
      await t.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('tracking-exercise-chart')),
        findsNothing,
      );
      expect(
        find.textContaining('1 session duration is not recorded'),
        findsOneWidget,
      );
      expect(f.viewModel.data!.sessions.single.durationRecorded, isFalse);
      expect(t.takeException(), isNull);
    },
  );
  testWidgets(
    'unavailable exercise history offers retry without a zero-session claim',
    (t) async {
      await t.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ExerciseTrackingPanel(
              sessions: const [],
              from: DateTime(2026, 11, 1),
              to: DateTime(2026, 11, 24),
              available: false,
              onRetry: () {},
            ),
          ),
        ),
      );
      expect(find.textContaining('totals are unavailable'), findsOneWidget);
      expect(find.text('Retry exercise history'), findsOneWidget);
      expect(find.textContaining('0 completed sessions'), findsNothing);
      expect(t.takeException(), isNull);
    },
  );
}
