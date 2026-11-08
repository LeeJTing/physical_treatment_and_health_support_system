import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:physical_treatment_and_health_support_system/core/utils/id_utils.dart';
import 'package:physical_treatment_and_health_support_system/model/business_logic/diet_planner_service/diet_planner_service.dart';
import 'package:physical_treatment_and_health_support_system/model/business_logic/suitability_service/suitability_service.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/diet_plan.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/diet_targets.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/enums.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/food_item.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/health_profile.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/lookups.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/meal_log.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/safety_limit.dart';
import 'package:physical_treatment_and_health_support_system/model/repository/food_repository/fake_food_repository.dart';
import 'package:physical_treatment_and_health_support_system/shared_client/api_client/api_client.dart';

/// The diet follows the whole profile: food names the patient cannot eat, physical limitations,
/// declared conditions, and an energy target from a validated equation. Same cases as the AI
/// server's tests/test_food_targets.py.
final foods = FakeFoodRepository.fromJson(File('assets/seed/food_catalogue.json').readAsStringSync());
FoodItem food(String key) => foods.foods.firstWhere((f) => f.foodKey == key);
HealthCondition cond(String c) => LookupSeed.conditions.firstWhere((x) => x.conditionCode == c);
PhysicalLimitation lim(String c) => LookupSeed.limitations.firstWhere((x) => x.limitationCode == c);
DietaryRestriction restr(String c) => LookupSeed.restrictions.firstWhere((x) => x.restrictionCode == c);

const limit = SafetyLimit(
  safetyLimitId: 'sl',
  maxExerciseIntensity: ExerciseIntensity.moderate,
  maxSessionDurationMin: 30,
  dailyCalorieTarget: 1800,
  dailySodiumLimitMg: 2000,
  dailySugarLimitG: 25,
);

