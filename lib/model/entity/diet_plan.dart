import 'package:physical_treatment_and_health_support_system/core/utils/id_utils.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/enums.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/food_item.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/meal_log.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/safety_limit.dart';

/// One food planned for one meal slot on one day (Table 4.52). Several rows make up a slot. Only
/// foods carrying no restriction the patient declared, and no Not Suitable verdict, may appear here
/// (FR700_033).
class PlannedMeal {
  final String plannedMealId;
  final String? dietPlanId;
  final FoodItem food;
  final DateTime planDate;
  final MealSlot mealSlot;
  final double portionSizeG;
  final double energyKcal;
  final double sodiumMg;
  final double sugarG;

  /// When true, regeneration leaves this row untouched (FR700_036).
  final bool isLocked;

  /// Whether a matching meal was logged (FR700_037): the numerator of the adherence rate.
  final bool isLogged;

  const PlannedMeal({
    required this.plannedMealId,
    this.dietPlanId,
    required this.food,
    required this.planDate,
    required this.mealSlot,
    required this.portionSizeG,
    required this.energyKcal,
    required this.sodiumMg,
    required this.sugarG,
    this.isLocked = false,
    this.isLogged = false,
  });

  factory PlannedMeal.of(
    FoodItem f,
    DateTime day,
    MealSlot slot,
    double grams, {
    bool locked = false,
  }) {
    final n = f.nutrientsFor(grams);
    return PlannedMeal(
      plannedMealId: newId(),
      food: f,
      planDate: DateTime(day.year, day.month, day.day),
      mealSlot: slot,
      portionSizeG: grams,
      energyKcal: n.energyKcal,
      sodiumMg: n.sodiumMg,
      sugarG: n.sugarG,
      isLocked: locked,
    );
  }

  Nutrients get nutrients => food.nutrientsFor(portionSizeG);

  PlannedMeal copyWith({
    bool? isLocked,
    bool? isLogged,
    String? dietPlanId,
  }) => PlannedMeal(
    plannedMealId: plannedMealId,
    dietPlanId: dietPlanId ?? this.dietPlanId,
    food: food,
    planDate: planDate,
    mealSlot: mealSlot,
    portionSizeG: portionSizeG,
    energyKcal: energyKcal,
    sodiumMg: sodiumMg,
    sugarG: sugarG,
    isLocked: isLocked ?? this.isLocked,
    isLogged: isLogged ?? this.isLogged,
  );

  /// The same planned food under a new id, for a regenerated plan that keeps it (FR700_036).
  PlannedMeal carriedOver() => PlannedMeal(
    plannedMealId: newId(),
    food: food,
    planDate: planDate,
    mealSlot: mealSlot,
    portionSizeG: portionSizeG,
    energyKcal: energyKcal,
    sodiumMg: sodiumMg,
    sugarG: sugarG,
    isLocked: isLocked,
    isLogged: isLogged,
  );

  /// Protects the slot from regeneration (FR700_036).
  PlannedMeal lock([bool on = true]) => copyWith(isLocked: on);

  /// Marks the slot as fulfilled by a logged meal of the same day and slot (FR700_037).
  bool matchLogged(MealLog m) {
    final d = m.consumedAt;
    return m.mealType == mealSlot &&
        d.year == planDate.year &&
        d.month == planDate.month &&
        d.day == planDate.day;
  }

  /// Swaps in an alternative that satisfies the same limits (FR700_035). Same energy where the
  /// alternative's serving allows, within half to one and a half servings.
  PlannedMeal replaceWith(FoodItem f) {
    final perG = f.energyKcalPer100g / 100;
    var g = perG > 0 ? energyKcal / perG : f.baseServingG;
    g = g.clamp(f.baseServingG * 0.5, f.baseServingG * 1.5);
    final n = f.nutrientsFor(g.roundToDouble());
    return PlannedMeal(
      plannedMealId: newId(),
      dietPlanId: dietPlanId,
      food: f,
      planDate: planDate,
      mealSlot: mealSlot,
      portionSizeG: g.roundToDouble(),
      energyKcal: n.energyKcal,
      sodiumMg: n.sodiumMg,
      sugarG: n.sugarG,
      isLocked: isLocked,
    );
  }

  Map<String, dynamic> toJson() => {
    'planned_meal_id': plannedMealId,
    'diet_plan_id': dietPlanId,
    'food_id': food.foodId,
    'plan_date': planDate.toIso8601String().substring(0, 10),
    'meal_slot': mealSlot.db,
    'portion_size_g': portionSizeG,
    'energy_kcal': energyKcal,
    'sodium_mg': sodiumMg,
    'sugar_g': sugarG,
    'is_locked': isLocked,
    'is_logged': isLogged,
  };

