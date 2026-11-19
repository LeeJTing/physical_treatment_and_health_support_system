import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:physical_treatment_and_health_support_system/model/business_logic/risk_assessment_service/risk_assessment_service.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/diet_plan.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/enums.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/food_item.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/meal_log.dart';
import 'package:physical_treatment_and_health_support_system/model/repository/auth_repository/fake_auth_repository.dart';
import 'package:physical_treatment_and_health_support_system/model/repository/biometric_repository/fake_biometric_repository.dart';
import 'package:physical_treatment_and_health_support_system/model/repository/meal_repository/fake_meal_repository.dart';
import 'package:physical_treatment_and_health_support_system/model/repository/profile_repository/fake_profile_repository.dart';
import 'package:physical_treatment_and_health_support_system/view/diet_view/diet_insights_view.dart';
import 'package:physical_treatment_and_health_support_system/viewmodel/diet_insights_view_model/diet_insights_view_model.dart';

/// Disposable, deterministic comparison data. No network, saved user records or Bluetooth.
class PlanComparisonFixture {
  static final now = DateTime(2026, 11, 20, 22);
  static final start = DateTime(2026, 11, 16);
  static FoodItem food(
    String key,
    String name,
    double energy,
    double sodium, {
    double sugar = 0,
  }) => FoodItem.fromJson({
    'food_id': key,
    'food_key': key,
    'food_name': name,
    'food_category': 'Test',
    'base_serving_g': 100,
    'energy_kcal_per_100g': energy,
    'sodium_mg_per_100g': sodium,
    'sugar_g_per_100g': sugar,
    'carb_g_per_100g': 20,
    'protein_g_per_100g': 5,
    'fat_g_per_100g': 2,
  });
  static final rice = food('rice', 'Rice', 130, 5);
  static final tofu = food('tofu', 'Tofu', 80, 10);
  static final tea = food('tea', 'Teh tarik', 85, 35, sugar: 12);
  final auth = FakeAuthRepository();
  final meals = FakeMealRepository();
  final readings = FakeBiometricRepository();
  final profiles = FakeProfileRepository();
  late String account;
  late final DietInsightsViewModel vm;
  static Future<PlanComparisonFixture> create({bool populated = true}) async {
    final f = PlanComparisonFixture();
    f.account = (await f.auth.login(
      'demo@apths.test',
      'password123',
    )).dataOrNull!.accountId;
    if (populated) {
      for (var w = -1; w <= 0; w++) {
        final from = start.add(Duration(days: w * 7));
        final planned = <PlannedMeal>[];
        for (var i = 0; i < 7; i++) {
          final day = from.add(Duration(days: i));
          for (final (slot, hour) in [
            (MealSlot.breakfast, 8),
            (MealSlot.lunch, 13),
            (MealSlot.dinner, 19),
          ]) {
            planned.add(PlannedMeal.of(rice, day, slot, 100));
            if (w == 0 && slot == MealSlot.dinner) {
              planned.add(PlannedMeal.of(tofu, day, slot, 100));
            }
            if (day.isAfter(now) ||
                (w == 0 && i == 2 && slot == MealSlot.breakfast)) {
              continue;
            }
            f.meals.meals.add(
              MealLog(
                mealId: '$w-$i-${slot.name}',
                accountId: f.account,
                mealType: slot,
                entryMethod: EntryMethod.manual,
                consumedAt: DateTime(day.year, day.month, day.day, hour),
                items: [
                  MealItem.of(
                    rice,
                    grams: w == 0 && slot == MealSlot.lunch ? 150 : 100,
                  ),
                  if (w == 0 && slot == MealSlot.dinner)
                    MealItem.of(tea, grams: 250),
                ],
              ),
            );
          }
        }
        f.meals.plans.add(
          DietPlan(
            dietPlanId: 'plan-$w',
            accountId: f.account,
            safetyLimitId: 'fixture',
            planType: PlanType.weekly,
            startDate: from,
            endDate: from.add(const Duration(days: 6)),
            generatedAt: from.subtract(const Duration(days: 1)),
            modelVersion: 'fixture',
            meals: planned,
          ),
        );
      }
      f.meals.meals.add(
        MealLog(
          mealId: 'extra-snack',
          accountId: f.account,
          mealType: MealSlot.snack,
          entryMethod: EntryMethod.manual,
          consumedAt: DateTime(2026, 11, 20, 16),
          items: [MealItem.of(tofu)],
        ),
      );
    }
    f.vm = DietInsightsViewModel(
      f.meals,
      f.readings,
      f.auth,
      RiskAssessmentService(f.auth, f.profiles),
      now: () => now,
    );
    await f.vm.load();
    return f;
  }

  Widget get app => ChangeNotifierProvider.value(
    value: vm,
    child: const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: DietInsightsView(),
    ),
  );
}
