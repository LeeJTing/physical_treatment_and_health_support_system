import 'package:flutter_test/flutter_test.dart';
import 'package:physical_treatment_and_health_support_system/model/business_logic/diet_insights_service/plan_comparison_service.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/diet_plan.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/enums.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/meal_log.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/plan_comparison.dart';
import 'package:physical_treatment_and_health_support_system/model/result.dart';
import '../integration_test/support/plan_comparison_fixture.dart';

void main() {
  const service = PlanComparisonService();
  final start = PlanComparisonFixture.start, now = PlanComparisonFixture.now;
  final rice = PlanComparisonFixture.rice;
  MealLog meal(
    String id, {
    String account = 'a',
    DateTime? at,
    double grams = 100,
    List<MealItem>? items,
  }) => MealLog(
    mealId: id,
    accountId: account,
    mealType: MealSlot.lunch,
    entryMethod: EntryMethod.manual,
    consumedAt: at ?? DateTime(2026, 11, 16, 13),
    items: items ?? [MealItem.of(rice, grams: grams)],
  );
  DietPlan plan({
    String id = 'p',
    String account = 'a',
    PlanType type = PlanType.weekly,
    DateTime? generated,
    List<PlannedMeal>? items,
  }) => DietPlan(
    dietPlanId: id,
    accountId: account,
    safetyLimitId: 's',
    planType: type,
    startDate: start,
    endDate: start.add(const Duration(days: 6)),
    generatedAt: generated ?? start.subtract(const Duration(days: 1)),
    modelVersion: 'test',
    meals: items ?? [PlannedMeal.of(rice, start, MealSlot.lunch, 100)],
  );
  PlanComparisonReport build(
    List<MealLog> meals, {
    DietPlan? p,
    bool available = true,
  }) => service.build(
    accountId: 'a',
    start: start,
    now: now,
    meals: meals,
    plans: {start: p ?? plan()},
    plansAvailable: available,
  );

  test(
    'isolated review counts food, portion, close, unknown and future separately',
    () async {
      final f = await PlanComparisonFixture.create();
      addTearDown(f.vm.dispose);
      final r = f.vm.insights!.comparison!;
      expect(r.compared.length, 14);
      expect(r.count(MealComparisonStatus.close), 4);
      expect(r.count(MealComparisonStatus.portions), 5);
      expect(r.count(MealComparisonStatus.foods), 5);
      expect(r.count(MealComparisonStatus.noLog), 1);
      expect(r.count(MealComparisonStatus.upcoming), 6);
      expect(r.count(MealComparisonStatus.unplanned), 1);
      expect(r.previousMeals.length, 21);
      expect(r.repeatedChanges.first.meals, 5);
      expect(
        r.loggedAverage.energyKcal,
        closeTo((4 * 130 + 5 * 195 + 5 * 342.5) / 14, .001),
      );
      expect(
        PlanComparisonReport.average(
          r.previousMeals,
          planned: false,
        ).energyKcal,
        130,
      );
    },
  );
  test('duplicate items and logs preserve recorded nutrient snapshots', () {
    final one = MealItem.of(rice, grams: 50).toJson()..['energy_kcal'] = 7;
    final m = meal(
      'm',
      items: [MealItem.fromJson(one, rice), MealItem.fromJson(one, rice)],
    );
    final p = plan(
      items: [
        PlannedMeal(
          plannedMealId: 'old',
          food: rice,
          planDate: start,
          mealSlot: MealSlot.lunch,
          portionSizeG: 100,
          energyKcal: 99,
          sodiumMg: 9,
          sugarG: 8,
        ),
      ],
    );
    final r = build([m, m], p: p).compared.single;
    expect(r.foods.single.loggedG, 100);
    expect(r.logCount, 1);
    expect(r.logged.energyKcal, 14);
    expect(r.planned.energyKcal, 99);
    expect(r.planned.sodiumMg, 9);
    expect(r.planned.sugarG, 8);
    expect(r.difference.energyKcal, -85);
    expect(r.status, MealComparisonStatus.close);
  });
  test(
    'wrong account and future logs are excluded, and absent log is unknown',
    () {
      final r = build([
        meal('other', account: 'b'),
        meal('future', at: now.add(const Duration(hours: 1))),
      ]);
      expect(r.compared, isEmpty);
      expect(r.count(MealComparisonStatus.noLog), 1);
      expect(r.days.first.hasLogs, isFalse);
    },
  );
  test(
    'invalid records withhold totals instead of producing NaN or zero eaten',
    () {
      final r = build([meal('bad', grams: double.nan)]);
      expect(r.compared, isEmpty);
      expect(r.count(MealComparisonStatus.unavailable), 1);
      expect(r.days.first.validTotals, isFalse);
    },
  );
  test('unavailable plan retrieval never labels a meal unplanned', () {
    final r = build([meal('m')], available: false);
    expect(r.count(MealComparisonStatus.unplanned), 0);
    expect(r.count(MealComparisonStatus.unavailable), 1);
    expect(r.compared, isEmpty);
  });
  test(
    'a later saved plan is reference only and excluded from comparison averages',
    () {
      final r = build([meal('m')], p: plan(generated: now));
      expect(r.count(MealComparisonStatus.reference), 1);
      expect(r.compared, isEmpty);
    },
  );
  test('plan saved between two logs in a slot remains reference only', () {
    final r = build([
      meal('first'),
      meal('second', at: DateTime(2026, 11, 16, 15)),
    ], p: plan(generated: DateTime(2026, 11, 16, 14)));
    expect(r.count(MealComparisonStatus.reference), 1);
    expect(r.compared, isEmpty);
  });
  test(
    'portion tolerance is inclusive and a zero planned nutrient needs no percentage division',
    () {
      expect(
        build([meal('m', grams: 110)]).compared.single.status,
        MealComparisonStatus.close,
      );
      expect(
        build([meal('m', grams: 111)]).compared.single.status,
        MealComparisonStatus.portions,
      );
      expect(build([meal('m')]).loggedAverage.sugarG.isFinite, isTrue);
    },
  );
  test(
    'canonical plan precedence is account scoped and daily before latest weekly',
    () {
      final daily = plan(id: 'daily', type: PlanType.daily);
      expect(
        PlanComparisonService.selectPlan(
          [
            plan(id: 'weekly', generated: now),
            daily,
            plan(id: 'foreign', account: 'b', type: PlanType.daily),
          ],
          'a',
          start,
        )?.dietPlanId,
        'daily',
      );
      expect(
        PlanComparisonService.selectPlan(
          [plan(id: 'old'), plan(id: 'new', generated: now)],
          'a',
          start,
        )?.dietPlanId,
        'new',
      );
      expect(
        PlanComparisonService.selectPlan(
          [daily],
          'a',
          start.subtract(const Duration(days: 1)),
        ),
        isNull,
      );
    },
  );
  test(
    'period repository includes overlapping versions and excludes unrelated accounts',
    () async {
      final f = await PlanComparisonFixture.create();
      addTearDown(f.vm.dispose);
      final r = await f.meals.plansForPeriod(
        f.account,
        start.subtract(const Duration(days: 7)),
        now,
      );
      expect(r, isA<Success<List<DietPlan>>>());
      expect(r.dataOrNull, hasLength(2));
      expect(
        (await f.meals.plansForPeriod('other', start, now)).dataOrNull,
        isEmpty,
      );
    },
  );
}
