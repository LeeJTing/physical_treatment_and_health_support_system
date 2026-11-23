import 'dart:async';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:physical_treatment_and_health_support_system/model/business_logic/health_insights_service/health_insights_service.dart';
import 'package:physical_treatment_and_health_support_system/model/business_logic/health_insights_service/weekly_report_service.dart';
import 'package:physical_treatment_and_health_support_system/model/business_logic/suitability_service/suitability_service.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/biometric_reading.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/enums.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/health_insights.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/meal_log.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/safety_limit.dart';
import 'package:physical_treatment_and_health_support_system/model/repository/meal_repository/fake_meal_repository.dart';
import 'package:physical_treatment_and_health_support_system/model/result.dart';
import 'package:physical_treatment_and_health_support_system/viewmodel/health_insights_view_model/health_insights_view_model.dart';
import 'package:physical_treatment_and_health_support_system/viewmodel/health_insights_view_model/meal_simulation_view_model.dart';
import '../integration_test/support/health_insights_fixture.dart';
import '../integration_test/support/plan_comparison_fixture.dart';

class GateMeals extends FakeMealRepository {
  final gate = Completer<Result<List<MealLog>>>();
  @override
  Future<Result<List<MealLog>>> findMeals(String id, DateTime a, DateTime b) =>
      gate.future;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'timeline joins all five record kinds and retains original recorded time',
    () async {
      final f = await HealthInsightsFixture.create();
      addTearDown(f.dispose);
      final d = f.vm.data!;
      expect(
        d.timeline.map((e) => e.kind).toSet(),
        containsAll(TimelineKind.values),
      );
      expect(
        d.timeline.firstWhere((e) => e.id == 'bp-8').at,
        DateTime(2026, 11, 17, 8),
      );
      expect(d.facts.any((f) => f.title == 'Systolic blood pressure'), isTrue);
      expect(d.completeMealDays, 4);
      expect(d.comparison.compared, hasLength(14));
      expect(d.notices, isEmpty);
    },
  );
  test('demo filter excludes records without deleting saved history', () async {
    final f = await HealthInsightsFixture.create();
    addTearDown(f.dispose);
    expect(f.vm.data!.demoCount, 1);
    await f.vm.setIncludeDemo(false);
    expect(f.vm.data!.readings, hasLength(11));
    expect(f.vm.data!.timeline.any((e) => e.isDemo), isFalse);
    expect(f.base.readings.readings, hasLength(12));
    await f.vm.setIncludeDemo(true);
    expect(f.vm.data!.readings, hasLength(12));
  });
  test(
    'daily means prevent dense bursts from overweighting week comparisons',
    () {
      final readings = <BiometricReading>[];
      for (final (day, value) in [
        (9, 60.0),
        (10, 60.0),
        (16, 64.0),
        (17, 66.0),
      ]) {
        final n = day == 16 ? 30 : 1;
        for (var i = 0; i < n; i++) {
          readings.add(
            BiometricReading(
              readingId: '$day-$i',
              accountId: 'a',
              metricType: MetricType.bodyWeight,
              primaryValue: value,
              recordedAt: DateTime(2026, 11, day, 8, i),
            ),
          );
        }
      }
      readings.add(
        BiometricReading(
          readingId: 'other',
          accountId: 'b',
          metricType: MetricType.bodyWeight,
          primaryValue: 99,
          recordedAt: DateTime(2026, 11, 17, 8),
        ),
      );
      final d = const HealthInsightsService().build(
        accountId: 'a',
        start: DateTime(2026, 11, 16),
        now: DateTime(2026, 11, 20),
        meals: [],
        readings: readings,
        plans: [],
        treatments: [],
        sessions: [],
        checkIns: [],
      );
      expect(d.facts.last.text, contains('60.0 → 65.0'));
      expect(d.readings.any((r) => r.accountId == 'b'), isFalse);
      expect(d.loggedDays, 0);
      expect(d.facts.first.text, contains('unknown'));
    },
  );
  test('recovery save edits one row and never advances treatment', () async {
    final f = await HealthInsightsFixture.create();
    addTearDown(f.dispose);
    final ok = await f.vm.saveCheckIn(
      planId: 'assignment',
      date: DateTime(2026, 11, 19),
      pain: 3,
      stiffness: 2,
      difficulty: 2,
      notes: 'Better today',
    );
    expect(ok, isTrue);
    expect(f.recovery.rows, hasLength(2));
    expect(f.recovery.rows.last.checkInId, 'check-1');
    expect(f.vm.data!.recovery.single.painChange, -1);
    expect(
      (await f.treatments.getActivePlan(
        f.base.account,
      )).dataOrNull!.progressPercentage,
      33.33,
    );
    expect(
      await f.vm.saveCheckIn(
        planId: 'assignment',
        date: DateTime(2026, 11, 21),
        pain: 2,
        stiffness: 2,
        difficulty: 2,
      ),
      isFalse,
    );
    expect(f.recovery.rows, hasLength(2));
    expect(await f.vm.deleteCheckIn(f.recovery.rows.last), isTrue);
    expect(f.recovery.rows, hasLength(1));
  });
  test('old async responses cannot show data after logout', () async {
    final f = await HealthInsightsFixture.create();
    addTearDown(f.dispose);
    final meals = GateMeals();
    final vm = HealthInsightsViewModel(
      f.base.auth,
      f.base.readings,
      meals,
      f.treatments,
      f.recovery,
      now: () => PlanComparisonFixture.now,
    );
    addTearDown(vm.dispose);
    final pending = vm.load();
    await Future<void>.delayed(Duration.zero);
    await f.base.auth.signOut();
    meals.gate.complete(const Success([]));
    await pending;
    expect(vm.data, isNull);
    expect(vm.errorMessage, contains('session changed'));
  });
  test(
    'simulation is isolated, merges duplicates, rejects NaN and recalculates day once',
    () {
      final original = [
        MealItem.of(PlanComparisonFixture.rice, grams: 100),
        MealItem.of(PlanComparisonFixture.tea, grams: 250),
      ];
      final vm = MealSimulationViewModel(
        original,
        PlanComparisonFixture.rice.nutrientsFor(100 / 1.3),
        DietContext(limit: SafetyLimit.mostRestrictive()),
      );
      addTearDown(vm.dispose);
      expect(vm.resize(vm.proposed.first, 'NaN'), isFalse);
      expect(vm.proposed.first.portionSizeG, 100);
      expect(vm.resize(vm.proposed.first, '200'), isTrue);
      expect(original.first.portionSizeG, 100);
      vm.add(PlanComparisonFixture.rice);
      expect(
        vm.proposed.where((i) => i.food.foodKey == 'rice').single.portionSizeG,
        300,
      );
      expect(vm.result.afterDay.energyKcal, closeTo(100 + 390 + 212.5, .01));
      expect(vm.result.warnings, isNotEmpty);
      vm.reset();
      expect(vm.result.delta.energyKcal, 0);
    },
  );
  test('weekly PDF is generated offline from the same facts', () async {
    final f = await HealthInsightsFixture.create();
    addTearDown(f.dispose);
    final r = await const WeeklyReportService().create(f.vm.data!);
    expect(r, isA<Success>());
    expect(r.dataOrNull!.length, greaterThan(3000));
    final output = File(
      'build/health-insights-evidence/weekly-report-fixture.pdf',
    );
    output.parent.createSync(recursive: true);
    output.writeAsBytesSync(r.dataOrNull!);
  });
}
