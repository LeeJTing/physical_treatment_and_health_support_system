import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:physical_treatment_and_health_support_system/view/diet_view/plan_comparison_panel.dart';
import '../support/plan_comparison_fixture.dart';

void runPlanComparisonFlows() {
  testWidgets(
    'plan comparison explains changes, chart selection and previous week',
    (t) async {
      if (t.binding is AutomatedTestWidgetsFlutterBinding) {
        t.view.physicalSize = const Size(390, 844);
        t.view.devicePixelRatio = 1;
        addTearDown(t.view.resetPhysicalSize);
        addTearDown(t.view.resetDevicePixelRatio);
      }
      final f = (await t.runAsync(PlanComparisonFixture.create))!;
      addTearDown(f.vm.dispose);
      await t.pumpWidget(f.app);
      await t.pumpAndSettle();
      await t.tap(find.text('Plan comparison'));
      await t.pumpAndSettle();
      expect(find.text('14 meals compared'), findsOneWidget);
      expect(find.text('4 close to plan · 10 with changes'), findsOneWidget);
      final scrollable = find
          .descendant(
            of: find.byType(PlanComparisonPanel),
            matching: find.byType(Scrollable),
          )
          .first;
      Future<void> scrollTo(Finder finder) async {
        await t.scrollUntilVisible(finder, 300, scrollable: scrollable);
        await t.pumpAndSettle();
      }

      await scrollTo(find.text('Show all 6 nutrients'));
      await t.tap(find.text('Show all 6 nutrients'));
      await t.pumpAndSettle();
      await scrollTo(find.text('Protein'));
      expect(find.text('Fat'), findsOneWidget);
      await scrollTo(find.byKey(const ValueKey('compare-day-1')));
      await t.tap(find.byKey(const ValueKey('compare-day-1')));
      await t.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('comparison-day-values')),
        findsOneWidget,
      );
      await scrollTo(find.text('Added: Teh tarik · 5 compared meals.'));
      expect(find.text('Added: Teh tarik · 5 compared meals.'), findsOneWidget);
      await scrollTo(find.text('Dinner'));
      await t.tap(find.text('Dinner'));
      await t.pumpAndSettle();
      await scrollTo(find.text('Added Teh tarik: 250 g.'));
      expect(
        find.text('Tofu was planned but is not in this log.'),
        findsOneWidget,
      );
      expect(find.textContaining('Logged − planned'), findsOneWidget);
      await t.tap(find.byTooltip('Previous week'));
      await t.pumpAndSettle();
      // A new period resets the day filter and uses its own comparable-meal denominator.
      expect(f.vm.insights!.comparison!.compared.length, 21);
      expect(find.text('21 meals compared').hitTestable(), findsOneWidget);
      expect(t.takeException(), isNull);
    },
  );
  testWidgets('empty comparison invites logging without a fabricated score', (
    t,
  ) async {
    final f = (await t.runAsync(
      () => PlanComparisonFixture.create(populated: false),
    ))!;
    addTearDown(f.vm.dispose);
    await t.pumpWidget(f.app);
    await t.pumpAndSettle();
    await t.tap(find.text('Plan comparison'));
    await t.pumpAndSettle();
    expect(find.text('0 meals compared'), findsOneWidget);
    expect(find.text('How meals matched'), findsNothing);
    expect(t.takeException(), isNull);
  });
}
