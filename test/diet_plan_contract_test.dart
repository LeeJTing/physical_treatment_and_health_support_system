import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:physical_treatment_and_health_support_system/model/business_logic/diet_planner_service/diet_planner_service.dart';
import 'package:physical_treatment_and_health_support_system/model/business_logic/suitability_service/suitability_service.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/diet_plan.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/enums.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/lookups.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/safety_limit.dart';
import 'package:physical_treatment_and_health_support_system/model/repository/food_repository/fake_food_repository.dart';
import 'package:physical_treatment_and_health_support_system/shared_client/api_client/api_client.dart';

void main() {
  final foods = FakeFoodRepository.fromJson(File('assets/seed/food_catalogue.json').readAsStringSync());
  final fixtures = jsonDecode(File('test/fixtures/adequate_diet_plans.json').readAsStringSync()) as List;
  for (final fixture in fixtures.cast<Map>()) {
    test('real server 2.3 ${fixture['name']} week also passes the independent Flutter gate', () async {
      final req = fixture['request'] as Map, reply = fixture['response'] as Map;
      final limits = req['limits'] as Map;
      final ctx = DietContext(
        limit: SafetyLimit(
          safetyLimitId: 'test',
          maxExerciseIntensity: ExerciseIntensity.moderate,
          maxSessionDurationMin: 30,
          dailyCalorieTarget: (limits['daily_calorie_target'] as num).toInt(),
          dailySodiumLimitMg: (limits['daily_sodium_limit_mg'] as num).toInt(),
          dailySugarLimitG: (limits['daily_sugar_limit_g'] as num).toDouble(),
        ),
        conditions: LookupSeed.conditions.where((c) => (req['conditions'] as List).contains(c.conditionCode)).toList(),
        age: 60,
        gender: Gender.female,
        weightKg: 65,
        heightCm: 158,
      );
      final service = DietPlannerService(
        ApiClient(
          baseUrl: 'http://ai',
          tokenProvider: () => 'test',
          httpClient: MockClient((_) async => http.Response(jsonEncode(reply), 200)),
        ),
        foods,
      );
      final start = DateTime.parse(req['start_date'] as String);
      final local = DietPlan(
        dietPlanId: 'p',
        accountId: 'test',
        safetyLimitId: 'test',
        planType: PlanType.weekly,
        startDate: start,
        endDate: start.add(const Duration(days: 6)),
        modelVersion: reply['model_version'] as String,
        generatedAt: start,
        meals: [
          for (final d in reply['days'] as List)
            for (final s in d['meals'] as List)
              for (final i in s['items'] as List)
                PlannedMeal.of(
                  foods.foods.firstWhere((f) => f.foodKey == i['food_key']),
                  DateTime.parse(d['plan_date'] as String),
                  MealSlot.fromDb(s['meal_slot'] as String),
                  (i['portion_g'] as num).toDouble(),
                ),
        ],
      );
      expect(
        service.generationProblems(local, ctx),
        isEmpty,
        reason: service.generationProblems(local, ctx).join('\n'),
      );
      final result = await service.generate(accountId: 'test', ctx: ctx, type: PlanType.weekly, start: start);
      expect(result.isSuccess, isTrue);
      for (final day in result.dataOrNull!.days()) {
        expect(service.nutritionWarnings(result.dataOrNull!, day, ctx), isEmpty);
      }
    });
  }
}
