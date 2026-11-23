// Explicit private-data validation, outside the normal test/ suite.
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:physical_treatment_and_health_support_system/model/business_logic/diet_insights_service/plan_comparison_service.dart';
import 'package:physical_treatment_and_health_support_system/model/business_logic/diet_planner_service/diet_planner_service.dart';
import 'package:physical_treatment_and_health_support_system/model/business_logic/suitability_service/suitability_service.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/biometric_reading.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/diet_plan.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/food_item.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/enums.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/health_profile.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/lookups.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/meal_log.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/plan_comparison.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/safety_limit.dart';
import 'package:physical_treatment_and_health_support_system/model/repository/food_repository/fake_food_repository.dart';
import 'package:physical_treatment_and_health_support_system/shared_client/api_client/api_client.dart';

void main() {
  final directory = const String.fromEnvironment(
    'PRESENTATION_DATA',
    defaultValue: 'build/presentation-demo-2026-11-24',
  );
  final data =
      jsonDecode(File('$directory/dataset.json').readAsStringSync())
          as Map<String, dynamic>;
  final source =
      jsonDecode(File('$directory/context.json').readAsStringSync())
          as Map<String, dynamic>;
  final rows = data['rows'] as Map<String, dynamic>;
  final context = source['context'] as Map<String, dynamic>;
  final food = <String, FoodItem>{};
  for (final raw in source['foods'] as List) {
    final f = Map<String, dynamic>.from(raw as Map);
    for (final key in f.keys.toList()) {
      if (key.endsWith('_per_100g') || key == 'base_serving_g') {
        f[key] = num.parse('${f[key]}');
      }
    }
    food[f['food_id'] as String] = FoodItem.fromJson(f);
  }
  final profile = HealthProfile.fromJson(
    Map<String, dynamic>.from(data['profile'] as Map),
    limitations: [
      for (final (i, code) in (context['limitations'] as List).indexed)
        PhysicalLimitation.fromJson({
          'limitation_id': i + 1,
          'limitation_code': code,
          'limitation_name': code,
          'category': 'Mobility',
        }),
    ],
  );
  final safety = SafetyLimit.fromJson(
    Map<String, dynamic>.from(data['safety_limit'] as Map),
  );
  final ctx = DietContext.from(
    ProfileSnapshot(
      profile: profile,
      safetyLimit: safety,
      status: ProfileStatus.complete,
    ),
  );
  final plans = [
    for (final raw in rows['diet_plan'] as List)
      DietPlan.fromJson(Map<String, dynamic>.from(raw as Map), [
        for (final p in rows['planned_meal'] as List)
          if (p['diet_plan_id'] == raw['diet_plan_id'])
            PlannedMeal.fromJson(
              Map<String, dynamic>.from(p as Map),
              food[p['food_id']]!,
            ),
      ]),
  ];
  final meals = [
    for (final raw in rows['meal_log'] as List)
      MealLog.fromJson(Map<String, dynamic>.from(raw as Map), [
        for (final i in rows['meal_item'] as List)
          if (i['meal_id'] == raw['meal_id'])
            MealItem.fromJson(
              Map<String, dynamic>.from(i as Map),
              food[i['food_id']]!,
            ),
      ]),
  ];

  test(
    'approved demo profile and every planned day pass the application nutrition gate',
    () {
      expect(profile.bmi, 20.1);
      expect(profile.generateSafetyLimit().dailyCalorieTarget, 2429);
      expect(ctx.oneHandOnly, isTrue);
      final planner = DietPlannerService(
        ApiClient(
          baseUrl: 'http://not-used.invalid',
          tokenProvider: () => null,
        ),
        FakeFoodRepository(food.values.toList()),
      );
      for (final p in plans) {
        expect(
          planner.generationProblems(p, ctx),
          isEmpty,
          reason: p.startDate.toString(),
        );
      }
    },
  );
  for (var i = 0; i < 3; i++) {
    test(
      'demo week ${i + 1} has the requested complete comparison pattern',
      () {
        final p = plans[i];
        final map = <DateTime, DietPlan>{
          for (var d = 0; d < 7; d++) p.startDate.add(Duration(days: d)): p,
        };
        final report = const PlanComparisonService().build(
          accountId: p.accountId,
          start: p.startDate,
          now: DateTime(2026, 11, 24, 23),
          meals: meals,
          plans: map,
        );
        expect(report.compared, hasLength(28));
        expect(report.count(MealComparisonStatus.close), [28, 0, 14][i]);
        expect(report.count(MealComparisonStatus.foods), [0, 28, 14][i]);
        expect(report.count(MealComparisonStatus.portions), 0);
        expect(report.count(MealComparisonStatus.noLog), 0);
        expect(report.count(MealComparisonStatus.reference), 0);
        for (final m in meals.where((m) => m.plannedMealId != null)) {
          final linked = (rows['planned_meal'] as List).singleWhere(
            (p) => p['planned_meal_id'] == m.plannedMealId,
          );
          expect(linked['meal_slot'], m.mealType.db);
        }
      },
    );
  }
  test(
    'stored meal totals, original timestamps and treatment progression are internally consistent',
    () {
      for (final m in meals) {
        final row = (rows['meal_log'] as List).singleWhere(
          (r) => r['meal_id'] == m.mealId,
        );
        expect(
          m.totals.energyKcal,
          closeTo((row['total_energy_kcal'] as num).toDouble(), .11),
        );
        expect(
          m.totals.sodiumMg,
          closeTo((row['total_sodium_mg'] as num).toDouble(), .11),
        );
      }
      final readings = [
        for (final r in rows['biometric_reading'] as List)
          BiometricReading.fromJson(Map<String, dynamic>.from(r as Map)),
      ];
      expect(
        readings.map((r) => r.duplicateKey()).toSet(),
        hasLength(readings.length),
      );
      expect(
        readings.every(
          (r) =>
              r.isPlausible() &&
              r.isValidBloodPressure() &&
              !r.isFutureDated(DateTime(2026, 11, 24, 23)),
        ),
        isTrue,
      );
      expect(
        (rows['patient_plan'] as List)
            .where((p) => p['status'] == 'ACTIVE')
            .single['progress_percentage'],
        66.67,
      );
      expect((rows['exercise_session'] as List), hasLength(23));
    },
  );
}
