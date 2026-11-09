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
import 'package:physical_treatment_and_health_support_system/model/entity/meal_log.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/lookups.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/safety_limit.dart';
import 'package:physical_treatment_and_health_support_system/model/repository/auth_repository/fake_auth_repository.dart';
import 'package:physical_treatment_and_health_support_system/model/repository/food_repository/fake_food_repository.dart';
import 'package:physical_treatment_and_health_support_system/model/repository/meal_repository/fake_meal_repository.dart';
import 'package:physical_treatment_and_health_support_system/model/repository/profile_repository/fake_profile_repository.dart';
import 'package:physical_treatment_and_health_support_system/model/result.dart';
import 'package:physical_treatment_and_health_support_system/shared_client/api_client/api_client.dart';
import 'package:physical_treatment_and_health_support_system/viewmodel/diet_plan_view_model/diet_plan_view_model.dart';
import 'support/diet_plan_fixtures.dart';

class _DelayedMeals extends FakeMealRepository {
  Completer<void>? resume;
  final started = Completer<void>();
  bool fail = false;
  @override
  Future<Result<void>> updatePlan(DietPlan p) async {
    final pending = resume;
    if (pending != null) {
      resume = null;
      started.complete();
      await pending.future;
      if (fail) return const Failure('offline');
    }
    return super.updatePlan(p);
  }
}

