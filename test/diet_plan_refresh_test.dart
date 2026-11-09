import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:physical_treatment_and_health_support_system/model/business_logic/diet_planner_service/diet_planner_service.dart';
import 'package:physical_treatment_and_health_support_system/model/business_logic/risk_assessment_service/risk_assessment_service.dart';
import 'package:physical_treatment_and_health_support_system/model/business_logic/suitability_service/suitability_service.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/diet_plan.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/enums.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/food_item.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/health_profile.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/lookups.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/meal_log.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/safety_limit.dart';
import 'package:physical_treatment_and_health_support_system/model/repository/auth_repository/fake_auth_repository.dart';
import 'package:physical_treatment_and_health_support_system/model/repository/food_repository/fake_food_repository.dart';
import 'package:physical_treatment_and_health_support_system/model/repository/meal_repository/fake_meal_repository.dart';
import 'package:physical_treatment_and_health_support_system/model/repository/profile_repository/fake_profile_repository.dart';
import 'package:physical_treatment_and_health_support_system/model/result.dart';
import 'package:physical_treatment_and_health_support_system/shared_client/api_client/api_client.dart';
import 'package:physical_treatment_and_health_support_system/viewmodel/diet_plan_view_model/diet_plan_view_model.dart';

class _ReadFailure extends FakeMealRepository {
  @override
  Future<Result<DietPlan?>> planFor(String accountId, PlanType type, DateTime day) async => const Failure('offline');
}

