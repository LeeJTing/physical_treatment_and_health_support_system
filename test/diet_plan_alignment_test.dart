import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:physical_treatment_and_health_support_system/model/business_logic/diet_planner_service/diet_planner_service.dart';
import 'package:physical_treatment_and_health_support_system/model/business_logic/risk_assessment_service/risk_assessment_service.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/diet_plan.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/enums.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/food_item.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/meal_log.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/safety_limit.dart';
import 'package:physical_treatment_and_health_support_system/model/repository/auth_repository/fake_auth_repository.dart';
import 'package:physical_treatment_and_health_support_system/model/repository/food_repository/fake_food_repository.dart';
import 'package:physical_treatment_and_health_support_system/model/repository/meal_repository/fake_meal_repository.dart';
import 'package:physical_treatment_and_health_support_system/model/repository/profile_repository/fake_profile_repository.dart';
import 'package:physical_treatment_and_health_support_system/model/result.dart';
import 'package:physical_treatment_and_health_support_system/shared_client/api_client/api_client.dart';
import 'package:physical_treatment_and_health_support_system/viewmodel/diet_plan_view_model/diet_plan_view_model.dart';
import 'support/diet_plan_fixtures.dart';

class _FailPlanSave extends FakeMealRepository {
  bool refuse = false;
  bool refuseRead = false;
  @override
  Future<Result<DietPlan?>> planFor(String accountId, PlanType type, DateTime day) =>
      refuseRead ? Future.value(const Failure('offline')) : super.planFor(accountId, type, day);
  @override
  Future<Result<void>> savePlan(DietPlan p) => refuse ? Future.value(const Failure('offline')) : super.savePlan(p);
}

