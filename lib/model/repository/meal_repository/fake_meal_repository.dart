import 'dart:typed_data';

import 'package:physical_treatment_and_health_support_system/model/result.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/diet_plan.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/enums.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/meal_log.dart';
import 'package:physical_treatment_and_health_support_system/model/repository/meal_repository/i_meal_repository.dart';

class FakeMealRepository implements IMealRepository {
  final List<MealLog> meals = [];
  final Map<String, Uint8List> images = {};
  final List<DietPlan> plans = [];
  bool failNext = false;

  @override
  Future<Result<MealLog>> saveMeal(MealLog m, {Uint8List? image}) async {
    if (failNext) {
      failNext = false;
      return const Failure('offline', code: 'offline');
    }
    var saved = m.copyWith(items: [for (final i in m.items) i.withMeal(m.mealId)]);
    if (image != null) {
      final path = '${m.accountId}/${m.mealId}.jpg';
      images[path] = image;
      saved = saved.copyWith(imageUri: path);
    }
    meals.removeWhere((x) => x.mealId == m.mealId);
    meals.add(saved);
    return Success(saved);
  }

  @override
  Future<Result<List<MealLog>>> findMeals(String accountId, DateTime from, DateTime to) async =>
      Success(
        meals
            .where(
              (m) =>
                  m.accountId == accountId &&
                  !m.consumedAt.isBefore(from) &&
                  !m.consumedAt.isAfter(to),
            )
            .toList()
          ..sort((a, b) => b.consumedAt.compareTo(a.consumedAt)),
      );

  @override
  Future<Result<void>> deleteMeal(MealLog m) async {
    meals.removeWhere((x) => x.mealId == m.mealId);
    if (m.imageUri != null) images.remove(m.imageUri);
    return const Success(null);
  }

  @override
  Future<Result<void>> savePlan(DietPlan p) async {
    plans.add(p);
    return const Success(null);
  }

  @override
  Future<Result<DietPlan?>> planFor(String accountId, PlanType type, DateTime day) async {
    final d = DateTime(day.year, day.month, day.day);
    final match = plans
        .where(
          (p) =>
              p.accountId == accountId &&
              p.planType == type &&
              !d.isBefore(p.startDate) &&
              !d.isAfter(p.endDate),
        )
        .toList()
      ..sort((a, b) => a.generatedAt.compareTo(b.generatedAt));
    return Success(match.lastOrNull);
  }

  @override
  Future<Result<void>> updatePlan(DietPlan p) async {
    final i = plans.indexWhere((x) => x.dietPlanId == p.dietPlanId);
    if (i >= 0) plans[i] = p;
    return const Success(null);
  }
}
