import 'package:flutter_test/flutter_test.dart';
import 'package:physical_treatment_and_health_support_system/model/business_logic/diet_insights_service/diet_food_guidance_service.dart';
import 'package:physical_treatment_and_health_support_system/model/business_logic/diet_insights_service/plan_comparison_service.dart';
import 'package:physical_treatment_and_health_support_system/model/business_logic/suitability_service/suitability_service.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/diet_food_guidance.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/diet_plan.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/enums.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/food_item.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/lookups.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/meal_log.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/safety_limit.dart';
import '../integration_test/support/plan_comparison_fixture.dart';

void main() {
  final start = DateTime(2026, 11, 16), now = DateTime(2026, 11, 20, 22);
  final rice = PlanComparisonFixture.rice, tea = PlanComparisonFixture.tea;
  final tofu = FoodItem.fromJson({
    'food_id': 'tofu',
    'food_key': 'tofu',
    'food_name': 'Tofu',
    'food_category': 'Protein',
    'base_serving_g': 100,
    'energy_kcal_per_100g': 80,
    'protein_g_per_100g': 8,
    'sodium_mg_per_100g': 10,
    'restrictions': ['SOY'],
  });
  DietContext context({bool failSafe = false, bool restricted = false}) =>
      DietContext(
        limit: SafetyLimit.mostRestrictive(),
        age: 21,
        gender: Gender.male,
        weightKg: 65,
        heightCm: 180,
        failSafe: failSafe,
        restrictions: restricted
            ? const [
                DietaryRestriction(1, 'SOY', 'Soy', RestrictionType.allergy),
              ]
            : const [],
      );
  MealLog meal(
    int d, {
    String account = 'a',
    bool sweet = true,
    double riceG = 100,
  }) => MealLog(
    mealId: '$account-$d',
    accountId: account,
    mealType: MealSlot.lunch,
    entryMethod: EntryMethod.manual,
    consumedAt: start.add(Duration(days: d, hours: 13)),
    items: [
      MealItem.of(rice, grams: riceG),
      if (sweet) MealItem.of(tea, grams: 250),
    ],
  );
  DietFoodGuidance build(
    List<MealLog> meals, {
    DietContext? ctx,
    bool latePlan = false,
  }) {
    final p = DietPlan(
      dietPlanId: 'p',
      accountId: 'a',
      safetyLimitId: 's',
      planType: PlanType.weekly,
      startDate: start,
      endDate: start.add(const Duration(days: 6)),
      generatedAt: latePlan ? now : start.subtract(const Duration(days: 1)),
      modelVersion: 'test',
      meals: [
        for (var i = 0; i < 7; i++) ...[
          PlannedMeal.of(
            rice,
            start.add(Duration(days: i)),
            MealSlot.lunch,
            100,
          ),
          PlannedMeal.of(
            tofu,
            start.add(Duration(days: i)),
            MealSlot.lunch,
            100,
          ),
        ],
      ],
    );
    final comparison = const PlanComparisonService().build(
      accountId: 'a',
      start: start,
      now: now,
      meals: meals,
      plans: {for (var i = 0; i < 7; i++) start.add(Duration(days: i)): p},
    );
    return const DietFoodGuidanceService().build(
      comparison: comparison,
      meals: meals,
      plans: [p],
      accountId: 'a',
      now: now,
      context: ctx,
    );
  }

  test(
    'specific food, portion and reason; over-limit day offers a conditional swap',
    () {
      final d = build([meal(0)], ctx: context()).days.first;
      final less = d.actions.firstWhere((a) => a.foodName == 'Teh tarik');
      expect(less.kind, FoodGuidanceKind.replace);
      expect(less.loggedG, 250);
      final more = d.actions.firstWhere((a) => a.foodName == 'Tofu');
      expect(more.suggestedG, 100);
      expect(more.reason, contains('8.0 g protein'));
      expect(more.reason, contains('Only if replacing the 250 g Teh tarik'));
      expect(d.conclusion, contains('Partial day'));
      expect(d.conclusion, contains('30.0 / 25.0 g'));
    },
  );
  test('weekly frequencies and gram totals use recorded occurrences only', () {
    final r = build([meal(0), meal(1)], ctx: context());
    final p = r.priorities.firstWhere((p) => p.title.contains('Tofu'));
    expect(p.dates, [start, start.add(const Duration(days: 1))]);
    expect(p.detail, contains('2 recorded meals across 2 days'));
    expect(p.detail, contains('200 g in total'));
    expect(p.detail, contains('8.0 g protein'));
    expect(r.days[2].actions, isEmpty);
    expect(r.days[2].conclusion, contains('Intake is unknown'));
  });
  test('changed restrictions reject an old planned food', () {
    final r = build([meal(0, sweet: false)], ctx: context(restricted: true));
    expect(
      r.days.first.actions.where((a) => a.kind == FoodGuidanceKind.restore),
      isEmpty,
    );
  });
  test('missing or unreadable profile withholds personalised amounts', () {
    for (final ctx in [
      null,
      context(failSafe: true),
      DietContext(limit: SafetyLimit.mostRestrictive()),
    ]) {
      final r = build([meal(0)], ctx: ctx);
      expect(r.days.first.actions, isEmpty);
      expect(r.days.first.conclusion, contains('profile is unavailable'));
    }
  });
  test('later-created plan never generates restorative adherence advice', () {
    final r = build([meal(0, sweet: false)], ctx: context(), latePlan: true);
    expect(r.days.first.actions, isEmpty);
  });
  test(
    'duplicates, another account and future logs cannot inflate guidance',
    () {
      final r = build([
        meal(0),
        meal(0),
        meal(0, account: 'b'),
        meal(6),
      ], ctx: context());
      expect(r.priorities.every((p) => p.dates.length == 1), isTrue);
      expect(r.days.length, 5);
      expect(r.days.first.actions.first.loggedG, 250);
    },
  );
  test('no extra food is proposed above the current daily energy budget', () {
    final r = build([meal(0, sweet: false, riceG: 2000)], ctx: context());
    expect(
      r.days.first.actions.where((a) => a.kind == FoodGuidanceKind.restore),
      isEmpty,
    );
  });
}