void main() {
  const s = SuitabilityService();

  group('energy target (Mifflin-St Jeor x activity level)', () {
    int? e(int? a, bool male, double? w, double h, [List<String> l = const [], List<String> c = const []]) =>
        DietTargets.energyTarget(age: a, male: male, weightKg: w, heightCm: h, limitations: l, conditions: c);

    test('same numbers as the server', () {
      expect(e(60, false, 65, 158), 1765);
      expect(e(60, false, 65, 158, ['LEFT_ARM_MOBILITY']), 1706);
      expect(e(60, false, 65, 158, ['BALANCE_IMPAIRMENT']), 1647);
      expect(e(45, true, 90, 170), 2114); // BMI 31.1: - 500
      expect(e(30, false, 60, 160, [], ['PREGNANCY']), 2219);
      expect(e(80, false, 75, 145, ['RIGHT_LEG_MOBILITY']), 1200); // floor for women
      expect(e(50, false, null, 158), isNull);
    });

    test('the safety limit uses it', () {
      final p = HealthProfile(
        profileId: newId(),
        accountId: 'a',
        age: 60,
        gender: Gender.female,
        weightKg: 65,
        heightCm: 158,
        limitations: [lim('BALANCE_IMPAIRMENT')],
        updatedAt: DateTime.now(),
      );
      expect(p.generateSafetyLimit().dailyCalorieTarget, 1647);
    });
  });

  test('condition targets', () {
    final t = DietTargets.of(energyKcal: 1800, conditions: ['HEART_DISEASE', 'KIDNEY_DISEASE', 'OSTEOPOROSIS'], weightKg: 70);
    expect(t.limits['sat_fat_g'], 20.0);
    expect(t.limits['protein_g'], 56.0);
    expect(t.needs['calcium_mg_min'], 1000);
    expect(t.needs.containsKey('protein_g_min'), isFalse);
    final t2 = DietTargets.of(
      energyKcal: 1800,
      conditions: ['FOOT_ULCER', 'PREGNANCY'],
      limitations: ['RIGHT_ARM_MOBILITY'],
      weightKg: 60,
    );
    expect(t2.needs['protein_g_min'], 72.0);
    expect(t2.limits['caffeine_mg'], 200);
    expect(t2.oneHandOnly && t2.pregnant, isTrue);
  });

  group('foods the patient cannot eat are food names', () {
    test('the list holds food names, grouped', () {
      final codes = LookupSeed.restrictions.map((r) => r.restrictionCode).toSet();
      expect(codes, containsAll(['ONION', 'GARLIC', 'PORK', 'PRAWN', 'PEANUT', 'MILK']));
      expect(codes.intersection({'HALAL', 'VEGETARIAN', 'VEGAN', 'SHELLFISH'}), isEmpty);
      expect(LookupSeed.restrictions.every((r) => LookupSeed.foodGroups.contains(r.foodGroup)), isTrue);
    });

    test('a dish with a declared food name is Not Suitable, and the reason names it', () {
      final vs = s.assess(MealItem.of(food('nasi_goreng')), DietContext(limit: limit, restrictions: [restr('ONION')]));
      expect(s.mostRestrictive(vs), Verdict.notSuitable);
      expect(vs.first.reasonText, contains('onion'));
      expect(vs.first.restrictionId, restr('ONION').restrictionId);
    });

    test('an older diet label still works as its food names', () {
      const halal = DietaryRestriction(5, 'HALAL', 'Halal', RestrictionType.religious, isActive: false);
      expect(DietaryRestriction.expandCodes(['HALAL']), ['PORK', 'LARD', 'ALCOHOL']);
      expect(food('char_siew').breaches(halal), isTrue);
      expect(food('nasi_ayam').breaches(halal), isFalse);
    });
  });

  group('conditions and limitations', () {
    test('pregnancy: raw fish, half-boiled eggs and alcohol are Not Suitable; caffeine is Caution', () {
      final c = DietContext(limit: limit, conditions: [cond('PREGNANCY')]);
      for (final k in ['hinava', 'telur_separuh_masak', 'char_siew']) {
        expect(s.mostRestrictive(s.assess(MealItem.of(food(k)), c)), Verdict.notSuitable, reason: k);
      }
      final two = s.assess(MealItem.of(food('kopi_o'), grams: 500), c);
      expect(two.any((v) => v.nutrient == 'caffeine_mg' && v.verdict == Verdict.caution), isTrue);
    });

    test('arm limitation: a food that needs two hands is Caution and left out of plans', () {
      final c = DietContext(limit: limit, limitations: [lim('LEFT_ARM_MOBILITY')]);
      final vs = s.assess(MealItem.of(food('chilli_crab')), c);
      expect(vs.any((v) => v.verdict == Verdict.caution && v.reasonText.contains('two hands')), isTrue);
      expect(s.isExcludedFromPlans(food('chilli_crab'), c), isTrue);
      expect(s.isExcludedFromPlans(food('steamed_chicken'), c), isFalse);
    });

    test('heart disease limits saturated fat; kidney disease potassium is at most Caution', () {
      final heart = s.assess(MealItem.of(food('rendang_daging')), DietContext(limit: limit, conditions: [cond('HEART_DISEASE')]));
      expect(heart.any((v) => v.nutrient == 'sat_fat_g' && v.verdict == Verdict.notSuitable), isTrue);
      final kidney = s.assess(MealItem.of(food('air_kelapa')), DietContext(limit: limit, conditions: [cond('KIDNEY_DISEASE')]));
      final k = kidney.firstWhere((v) => v.nutrient == 'potassium_mg');
      expect(k.verdict, Verdict.caution);
      expect(k.reasonText, contains('doctor'));
    });

    test('the phone-side gate checks saturated fat and two-hand foods too', () {
      final planner = DietPlannerService(ApiClient(baseUrl: 'x', tokenProvider: () => null), foods);
      final day = DateTime(2026, 11, 2);
      DietPlan plan(List<PlannedMeal> m) => DietPlan(
        dietPlanId: 'p',
        accountId: 'a',
        safetyLimitId: 'sl',
        planType: PlanType.daily,
        startDate: day,
        endDate: day,
        modelVersion: 'test',
        generatedAt: day,
        meals: m,
      );
      final fatty = plan([
        PlannedMeal.of(food('rendang_daging'), day, MealSlot.lunch, 120),
        PlannedMeal.of(food('nasi_putih'), day, MealSlot.lunch, 160),
      ]);
      expect(planner.validate(fatty, DietContext(limit: limit, conditions: [cond('HEART_DISEASE')])), isNotEmpty);
      final crab = plan([PlannedMeal.of(food('chilli_crab'), day, MealSlot.dinner, 150)]);
      expect(planner.validate(crab, DietContext(limit: limit, limitations: [lim('RIGHT_ARM_MOBILITY')])), isNotEmpty);
      expect(planner.validate(crab, DietContext(limit: limit)), isEmpty);
    });
  });
}