  factory PlannedMeal.fromJson(Map<String, dynamic> j, FoodItem food) =>
      PlannedMeal(
        plannedMealId: j['planned_meal_id'] as String,
        dietPlanId: j['diet_plan_id'] as String?,
        food: food,
        planDate: DateTime.parse(j['plan_date'] as String),
        mealSlot: MealSlot.fromDb(j['meal_slot'] as String?),
        portionSizeG: (j['portion_size_g'] as num).toDouble(),
        energyKcal: (j['energy_kcal'] as num).toDouble(),
        sodiumMg: (j['sodium_mg'] as num).toDouble(),
        sugarG: (j['sugar_g'] as num).toDouble(),
        isLocked: (j['is_locked'] ?? false) as bool,
        isLogged: (j['is_logged'] ?? false) as bool,
      );
}

/// One generated daily or weekly diet plan (Table 4.47; FR700_029 to FR700_045).
class DietPlan {
  final String dietPlanId;
  final String accountId;

  /// [SafetyLimit.failSafeId] when the plan was made under the fail-safe limits (UC900 E1).
  final String safetyLimitId;
  final PlanType planType;
  final DateTime startDate;
  final DateTime endDate;
  final double? adherenceRate;
  final String modelVersion;
  final DateTime generatedAt;
  final List<PlannedMeal> meals;

  const DietPlan({
    required this.dietPlanId,
    required this.accountId,
    required this.safetyLimitId,
    required this.planType,
    required this.startDate,
    required this.endDate,
    this.adherenceRate,
    required this.modelVersion,
    required this.generatedAt,
    this.meals = const [],
  });

  /// The slots planned for one day, in slot order.
  List<PlannedMeal> mealsFor(DateTime day) =>
      meals
          .where(
            (m) =>
                m.planDate.year == day.year &&
                m.planDate.month == day.month &&
                m.planDate.day == day.day,
          )
          .toList()
        ..sort((a, b) => a.mealSlot.index.compareTo(b.mealSlot.index));

  List<DateTime> days() {
    final out = <DateTime>[];
    for (var d = startDate; !d.isAfter(endDate); d = d.add(const Duration(days: 1))) {
      out.add(DateTime(d.year, d.month, d.day));
    }
    return out;
  }

  Nutrients totalsFor(DateTime day) =>
      Nutrients.sum(mealsFor(day).map((m) => m.nutrients)).rounded();

  /// Share of planned slots that were logged (FR700_038). A slot counts once however many foods
  /// it holds.
  double adherence() {
    final slots = <String, bool>{};
    for (final m in meals) {
      final k = '${m.planDate.toIso8601String().substring(0, 10)}|${m.mealSlot.db}';
      slots[k] = (slots[k] ?? false) || m.isLogged;
    }
    if (slots.isEmpty) return 0;
    return slots.values.where((v) => v).length / slots.length;
  }

  DietPlan copyWith({List<PlannedMeal>? meals, double? adherenceRate}) => DietPlan(
    dietPlanId: dietPlanId,
    accountId: accountId,
    safetyLimitId: safetyLimitId,
    planType: planType,
    startDate: startDate,
    endDate: endDate,
    adherenceRate: adherenceRate ?? this.adherenceRate,
    modelVersion: modelVersion,
    generatedAt: generatedAt,
    meals: meals ?? this.meals,
  );

  Map<String, dynamic> toJson() => {
    'diet_plan_id': dietPlanId,
    'account_id': accountId,
    'safety_limit_id': safetyLimitId == SafetyLimit.failSafeId ? null : safetyLimitId,
    'plan_type': planType.db,
    'start_date': startDate.toIso8601String().substring(0, 10),
    'end_date': endDate.toIso8601String().substring(0, 10),
    'adherence_rate': adherenceRate,
    'model_version': modelVersion,
    'generated_at': generatedAt.toUtc().toIso8601String(),
  };

  factory DietPlan.fromJson(Map<String, dynamic> j, List<PlannedMeal> meals) =>
      DietPlan(
        dietPlanId: j['diet_plan_id'] as String,
        accountId: j['account_id'] as String,
        safetyLimitId: j['safety_limit_id'] as String? ?? SafetyLimit.failSafeId,
        planType: PlanType.fromDb(j['plan_type'] as String?),
        startDate: DateTime.parse(j['start_date'] as String),
        endDate: DateTime.parse(j['end_date'] as String),
        adherenceRate: (j['adherence_rate'] as num?)?.toDouble(),
        modelVersion: j['model_version'] as String,
        generatedAt: DateTime.parse(j['generated_at'] as String).toLocal(),
        meals: meals,
      );
}
