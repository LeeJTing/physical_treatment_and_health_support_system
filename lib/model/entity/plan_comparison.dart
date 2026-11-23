import 'package:physical_treatment_and_health_support_system/model/entity/enums.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/food_item.dart';

enum MealComparisonStatus {
  close('Close to plan'),
  portions('Portion changed'),
  foods('Different foods'),
  noLog('Not logged'),
  upcoming('Not due yet'),
  unplanned('No planned meal'),
  reference('Reference only'),
  unavailable('Cannot compare');

  final String label;
  const MealComparisonStatus(this.label);
}

class ComparedFood {
  final String key, name;
  final double plannedG, loggedG;
  final Nutrients planned, logged;
  const ComparedFood(
    this.key,
    this.name,
    this.plannedG,
    this.loggedG,
    this.planned,
    this.logged,
  );
  bool get added => plannedG == 0 && loggedG > 0;
  bool get absent => plannedG > 0 && loggedG == 0;
  bool get changedPortion =>
      plannedG > 0 &&
      loggedG > 0 &&
      (loggedG - plannedG).abs() > plannedG * .1 + .01;
}

class MealPlanComparison {
  final DateTime date;
  final MealSlot slot;
  final MealComparisonStatus status;
  final List<ComparedFood> foods;
  final int logCount;
  final String? note;
  const MealPlanComparison({
    required this.date,
    required this.slot,
    required this.status,
    required this.foods,
    required this.logCount,
    this.note,
  });
  bool get comparable => [
    MealComparisonStatus.close,
    MealComparisonStatus.portions,
    MealComparisonStatus.foods,
  ].contains(status);
  bool get changed =>
      status == MealComparisonStatus.portions ||
      status == MealComparisonStatus.foods;
  Nutrients get planned => Nutrients.sum(foods.map((f) => f.planned));
  Nutrients get logged => Nutrients.sum(foods.map((f) => f.logged));
  Nutrients get difference => logged - planned;
}

class ComparisonDay {
  final DateTime date;
  final List<MealPlanComparison> meals;
  final bool future;
  const ComparisonDay(this.date, this.meals, this.future);
  bool get hasPlan => meals.any((m) => m.foods.any((f) => f.plannedG > 0));
  bool get hasLogs => meals.any((m) => m.logCount > 0);
  bool get validTotals =>
      meals.every((m) => m.status != MealComparisonStatus.unavailable);
  Nutrients get planned => Nutrients.sum(meals.map((m) => m.planned));
  Nutrients get logged => Nutrients.sum(meals.map((m) => m.logged));
}

class RepeatedFoodChange {
  final String name, change;
  final int meals;
  const RepeatedFoodChange(this.name, this.change, this.meals);
}

class PlanComparisonReport {
  final DateTime start, end;
  final List<ComparisonDay> days;
  final List<MealPlanComparison> previousMeals;
  final bool plansAvailable;
  const PlanComparisonReport(
    this.start,
    this.end,
    this.days,
    this.previousMeals,
    this.plansAvailable,
  );
  List<MealPlanComparison> get meals => days.expand((d) => d.meals).toList();
  List<MealPlanComparison> get compared =>
      meals.where((m) => m.comparable).toList();
  int count(MealComparisonStatus status) =>
      meals.where((m) => m.status == status).length;
  Nutrients get plannedAverage => average(compared, planned: true);
  Nutrients get loggedAverage => average(compared, planned: false);
  static Nutrients average(
    List<MealPlanComparison> meals, {
    required bool planned,
  }) => meals.isEmpty
      ? Nutrients.zero
      : Nutrients.sum(
          meals.map((m) => planned ? m.planned : m.logged),
        ).scale(1 / meals.length);
  List<RepeatedFoodChange> get repeatedChanges {
    final groups = <String, (String, String, int)>{};
    for (final meal in compared) {
      for (final food in meal.foods) {
        final change = food.added
            ? 'Added'
            : food.absent
            ? 'Not in the log'
            : food.changedPortion
            ? 'Portion changed'
            : null;
        if (change == null) continue;
        final key = '${food.key}|$change';
        groups[key] = (food.name, change, (groups[key]?.$3 ?? 0) + 1);
      }
    }
    return [for (final g in groups.values) RepeatedFoodChange(g.$1, g.$2, g.$3)]
      ..sort((a, b) => b.meals.compareTo(a.meals));
  }
}
