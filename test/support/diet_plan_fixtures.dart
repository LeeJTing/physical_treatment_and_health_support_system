import 'package:physical_treatment_and_health_support_system/model/entity/diet_plan.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/enums.dart';
import 'package:physical_treatment_and_health_support_system/model/repository/food_repository/fake_food_repository.dart';

/// Complete calorie fixtures keep the food under test unchanged and fill the other main meals.
/// This deliberately uses catalogue arithmetic rather than the planner under test.
Map<String, dynamic> adequateDay(
  FakeFoodRepository foods,
  DateTime day, {
  String key = 'oats',
  double grams = 125,
  double energyTarget = 1600,
}) {
  final focus = foods.foods.where((f) => f.foodKey == key).firstOrNull;
  final energy = focus == null || !grams.isFinite || grams <= 0 ? 0.0 : focus.nutrientsFor(grams).energyKcal;
  final topUp = (energyTarget * 0.85 - energy).clamp(0.0, energyTarget);
  return {
    'plan_date': day.toIso8601String().substring(0, 10),
    'meals': [
      {
        'meal_slot': 'BREAKFAST',
        'items': [
          {'food_key': key, 'portion_g': grams, 'verdict': 'SUITABLE'},
        ],
      },
      for (final pair in [('LUNCH', 'nasi_putih'), ('DINNER', 'nasi_beras_perang')])
        if (topUp > 0)
          {
            'meal_slot': pair.$1,
            'items': [
              {
                'food_key': pair.$2,
                'portion_g': (topUp / 2 / foods.foods.firstWhere((f) => f.foodKey == pair.$2).energyKcalPer100g * 100)
                    .round(),
                'verdict': 'SUITABLE',
              },
            ],
          },
    ],
  };
}

List<PlannedMeal> adequateMeals(FakeFoodRepository foods, DateTime day, {double grams = 125}) {
  final data = adequateDay(foods, day, grams: grams);
  return [
    for (final slot in data['meals'] as List)
      for (final item in slot['items'] as List)
        PlannedMeal.of(
          foods.foods.firstWhere((f) => f.foodKey == item['food_key']),
          day,
          MealSlot.fromDb(slot['meal_slot'] as String),
          (item['portion_g'] as num).toDouble(),
        ),
  ];
}
