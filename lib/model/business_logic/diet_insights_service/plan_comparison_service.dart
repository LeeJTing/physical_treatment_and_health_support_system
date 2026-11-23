import 'package:physical_treatment_and_health_support_system/model/business_logic/diet_planner_service/diet_planner_service.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/diet_plan.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/enums.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/food_item.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/meal_log.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/plan_comparison.dart';

/// Compares stored records, without inferring eating from absent logs or changing saved plans.
class PlanComparisonService {
  const PlanComparisonService();
  static DateTime day(DateTime at) {
    final d = at.toLocal();
    return DateTime(d.year, d.month, d.day);
  }

  static DietPlan? selectPlan(
    List<DietPlan> plans,
    String account,
    DateTime at,
  ) {
    final d = day(at);
    final candidates =
        plans
            .where(
              (p) =>
                  p.accountId == account &&
                  !d.isBefore(day(p.startDate)) &&
                  !d.isAfter(day(p.endDate)),
            )
            .toList()
          ..sort((a, b) {
            final daily = (a.planType == PlanType.daily ? 1 : 0).compareTo(
              b.planType == PlanType.daily ? 1 : 0,
            );
            if (daily != 0) return daily;
            final start = a.startDate.compareTo(b.startDate);
            if (start != 0) return start;
            final generated = a.generatedAt.compareTo(b.generatedAt);
            return generated != 0
                ? generated
                : a.dietPlanId.compareTo(b.dietPlanId);
          });
    return candidates.lastOrNull;
  }

  PlanComparisonReport build({
    required String accountId,
    required DateTime start,
    required DateTime now,
    required List<MealLog> meals,
    required Map<DateTime, DietPlan> plans,
    bool plansAvailable = true,
  }) {
    final from = day(start);
    final unique = <String, MealLog>{};
    for (final meal in meals) {
      if (meal.accountId == accountId && !meal.consumedAt.isAfter(now)) {
        unique[meal.mealId] = meal;
      }
    }
    List<ComparisonDay> period(DateTime beginning) => [
      for (var i = 0; i < 7; i++)
        _day(
          accountId,
          day(beginning.add(Duration(days: i))),
          now,
          unique.values.toList(),
          plans,
          plansAvailable,
        ),
    ];
    final current = period(from);
    final previous = period(from.subtract(const Duration(days: 7)));
    return PlanComparisonReport(
      from,
      from.add(const Duration(days: 6)),
      current,
      previous.expand((d) => d.meals).where((m) => m.comparable).toList(),
      plansAvailable,
    );
  }

  ComparisonDay _day(
    String account,
    DateTime date,
    DateTime now,
    List<MealLog> all,
    Map<DateTime, DietPlan> plans,
    bool available,
  ) {
    final p = plans[date];
    final plan = p?.accountId == account ? p : null;
    final rows = <MealPlanComparison>[];
    final future = date.isAfter(day(now));
    for (final slot in MealSlot.values) {
      final planned =
          plan?.mealsFor(date).where((m) => m.mealSlot == slot).toList() ??
          <PlannedMeal>[];
      final logged = all
          .where((m) => day(m.consumedAt) == date && m.mealType == slot)
          .toList();
      if (planned.isEmpty && logged.isEmpty) continue;
      final valid =
          planned.every(
            (m) =>
                m.portionSizeG.isFinite &&
                m.portionSizeG > 0 &&
                _valid(_plannedNutrients(m)),
          ) &&
          logged.every(
            (m) =>
                m.items.isNotEmpty &&
                m.items.every(
                  (i) =>
                      i.portionSizeG.isFinite &&
                      i.portionSizeG > 0 &&
                      _valid(i.nutrients),
                ),
          );
      final food = <String, ComparedFood>{};
      void add(FoodItem item, double grams, Nutrients nutrients, bool isPlan) {
        final key = item.foodKey.isEmpty ? item.foodId : item.foodKey;
        final old = food[key];
        food[key] = ComparedFood(
          key,
          item.foodName,
          (old?.plannedG ?? 0) + (isPlan ? grams : 0),
          (old?.loggedG ?? 0) + (isPlan ? 0 : grams),
          (old?.planned ?? Nutrients.zero) +
              (isPlan ? nutrients : Nutrients.zero),
          (old?.logged ?? Nutrients.zero) +
              (isPlan ? Nutrients.zero : nutrients),
        );
      }

      if (valid) {
        for (final row in planned) {
          add(row.food, row.portionSizeG, _plannedNutrients(row), true);
        }
        for (final meal in logged) {
          for (final row in meal.items) {
            add(row.food, row.portionSizeG, row.nutrients, false);
          }
        }
      }
      final firstLog = logged.isEmpty
          ? null
          : logged
                .map((m) => m.consumedAt)
                .reduce((a, b) => a.isBefore(b) ? a : b);
      final reference =
          firstLog != null &&
          plan != null &&
          plan.generatedAt.isAfter(firstLog);
      final deadline = DietPlannerService.deadlineOf(slot, date);
      final upcoming =
          future ||
          (logged.isEmpty &&
              day(now) == date &&
              (deadline == null || deadline.isAfter(now)));
      final status = !valid || !available
          ? MealComparisonStatus.unavailable
          : logged.isEmpty
          ? (upcoming
                ? MealComparisonStatus.upcoming
                : MealComparisonStatus.noLog)
          : planned.isEmpty
          ? MealComparisonStatus.unplanned
          : reference
          ? MealComparisonStatus.reference
          : food.values.any((f) => f.added || f.absent)
          ? MealComparisonStatus.foods
          : food.values.any((f) => f.changedPortion)
          ? MealComparisonStatus.portions
          : MealComparisonStatus.close;
      rows.add(
        MealPlanComparison(
          date: date,
          slot: slot,
          status: status,
          foods: food.values.toList(),
          logCount: logged.length,
          note: !valid
              ? 'Some amounts could not be read. Check the meal records before comparing.'
              : !available
              ? 'Saved plans could not be loaded. Retry to compare these records.'
              : reference
              ? 'This plan was saved after the meal. This is a reference comparison, not evidence of a missed target.'
              : null,
        ),
      );
    }
    return ComparisonDay(date, rows, future);
  }

  bool _valid(Nutrients n) =>
      n.toJson().values.every((v) => v is num && v.isFinite && v >= 0);
  Nutrients _plannedNutrients(PlannedMeal m) {
    final catalogue = m.nutrients;
    return Nutrients(
      energyKcal: m.energyKcal,
      sodiumMg: m.sodiumMg,
      sugarG: m.sugarG,
      carbG: catalogue.carbG,
      proteinG: catalogue.proteinG,
      fatG: catalogue.fatG,
    );
  }
}
