import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:physical_treatment_and_health_support_system/model/business_logic/suitability_service/suitability_service.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/meal_log.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/safety_limit.dart';
import 'package:physical_treatment_and_health_support_system/view/diet_view/meal_simulation_view.dart';
import 'package:physical_treatment_and_health_support_system/view/health_insights_view/health_timeline.dart';
import 'package:physical_treatment_and_health_support_system/viewmodel/health_insights_view_model/meal_simulation_view_model.dart';
import '../support/health_insights_fixture.dart';
import '../support/plan_comparison_fixture.dart';

void runHealthInsightsFlows({
  Future<void> Function(WidgetTester, String)? capture,
}) {
  Future<void> viewport(WidgetTester t) async {
    if (t.binding is AutomatedTestWidgetsFlutterBinding) {
      t.view.physicalSize = const Size(390, 844);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
    }
  }

  Future<void> tab(WidgetTester t, String label) async {
    final f = find.widgetWithText(Tab, label);
    await t.ensureVisible(f);
    await t.tap(f);
    await t.pumpAndSettle();
  }

  testWidgets(
    'insights timeline selection, zoom, evidence navigation and demo exclusion',
    (t) async {
      await viewport(t);
      final f = (await t.runAsync(HealthInsightsFixture.create))!;
      addTearDown(f.dispose);
      await t.pumpWidget(
        RepaintBoundary(
          key: const ValueKey('insights-evidence'),
          child: f.app(),
        ),
      );
      await t.pumpAndSettle();
      await t.tap(find.byTooltip('Zoom in timeline'));
      await t.pumpAndSettle();
      expect(find.text('2×'), findsOneWidget);
      await t.tap(find.byTooltip('Zoom out timeline'));
      await t.pumpAndSettle();
      final marker = find.byTooltip('08:00 Blood pressure');
      await Scrollable.ensureVisible(t.element(marker), alignment: .5);
      await t.pumpAndSettle();
      await t.tap(marker);
      await t.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('timeline-selected-line')),
        findsOneWidget,
      );
      await capture?.call(t, 'timeline');
      await tab(t, 'Weekly report');
      expect(find.text('14 meals compared'), findsOneWidget);
      await capture?.call(t, 'weekly-report');
      final weeklyList = find.byKey(const ValueKey('weekly-insights-list'));
      final scroll = find
          .descendant(of: weeklyList, matching: find.byType(Scrollable))
          .first;
      await t.scrollUntilVisible(
        find.text('View supporting records'),
        280,
        scrollable: scroll,
      );
      await t.pumpAndSettle();
      await t.tap(find.byType(ActionChip).first);
      await t.pumpAndSettle();
      expect(find.byType(HealthTimeline), findsOneWidget);
      await tab(t, 'Data quality');
      expect(find.text('Understand your data'), findsOneWidget);
      await capture?.call(t, 'data-quality');
      await t.tap(find.byType(Switch).first);
      await t.pumpAndSettle();
      expect(f.vm.includeDemo, isFalse);
      expect(f.vm.data!.readings.length, 11);
      expect(t.takeException(), isNull);
    },
  );
  testWidgets('recovery diary shows worsening and saves a daily check-in', (
    t,
  ) async {
    await viewport(t);
    final f = (await t.runAsync(HealthInsightsFixture.create))!;
    addTearDown(f.dispose);
    await t.pumpWidget(
      RepaintBoundary(
        key: const ValueKey('insights-evidence'),
        child: f.app(tab: 3),
      ),
    );
    await t.pumpAndSettle();
    expect(find.text('How recovery feels'), findsOneWidget);
    await capture?.call(t, 'recovery');
    await t.tap(find.byKey(const ValueKey('new-recovery-check-in')));
    await t.pumpAndSettle();
    await t.enterText(find.byType(TextField), 'Fixture diary note');
    await capture?.call(t, 'recovery-check-in');
    await t.tap(find.text('Save check-in'));
    await t.pumpAndSettle();
    expect(f.recovery.rows, hasLength(3));
    expect(f.recovery.rows.last.notes, 'Fixture diary note');
    expect(
      (await f.treatments.getActivePlan(
        f.base.account,
      )).dataOrNull!.progressPercentage,
      33.33,
    );
    expect(t.takeException(), isNull);
  });
  testWidgets(
    'meal simulator updates nutrients then returns proposal without saving',
    (t) async {
      await viewport(t);
      final vm = MealSimulationViewModel(
        [MealItem.of(PlanComparisonFixture.rice)],
        PlanComparisonFixture.tofu.nutrientsFor(100),
        DietContext(limit: SafetyLimit.mostRestrictive()),
      );
      addTearDown(vm.dispose);
      await t.pumpWidget(
        RepaintBoundary(
          key: const ValueKey('insights-evidence'),
          child: ChangeNotifierProvider.value(
            value: vm,
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: ThemeData(
                useMaterial3: true,
                colorSchemeSeed: const Color(0xFF116C63),
              ),
              home: MealSimulationView(
                search: (_) async => [PlanComparisonFixture.tofu],
              ),
            ),
          ),
        ),
      );
      await t.pumpAndSettle();
      await t.tap(find.text('Edit grams'));
      await t.pumpAndSettle();
      await t.enterText(find.byKey(const ValueKey('simulation-grams')), '200');
      await t.tap(find.text('Update'));
      await t.pumpAndSettle();
      expect(vm.proposed.single.portionSizeG, 200);
      expect(vm.original.single.portionSizeG, 100);
      await capture?.call(t, 'meal-simulator');
      await t.tap(find.byTooltip('Reset simulation'));
      await t.pumpAndSettle();
      expect(vm.result.delta.energyKcal, 0);
      expect(t.takeException(), isNull);
    },
  );
  testWidgets('all insight tabs fit a narrow screen with larger text', (
    t,
  ) async {
    if (t.binding is! AutomatedTestWidgetsFlutterBinding) return;
    t.view.physicalSize = const Size(320, 640);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    t.platformDispatcher.textScaleFactorTestValue = 1.3;
    addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
    final f = (await t.runAsync(HealthInsightsFixture.create))!;
    addTearDown(f.dispose);
    await t.pumpWidget(f.app());
    await t.pumpAndSettle();
    for (final name in [
      'Timeline',
      'Weekly report',
      'Data quality',
      'Recovery',
    ]) {
      await tab(t, name);
      expect(t.takeException(), isNull, reason: name);
    }
  });
}