void main() {
  final foods = FakeFoodRepository.fromJson(File('assets/seed/food_catalogue.json').readAsStringSync());
  final now = DateTime.now();
  final day = DateTime(now.year, now.month, now.day);
  FoodItem food(String key) => foods.foods.firstWhere((f) => f.foodKey == key);
  final ctx = DietContext(limit: SafetyLimit.mostRestrictive());
  http.Response response(String key, num grams) => http.Response(
    jsonEncode({
      'model_version': 'diet-planner-2.3',
      'days': [adequateDay(foods, day, key: key, grams: grams.toDouble())],
    }),
    200,
  );
  DietPlannerService planner(http.Client client) =>
      DietPlannerService(ApiClient(baseUrl: 'http://ai', tokenProvider: () => 't', httpClient: client), foods);
  Future<DietPlanViewModel> vmFor(DietPlannerService service, FakeMealRepository repo) async {
    final auth = FakeAuthRepository();
    await auth.login('demo@apths.test', 'password123');
    return DietPlanViewModel(service, repo, foods, RiskAssessmentService(auth, FakeProfileRepository()), auth);
  }

  test('an unsafe server food is rejected despite its Suitable label and only the regenerated plan is saved', () async {
    var calls = 0;
    final repo = FakeMealRepository();
    final service = planner(
      MockClient((request) async {
        final body = jsonDecode(request.body) as Map;
        calls++;
        if (calls == 1) return response('nasi_lemak', 250);
        expect(body['exclude'], contains('nasi_lemak'));
        expect(body['seed'], 101);
        return response('oats', 125);
      }),
    );
    final vm = await vmFor(service, repo);
    await vm.load(PlanType.daily);
    expect(calls, 2);
    expect(repo.plans.single.meals.first.food.foodKey, 'oats');
    expect(vm.plan!.meals.first.food.foodKey, 'oats');
  });

  test('three unsafe replies stop with an explanation and never save a plan', () async {
    var calls = 0;
    final repo = FakeMealRepository();
    final vm = await vmFor(
      planner(
        MockClient((_) async {
          calls++;
          return response('nasi_lemak', 250);
        }),
      ),
      repo,
    );
    await vm.load(PlanType.daily);
    expect(calls, 3);
    expect(repo.plans, isEmpty);
    expect(vm.plan, isNull);
    expect(vm.takeMessage(), contains('3 attempts'));
  });

  test('an underfilled Suitable reply is retried without excluding its safe food', () async {
    var calls = 0;
    final repo = FakeMealRepository();
    final vm = await vmFor(
      planner(
        MockClient((request) async {
          calls++;
          if (calls == 1) {
            final body = jsonDecode(response('oats', 125).body) as Map;
            final dayData = (body['days'] as List).single as Map;
            dayData['meals'] = [(dayData['meals'] as List).first];
            return http.Response(jsonEncode(body), 200);
          }
          expect((jsonDecode(request.body) as Map)['exclude'], isNot(contains('oats')));
          return response('oats', 125);
        }),
      ),
      repo,
    );
    await vm.load(PlanType.daily);
    expect(calls, 2);
    expect(repo.plans, hasLength(1));
    expect(vm.nutritionWarnings(day), isEmpty);
  });

  test('three underfilled replans keep the previous saved foods and do not report the server offline', () async {
    var calls = 0;
    final repo = FakeMealRepository();
    final vm = await vmFor(
      planner(
        MockClient((_) async {
          calls++;
          final result = response('oats', 125);
          if (calls == 1) return result;
          final body = jsonDecode(result.body) as Map;
          final d = (body['days'] as List).single as Map;
          d['meals'] = [(d['meals'] as List).first];
          return http.Response(jsonEncode(body), 200);
        }),
      ),
      repo,
    );
    await vm.load(PlanType.daily);
    final previous = vm.plan!;
    await vm.regenerate();
    expect(calls, 4);
    expect(repo.plans, hasLength(1));
    expect(vm.plan!.dietPlanId, previous.dietPlanId);
    expect(vm.plan!.meals.map((m) => m.plannedMealId), previous.meals.map((m) => m.plannedMealId));
    expect(vm.plannerDown, isFalse);
    expect(vm.takeMessage(), contains('No new plan was saved'));
  });

  test('a weekly reply with missing days cannot be saved as an adequate week', () async {
    var calls = 0;
    final result = await planner(
      MockClient((_) async {
        calls++;
        return response('oats', 125);
      }),
    ).generate(accountId: 'a', ctx: ctx, type: PlanType.weekly, start: day);
    expect(result, isA<Failure<DietPlan>>());
    expect(calls, 3);
  });

  test('a calorie-complete reply missing the profile fibre target is rejected', () async {
    final diabetic = DietContext(
      limit: ctx.limit,
      conditions: [LookupSeed.conditions.firstWhere((c) => c.conditionCode == 'DIABETES')],
    );
    var calls = 0;
    final result = await planner(
      MockClient((_) async {
        calls++;
        return response('oats', 125);
      }),
    ).generate(accountId: 'a', ctx: diabetic, type: PlanType.daily, start: day);
    expect(result, isA<Failure<DietPlan>>());
    expect(calls, 3);
  });

  test('an otherwise suitable reply over the calorie ceiling is rejected', () async {
    var calls = 0;
    final result = await planner(
      MockClient((_) async {
        calls++;
        return http.Response(
          jsonEncode({
            'model_version': 'diet-planner-2.3',
            'days': [
              {
                'plan_date': day.toIso8601String().substring(0, 10),
                'meals': [
                  {
                    'meal_slot': 'LUNCH',
                    'items': [
                      {'food_key': 'nasi_putih', 'portion_g': 1500, 'verdict': 'SUITABLE'},
                    ],
                  },
                ],
              },
            ],
          }),
          200,
        );
      }),
    ).generate(accountId: 'a', ctx: ctx, type: PlanType.daily, start: day);
    expect(result, isA<Failure<DietPlan>>());
    expect(calls, 3);
  });

  test('the request sends consumed protein, fat, carbohydrate and condition nutrients', () async {
    final eaten = MealLog(
      mealId: 'eaten',
      accountId: 'a',
      mealType: MealSlot.breakfast,
      entryMethod: EntryMethod.manual,
      consumedAt: now,
      items: [MealItem.of(food('oats'), grams: 125)],
    );
    Map? sent;
    await planner(
      MockClient((request) async {
        sent = jsonDecode(request.body) as Map;
        return http.Response('{"error":{"code":"offline","message":"down"}}', 503);
      }),
    ).generate(
      accountId: 'a',
      ctx: ctx,
      type: PlanType.daily,
      start: day,
      consumedToday: eaten.totals,
      history: [eaten],
      loggedSlots: {MealSlot.breakfast},
    );
    final nutrients = sent!['consumed_today'] as Map;
    expect(nutrients['protein_g'], eaten.totals.proteinG);
    expect(nutrients['carb_g'], eaten.totals.carbG);
    expect(nutrients['fat_g'], eaten.totals.fatG);
    expect(nutrients['fibre_g'], food('oats').extrasFor(125).fibreG);
    expect(nutrients['calcium_mg'], food('oats').extrasFor(125).calciumMg);
  });

  test('logged slots count actual food once and even a small upper-limit excess blocks generation', () {
    final service = planner(MockClient((_) async => response('oats', 125)));
    final row = PlannedMeal.of(
      food('oats'),
      day,
      MealSlot.breakfast,
      ctx.dailyEnergyKcal * .85 / food('oats').energyKcalPer100g * 100,
    );
    final p = DietPlan(
      dietPlanId: 'p',
      accountId: 'a',
      safetyLimitId: 'sl',
      planType: PlanType.daily,
      startDate: day,
      endDate: day,
      modelVersion: 'test',
      generatedAt: now,
      meals: [row],
    );
    expect(
      service.generationProblems(p, ctx, consumedToday: row.nutrients, loggedSlots: {MealSlot.breakfast}),
      isEmpty,
    );
    expect(service.generationProblems(p, ctx, consumedToday: row.nutrients), isNotEmpty);
    expect(
      service.generationProblems(
        p.copyWith(meals: []),
        ctx,
        consumedToday: Nutrients(energyKcal: ctx.dailyEnergyKcal + .1),
      ),
      isNotEmpty,
    );
  });

  test('a saved plan with profile conflicts stays visible with red warning reasons after reload', () async {
    var calls = 0;
    final repo = FakeMealRepository();
    final vm = await vmFor(
      planner(
        MockClient((_) async {
          calls++;
          return response('oats', 125);
        }),
      ),
      repo,
    );
    await vm.load(PlanType.daily);
    await repo.updatePlan(vm.plan!.copyWith(meals: [PlannedMeal.of(food('nasi_lemak'), day, MealSlot.breakfast, 250)]));
    await vm.load(PlanType.daily);
    expect(vm.plan!.meals.single.food.foodKey, 'nasi_lemak');
    expect(vm.savedFoodWarnings(vm.plan!.meals.single), isNotEmpty);
    expect(vm.takeMessage(), contains('highlighted in red'));
    expect(calls, 1); // user chooses whether to correct or regenerate
    expect((await vm.manualMeals()).dataOrNull!.single.food.foodKey, 'nasi_lemak');
  });

  test('unknown foods and invalid portions reject the entire reply instead of silently dropping an item', () async {
    for (final bad in [('missing_food', 100), ('oats', -10), ('oats', 0)]) {
      var calls = 0;
      final result = await planner(
        MockClient((_) async {
          calls++;
          return response(bad.$1, bad.$2);
        }),
      ).generate(accountId: 'a', ctx: ctx, type: PlanType.daily, start: day);
      expect(result, isA<Failure<DietPlan>>());
      expect(calls, 3);
    }
  });

  test('a locked slot does not hide an unsuitable food supplied by the server', () async {
    var calls = 0;
    final service = planner(
      MockClient((_) async {
        calls++;
        return response(calls == 1 ? 'nasi_lemak' : 'oats', calls == 1 ? 250 : 125);
      }),
    );
    final result = await service.generate(
      accountId: 'a',
      ctx: ctx,
      type: PlanType.daily,
      start: day,
      locked: [PlannedMeal.of(food('oats'), day, MealSlot.breakfast, 125, locked: true)],
    );
    expect(calls, 2);
    expect(result.isSuccess, isTrue);
    expect(result.dataOrNull!.meals.first.food.foodKey, 'oats');
  });

  test('Caution foods are rejected even when locked or marked logged', () {
    final hypertension = DietContext(
      limit: SafetyLimit.mostRestrictive(),
      conditions: [LookupSeed.conditions.firstWhere((c) => c.conditionCode == 'HYPERTENSION')],
    );
    final f = food('nasi_lemak');
    final portion = 510 / f.sodiumMgPer100g * 100;
    const rules = SuitabilityService();
    expect(
      rules.mostRestrictive(
        rules.assess(
          // This portion is Caution at 85% of the condition's per-item sodium limit.
          MealItem.of(f, grams: portion),
          hypertension,
        ),
      ),
      Verdict.caution,
    );
    final service = planner(MockClient((_) async => response('oats', 125)));
    for (final flags in [(false, false), (true, false), (false, true)]) {
      final p = DietPlan(
        dietPlanId: 'p',
        accountId: 'a',
        safetyLimitId: 'sl',
        planType: PlanType.daily,
        startDate: day,
        endDate: day,
        modelVersion: 'manual',
        generatedAt: now,
        meals: [PlannedMeal.of(f, day, MealSlot.breakfast, portion, locked: flags.$1).copyWith(isLogged: flags.$2)],
      );
      expect(service.validate(p, hypertension), isNotEmpty);
    }
  });

  test('manual save allows a conflicting food and daily excess still identifies each contributing row', () async {
    final repo = FakeMealRepository();
    final vm = await vmFor(planner(MockClient((_) async => response('oats', 125))), repo);
    await vm.load(PlanType.daily);
    final bad = PlannedMeal.of(food('nasi_lemak'), day, MealSlot.breakfast, 250);
    expect(vm.manualFoodProblems(bad, [bad]), isNotEmpty);
    expect(await vm.saveManualMeals([bad]), isEmpty);
    expect(repo.plans, hasLength(2));
    expect(vm.savedFoodWarnings(vm.plan!.meals.single), isNotEmpty);
    final grams = vm.ctx.dailyEnergyKcal / food('oats').energyKcalPer100g * 100 / 2;
    final rows = [
      for (final slot in [MealSlot.breakfast, MealSlot.lunch, MealSlot.dinner])
        PlannedMeal.of(food('oats'), day, slot, grams),
    ];
    expect(vm.manualProblems(rows), isEmpty);
    for (final row in rows) {
      expect(vm.manualFoodProblems(row, rows).join(' '), contains('too much energy'));
    }
  });

  test('manual picks merge within a date and slot, including changing a food into an existing choice', () async {
    final vm = await vmFor(planner(MockClient((_) async => response('oats', 125))), FakeMealRepository());
    await vm.load(PlanType.daily);
    final first = PlannedMeal.of(food('betik'), day, MealSlot.snack, 100, locked: true);
    final other = PlannedMeal.of(food('oats'), day, MealSlot.snack, 125);
    final nextDay = PlannedMeal.of(food('betik'), day.add(const Duration(days: 1)), MealSlot.snack, 100);
    final lunch = PlannedMeal.of(food('betik'), day, MealSlot.lunch, 100);
    final merged = vm.mergeManualChoice(
      [first, other, nextDay, lunch],
      PlannedMeal.of(food('betik'), day, MealSlot.snack, 150),
      replacing: other,
    );
    expect(merged, hasLength(3));
    expect(merged.first.plannedMealId, first.plannedMealId);
    expect(merged.first.portionSizeG, 250);
    expect(merged.first.energyKcal, food('betik').nutrientsFor(250).energyKcal);
    expect(merged.first.isLocked, isTrue);
    expect(merged[1].portionSizeG, 100);
    expect(merged[2].mealSlot, MealSlot.lunch);
    expect(await vm.saveManualMeals([merged.first]), isEmpty);
    expect(vm.plan!.meals.single.portionSizeG, 250);
  });

  test('manual search includes restricted foods and malformed portions still cannot be saved', () async {
    final vm = await vmFor(planner(MockClient((_) async => response('oats', 125))), FakeMealRepository());
    await vm.load(PlanType.daily);
    vm.ctx = DietContext(
      limit: vm.ctx.limit,
      restrictions: [LookupSeed.restrictions.firstWhere((r) => r.restrictionCode == 'PEANUT')],
    );
    expect((await vm.searchCatalogue('nasi lemak')).map((f) => f.foodKey), contains('nasi_lemak'));
    final restricted = PlannedMeal.of(food('nasi_lemak'), day, MealSlot.snack, 50);
    expect(vm.manualFoodProblems(restricted, [restricted]), isNotEmpty);
    expect(vm.manualProblems([restricted]), isEmpty);
    for (final grams in [double.nan, double.infinity, 0.0, -10.0]) {
      final bad = PlannedMeal.of(food('oats'), day, MealSlot.breakfast, grams);
      expect(vm.manualProblems([bad]), isNotEmpty);
      expect(vm.previewPortion(vm.plan!.meals.first, 0)!.allowed, isFalse);
    }
  });

  test('weekly edits can exceed limits and red reasons survive reopening the week', () async {
    final repo = FakeMealRepository();
    final vm = await vmFor(planner(MockClient((_) async => response('oats', 125))), repo);
    await vm.load(PlanType.daily);
    final tomorrow = day.add(const Duration(days: 1));
    await repo.savePlan(
      DietPlan(
        dietPlanId: 'week',
        accountId: vm.plan!.accountId,
        safetyLimitId: vm.plan!.safetyLimitId,
        planType: PlanType.weekly,
        startDate: day,
        endDate: day.add(const Duration(days: 6)),
        modelVersion: 'manual',
        generatedAt: now,
        meals: [PlannedMeal.of(food('oats'), tomorrow, MealSlot.breakfast, 125)],
      ),
    );
    await vm.load(PlanType.weekly);
    final change = vm.previewAdd(tomorrow, MealSlot.lunch, food('ikan_masin'), grams: 300)!;
    expect(change.allowed, isTrue);
    expect(change.warnings, isNotEmpty);
    expect(await vm.applyChange(change), isTrue);
    await vm.load(PlanType.weekly);
    final salty = vm.plan!.meals.firstWhere((m) => m.food.foodKey == 'ikan_masin');
    expect(vm.savedFoodWarnings(salty).join(' '), contains('too much sodium'));
    final remove = vm.previewRemove(salty)!;
    expect(await vm.applyChange(remove), isTrue);
    expect(vm.plan!.meals.any((m) => m.food.foodKey == 'ikan_masin'), isFalse);
  });

  test('split duplicate portions merge before warnings, while the AI gate remains strict', () async {
    final service = planner(MockClient((_) async => response('oats', 125)));
    final vm = await vmFor(service, FakeMealRepository());
    await vm.load(PlanType.daily);
    final f = food('nasi_lemak');
    final grams = vm.ctx.dailySodiumMg * 0.20 / f.sodiumMgPer100g * 100;
    final rows = [for (var i = 0; i < 2; i++) PlannedMeal.of(f, day, MealSlot.breakfast, grams)];
    expect(vm.foodProblemsForPlan(rows.first), isEmpty);
    expect(vm.manualProblems(rows), isEmpty);
    expect(await vm.saveManualMeals(rows), isEmpty);
    expect(vm.plan!.meals, hasLength(1));
    expect(vm.savedFoodWarnings(vm.plan!.meals.single), isNotEmpty);
    expect(service.validate(vm.plan!, vm.ctx), isNotEmpty);
  });

  for (final action in ['add', 'remove', 'replace', 'portion']) {
    test('$action shows progress and refuses repeat taps until persistence finishes', () async {
      final repo = _DelayedMeals();
      final vm = await vmFor(planner(MockClient((_) async => response('oats', 125))), repo);
      await vm.load(PlanType.daily);
      final row = vm.plan!.meals.first;
      final change = switch (action) {
        'add' => vm.previewAdd(day, MealSlot.breakfast, food('oats'), grams: 125)!,
        'remove' => vm.previewRemove(row)!,
        'replace' => vm.previewReplace(row, food('betik'))!,
        _ => vm.previewPortion(row, 100)!,
      };
      expect(change.allowed, isTrue, reason: change.problems.join(', '));
      final release = Completer<void>();
      repo.resume = release;
      final pending = vm.applyChange(change);
      expect(vm.isLoading, isTrue);
      expect(vm.changeInProgress, isNotNull);
      await repo.started.future;
      expect(await vm.applyChange(change), isFalse);
      release.complete();
      expect(await pending, isTrue);
      expect(vm.isLoading, isFalse);
      expect(vm.changeInProgress, isNull);
      if (action == 'add') {
        expect(repo.plans.single.meals, hasLength(3));
        expect(repo.plans.single.meals.first.portionSizeG, 250);
      }
    });
  }

  test('a delayed failed save rolls back the food change and clears the loading state', () async {
    final repo = _DelayedMeals();
    final vm = await vmFor(planner(MockClient((_) async => response('oats', 125))), repo);
    await vm.load(PlanType.daily);
    final original = vm.plan!;
    final release = Completer<void>();
    repo.resume = release;
    repo.fail = true;
    final pending = vm.applyChange(vm.previewRemove(original.meals.first)!);
    await repo.started.future;
    expect(vm.plan!.meals, hasLength(2));
    release.complete();
    expect(await pending, isFalse);
    expect(vm.plan, same(original));
    expect(vm.isLoading, isFalse);
    expect(vm.changeInProgress, isNull);
    expect(vm.takeMessage(), isNotNull);
  });
}