void main() {
  final foods = FakeFoodRepository.fromJson(File('assets/seed/food_catalogue.json').readAsStringSync());
  final food = foods.foods.firstWhere((f) => f.foodKey == 'oats');
  final now = DateTime.now();
  final day = DateTime(now.year, now.month, now.day);
  late FakeAuthRepository auth;
  late FakeProfileRepository profiles;
  late FakeMealRepository repo;
  late String account;

  DietPlan stored(PlanType type) => DietPlan(
    dietPlanId: type.db,
    accountId: account,
    safetyLimitId: 'sl',
    planType: type,
    startDate: day,
    endDate: type == PlanType.daily ? day : day.add(const Duration(days: 6)),
    modelVersion: 'manual',
    generatedAt: day,
    meals: [PlannedMeal.of(food, day, MealSlot.breakfast, 125)],
  );
  DietPlannerService planner(http.Client client) =>
      DietPlannerService(ApiClient(baseUrl: 'http://ai', tokenProvider: () => 't', httpClient: client), foods);
  DietPlanViewModel build(http.Client client) =>
      DietPlanViewModel(planner(client), repo, foods, RiskAssessmentService(auth, profiles), auth, () => now);
  http.Response suitable(http.Request request) {
    final body = jsonDecode(request.body) as Map;
    expect(body['profile']['weight_kg'], 75);
    final days = body['plan_type'] == 'WEEKLY' ? 7 : 1;
    return http.Response(
      jsonEncode({
        'model_version': 'diet-planner-2.2',
        'days': [
          for (var i = 0; i < days; i++)
            {
              'plan_date': day.add(Duration(days: i)).toIso8601String().substring(0, 10),
              'meals': [
                {
                  'meal_slot': 'BREAKFAST',
                  'items': [
                    {'food_key': 'oats', 'portion_g': 125},
                  ],
                },
              ],
            },
        ],
      }),
      200,
    );
  }

  setUp(() async {
    auth = FakeAuthRepository();
    account = (await auth.login('demo@apths.test', 'password123')).dataOrNull!.accountId;
    profiles = FakeProfileRepository();
    repo = FakeMealRepository();
    final p = HealthProfile(
      profileId: 'p',
      accountId: account,
      age: 60,
      gender: Gender.female,
      heightCm: 160,
      weightKg: 75,
      updatedAt: now,
    );
    await profiles.saveProfile(p, p.generateSafetyLimit());
  });

  test('energy alert appears below 75 percent and clears at the threshold', () {
    final service = planner(MockClient((_) async => http.Response('{}', 503)));
    final ctx = DietContext(limit: SafetyLimit.mostRestrictive());
    final empty = stored(PlanType.daily).copyWith(meals: []);
    expect(service.nutritionWarnings(empty, day, ctx).map((w) => w.text).join(' '), contains('Too little energy'));
    final enough = Nutrients(energyKcal: ctx.dailyEnergyKcal * 0.75);
    expect(
      service.nutritionWarnings(empty, day, ctx, eatenOutside: enough).any((w) => w.text.contains('Too little energy')),
      isFalse,
    );
  });

  test('profile nutrient needs warn with actual amounts and account for food already eaten', () {
    final service = planner(MockClient((_) async => http.Response('{}', 503)));
    final ctx = DietContext(
      limit: SafetyLimit.mostRestrictive(),
      age: 70,
      weightKg: 60,
      conditions: LookupSeed.conditions.where((c) => ['OSTEOPOROSIS', 'DIABETES'].contains(c.conditionCode)).toList(),
    );
    final empty = stored(PlanType.daily).copyWith(meals: []);
    final warnings = service.nutritionWarnings(empty, day, ctx).map((w) => w.text).join(' ');
    expect(warnings, contains('Too little protein'));
    expect(warnings, contains('Too little calcium'));
    expect(warnings, contains('Too little fibre'));
    expect(
      service.nutritionWarnings(
        empty,
        day,
        ctx,
        eatenOutside: Nutrients(energyKcal: ctx.dailyEnergyKcal, proteinG: 100),
        outsideExtras: const FoodExtras(calciumMg: 2000, fibreG: 100),
      ),
      isEmpty,
    );
  });

  test('today shortfall counts logged food outside planned slots without changing future-day alerts', () async {
    await repo.savePlan(stored(PlanType.weekly));
    final vm = build(MockClient((_) async => throw StateError('Stored plan must not generate')));
    await vm.load(PlanType.weekly);
    vm.logged = [
      MealLog(
        mealId: 'eaten',
        accountId: account,
        mealType: MealSlot.dinner,
        entryMethod: EntryMethod.manual,
        consumedAt: day.add(const Duration(hours: 8)),
        items: [MealItem.of(food, grams: 3000)],
      ),
    ];
    expect(vm.nutritionWarnings(day).any((w) => w.text.contains('Too little energy')), isFalse);
    expect(
      vm.nutritionWarnings(day.add(const Duration(days: 1))).any((w) => w.text.contains('Too little energy')),
      isTrue,
    );
  });

  test('confirmed profile refresh regenerates daily then existing week using the new profile', () async {
    await repo.savePlan(stored(PlanType.daily));
    await repo.savePlan(stored(PlanType.weekly));
    final types = <String>[];
    final vm = build(
      MockClient((req) async {
        types.add((jsonDecode(req.body) as Map)['plan_type'] as String);
        return suitable(req);
      }),
    );
    await vm.refreshAfterProfileChange();
    expect(types, ['DAILY', 'WEEKLY']);
    expect(repo.plans.where((p) => p.planType == PlanType.daily), hasLength(2));
    expect(repo.plans.where((p) => p.planType == PlanType.weekly), hasLength(2));
    expect(vm.type, PlanType.daily);
    expect(vm.ctx.weightKg, 75);
    expect(vm.isLoading, isFalse);
    expect(vm.changeInProgress, isNull);
    expect(vm.takeMessage(), contains('daily and weekly plans'));
  });

  test('with no saved week only a daily plan is generated', () async {
    var calls = 0;
    final vm = build(
      MockClient((req) async {
        calls++;
        return suitable(req);
      }),
    );
    await vm.refreshAfterProfileChange();
    expect(calls, 1);
    expect(repo.plans.single.planType, PlanType.daily);
  });

  test('a pending profile refresh shows progress and ignores a second update request', () async {
    final started = Completer<void>();
    final response = Completer<http.Response>();
    var calls = 0;
    late http.Request request;
    final vm = build(
      MockClient((req) async {
        calls++;
        request = req;
        started.complete();
        return response.future;
      }),
    );
    final pending = vm.refreshAfterProfileChange();
    expect(vm.isLoading, isTrue);
    await started.future;
    expect(vm.changeInProgress, contains("Updating today's plan"));
    await vm.refreshAfterProfileChange();
    expect(calls, 1);
    response.complete(suitable(request));
    await pending;
    expect(vm.isLoading, isFalse);
    expect(vm.changeInProgress, isNull);
  });

  test('failed profile refresh retains both stored plans and clears busy state', () async {
    final daily = stored(PlanType.daily), weekly = stored(PlanType.weekly);
    await repo.savePlan(daily);
    await repo.savePlan(weekly);
    final vm = build(MockClient((_) async => http.Response('{"error":{"code":"offline","message":"down"}}', 503)));
    await vm.refreshAfterProfileChange();
    expect(repo.plans.map((p) => p.dietPlanId), [daily.dietPlanId, weekly.dietPlanId]);
    expect(repo.plans.first.meals.single.plannedMealId, daily.meals.single.plannedMealId);
    expect(vm.plan!.dietPlanId, daily.dietPlanId);
    expect(vm.isLoading, isFalse);
    expect(vm.changeInProgress, isNull);
  });

  test('weekly refresh failure reports partial success and retains the old stored week', () async {
    final weekly = stored(PlanType.weekly);
    await repo.savePlan(stored(PlanType.daily));
    await repo.savePlan(weekly);
    final vm = build(
      MockClient(
        (req) async => (jsonDecode(req.body) as Map)['plan_type'] == 'DAILY'
            ? suitable(req)
            : http.Response('{"error":{"code":"offline","message":"down"}}', 503),
      ),
    );
    await vm.refreshAfterProfileChange();
    final kept = repo.plans.where((p) => p.planType == PlanType.weekly).single;
    expect(kept.dietPlanId, weekly.dietPlanId);
    expect(kept.meals.single.plannedMealId, weekly.meals.single.plannedMealId);
    expect(repo.plans.where((p) => p.planType == PlanType.daily), hasLength(2));
    expect(vm.takeMessage(), contains('weekly plan could not be updated'));
    expect(vm.isLoading, isFalse);
  });

  test('a failed saved-plan lookup does not generate or overwrite plans', () async {
    repo = _ReadFailure();
    final vm = build(MockClient((_) async => throw StateError('Must not generate after read failure')));
    await vm.refreshAfterProfileChange();
    expect(repo.plans, isEmpty);
    expect(vm.takeMessage(), isNotNull);
    expect(vm.isLoading, isFalse);
  });
}
