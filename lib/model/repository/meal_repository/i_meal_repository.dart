import 'dart:typed_data';

import 'package:physical_treatment_and_health_support_system/model/result.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/diet_plan.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/enums.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/meal_log.dart';

/// Contract for meals, items, verdicts and diet plans (Table 4.79).
abstract interface class IMealRepository {
  /// Writes the meal with its items and verdicts. [image] is the confirmed photograph; it is stored
  /// only now, after the patient confirmed the result (FR700_009). Returns the saved meal (with its
  /// image path).
  Future<Result<MealLog>> saveMeal(MealLog m, {Uint8List? image});

  /// Dietary history for a date range, newest first (FR700_014).
  Future<Result<List<MealLog>>> findMeals(String accountId, DateTime from, DateTime to);

  /// The stored photograph of a meal ([imageUri] is `MealLog.imageUri`), so the patient can see
  /// what they ate in the meal history (FR700_009, FR700_014).
  Future<Result<Uint8List>> mealPhoto(String imageUri);

  /// Deletes the meal, its items and verdicts, and its stored photograph (FR700_015, FR700_016).
  Future<Result<void>> deleteMeal(MealLog m);

  /// Persists a generated plan with its planned meals (FR700_041).
  Future<Result<void>> savePlan(DietPlan p);

  /// The newest plan of [type] that covers [day], with its planned meals.
  Future<Result<DietPlan?>> planFor(String accountId, PlanType type, DateTime day);

  /// Saves changed planned meals (locked, replaced, logged) and the plan's adherence rate.
  Future<Result<void>> updatePlan(DietPlan p);
}