void main() {
  final foods = FakeFoodRepository.fromJson(File('assets/seed/food_catalogue.json').readAsStringSync());
  FoodItem food(String key) => foods.foods.firstWhere((f) => f.foodKey == key);
  final now = DateTime.now();
  final day = DateTime(now.year, now.month, now.day);
  final tomorrow = day.add(const Duration(days: 1));
  late FakeAuthRepository auth;
  late String account;
  late FakeMealRepository repo;

  DietPlan stored(PlanType type, List<PlannedMeal> rows, {String? id}) => DietPlan(
    dietPlanId: id ?? type.db,
    accountId: account,
    safetyLimitId: SafetyLimit.failSafeId,
    planType: type,
    startDate: day,
    endDate: type == PlanType.daily ? day : day.add(const Duration(days: 6)),
    modelVersion: 'manual',
    generatedAt: day,
    meals: rows,
  );
  DietPlanViewModel build({http.Client? client}) => DietPlanViewModel(
    DietPlannerService(
      ApiClient(
        baseUrl: 'http://ai',
        tokenProvider: () => 't',
        httpClient:
            client ?? MockClient((_) async => http.Response('{"error":{"code":"offline","message":"down"}}', 503)),
      ),
      foods,
    ),
    repo,
    foods,
    RiskAssessmentService(auth, FakeProfileRepository()),
    auth,
    () => now,
  );

  setUp(() async {
    auth = FakeAuthRepository();
    account = (await auth.login('demo@apths.test', 'password123')).dataOrNull!.accountId;
    repo = FakeMealRepository();
  });

  test('weekly generation keeps an adequate daily plan, including its empty snack and unlocked portions', () async {
    final daily = stored(PlanType.daily, adequateMeals(foods, day));
    await repo.savePlan(daily);
    var calls = 0;
    final vm = build(
      client: MockClient((req) async {
        calls++;
        final body = jsonDecode(req.body) as Map;
        final locked = body['locked'] as List;
        expect(locked, hasLength(3));
        expect(locked.first['food_key'], 'oats');
        expect(locked.first['portion_g'], 125);
        final days = [
          for (var i = 0; i < 7; i++) adequateDay(foods, day.add(Duration(days: i)), grams: i == 1 ? 250 : 125),
        ];
        (days.first['meals'] as List).add({
          'meal_slot': 'SNACK',
          'items': [
            {'food_key': 'epal', 'portion_g': 150},
          ],
        });
        return http.Response(jsonEncode({'model_version': 'diet-planner-2.3', 'days': days}), 200);
      }),
    );
    await vm.load(PlanType.weekly);
    expect(vm.plan!.mealsFor(day), hasLength(3));
    expect(vm.plan!.mealsFor(day).first.portionSizeG, 125);
    expect(vm.plan!.mealsFor(day).first.isLocked, isFalse);
    expect(vm.plan!.mealsFor(day).first.plannedMealId, isNot(daily.meals.first.plannedMealId));
    expect(vm.plan!.mealsFor(day).any((m) => m.mealSlot == MealSlot.snack), isFalse);
    expect(vm.plan!.mealsFor(tomorrow).first.portionSizeG, 250);
    expect(vm.previewRemove(vm.plan!.mealsFor(day).first), isNull);
    expect(vm.previewAdd(tomorrow, MealSlot.snack, food('epal')), isNotNull);
    await vm.regenerate();
    expect(calls, 2);
    expect(vm.plan!.mealsFor(day).first.portionSizeG, 125);
    expect(vm.regenerateEffects.first, contains("Today's meals stay"));
  });

  test('reopening the week reflects daily edits and removals while keeping the other days and row ids', () async {
    final future = PlannedMeal.of(food('epal'), tomorrow, MealSlot.snack, 150);
    await repo.savePlan(
      stored(PlanType.weekly, [PlannedMeal.of(food('nasi_putih'), day, MealSlot.lunch, 160), future]),
    );
    final daily = stored(PlanType.daily, [PlannedMeal.of(food('oats'), day, MealSlot.breakfast, 125, locked: true)]);
    await repo.savePlan(daily);
    final vm = build();
    await vm.load(PlanType.weekly);
    expect(vm.plan!.mealsFor(day).single.food.foodKey, 'oats');
    expect(vm.plan!.mealsFor(day).single.isLocked, isTrue);
    final copiedId = vm.plan!.mealsFor(day).single.plannedMealId;
    await vm.load(PlanType.weekly);
    expect(vm.plan!.mealsFor(day).single.plannedMealId, copiedId);
    expect(vm.plan!.mealsFor(tomorrow).single.plannedMealId, future.plannedMealId);
    await repo.updatePlan(daily.copyWith(meals: []));
    await vm.load(PlanType.weekly);
    expect(vm.plan!.mealsFor(day), isEmpty);
    expect(vm.plan!.mealsFor(tomorrow).single.food.foodKey, 'epal');
    expect((await repo.planFor(account, PlanType.weekly, day)).dataOrNull!.mealsFor(day), isEmpty);
  });

  test('a daily plan is taken from an existing week without asking the AI server again', () async {
    final weekly = stored(PlanType.weekly, [PlannedMeal.of(food('oats'), day, MealSlot.breakfast, 125)]);
    await repo.savePlan(weekly);
    final vm = build(client: MockClient((_) async => throw StateError('The daily plan must reuse the week')));
    await vm.load(PlanType.daily);
    expect(vm.plan!.planType, PlanType.daily);
    expect(vm.plan!.endDate, day);
    expect(vm.plan!.meals.single.portionSizeG, 125);
    expect(vm.plan!.meals.single.plannedMealId, isNot(weekly.meals.single.plannedMealId));
  });

  test('a manual draft keeps existing portions, and a failed save keeps the saved plan and draft', () async {
    final failing = _FailPlanSave();
    repo = failing;
    final original = stored(PlanType.daily, [PlannedMeal.of(food('oats'), day, MealSlot.breakfast, 125)]);
    await repo.savePlan(original);
    final vm = build();
    await vm.load(PlanType.daily);
    final draft = (await vm.manualMeals()).dataOrNull!;
    expect(draft.single.portionSizeG, 125);
    draft.add(PlannedMeal.of(food('epal'), day, MealSlot.snack, 150));
    failing.refuse = true;
    expect(await vm.saveManualMeals(draft), isNotEmpty);
    expect(vm.plan!.meals, hasLength(1));
    expect(draft, hasLength(2));
    expect(repo.plans, hasLength(1));
    failing.refuse = false;
    expect(await vm.saveManualMeals(draft), isEmpty);
    expect(vm.plan!.meals, hasLength(2));
    expect(vm.plan!.meals.first.portionSizeG, 125);
  });

  test('a manual draft warns about meals logged outside its slots but still rejects an empty day', () async {
    final vm = build();
    await vm.load(PlanType.daily);
    vm.logged = [
      MealLog(
        mealId: 'logged',
        accountId: account,
        mealType: MealSlot.lunch,
        entryMethod: EntryMethod.manual,
        consumedAt: now,
        items: [MealItem.of(food('nasi_putih'), grams: 2000)],
      ),
    ];
    final row = PlannedMeal.of(food('oats'), day, MealSlot.breakfast, 125);
    expect(vm.manualProblems([row]), isEmpty);
    expect(vm.manualFoodProblems(row, [row]).join(' '), contains('too much energy'));
    expect(await vm.saveManualMeals([]), isNotEmpty);
    expect(repo.plans, isEmpty);
  });

  test('a failed plan lookup does not generate and overwrite the saved choices', () async {
    final failing = _FailPlanSave();
    repo = failing;
    final original = stored(PlanType.daily, [PlannedMeal.of(food('oats'), day, MealSlot.breakfast, 125)]);
    await repo.savePlan(original);
    failing.refuseRead = true;
    final vm = build(client: MockClient((_) async => throw StateError('Do not generate after a failed lookup')));
    await vm.load(PlanType.daily);
    expect(vm.plan, isNull);
    expect(vm.takeMessage(), isNotNull);
    expect(repo.plans.single, same(original));
  });

  test('a new week refuses to copy a warned or underfilled daily choice and keeps saved plans', () async {
    final saved = stored(PlanType.daily, [PlannedMeal.of(food('nasi_lemak'), day, MealSlot.breakfast, 250)]);
    await repo.savePlan(saved);
    final vm = build(client: MockClient((_) async => throw StateError('Replan Today before making a week')));
    await vm.load(PlanType.weekly);
    expect(vm.plan, isNull);
    expect(repo.plans.single, same(saved));
    expect(vm.takeMessage(), contains("Replan Today's Plan first"));
    expect(vm.needsDailyReplan, isTrue);
  });
}
