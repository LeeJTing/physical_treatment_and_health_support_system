import 'package:physical_treatment_and_health_support_system/model/entity/food_item.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/meal_log.dart';

class DietReviewDay {
  final DateTime date;
  final List<MealLog> meals;
  final bool future;
  const DietReviewDay(this.date, this.meals, {this.future = false});
  Nutrients get totals => Nutrients.sum(meals.map((m) => m.totals));
  int get mainMeals => meals
      .where((m) => m.mealType.db != 'SNACK')
      .map((m) => m.mealType)
      .toSet()
      .length;
  bool get hasLogs => meals.isNotEmpty;
}

class ReviewNutrient {
  final String key, label, unit;
  final double average;
  final double? minimum, maximum;
  final bool catalogueEstimate;
  const ReviewNutrient(
    this.key,
    this.label,
    this.unit,
    this.average, {
    this.minimum,
    this.maximum,
    this.catalogueEstimate = false,
  });
}

class FoodContribution {
  final String foodKey, foodName;
  final double amount, share;
  const FoodContribution(this.foodKey, this.foodName, this.amount, this.share);
}

class WeeklyDietReview {
  final DateTime start, end;
  final List<DietReviewDay> days;
  final List<ReviewNutrient> nutrients;
  final Map<String, List<FoodContribution>> contributors;
  final int followedSlots, dueSlots;
  final bool plansAvailable;
  const WeeklyDietReview({
    required this.start,
    required this.end,
    required this.days,
    required this.nutrients,
    required this.contributors,
    this.followedSlots = 0,
    this.dueSlots = 0,
    this.plansAvailable = true,
  });
  int get loggedDays => days.where((d) => d.hasLogs).length;
  int get elapsedDays => days.where((d) => !d.future).length;
  int get threeMealDays => days.where((d) => d.mainMeals == 3).length;
}

class MealHealthPoint {
  final DateTime at;
  final double foodValue, readingValue;
  final String description;
  const MealHealthPoint(
    this.at,
    this.foodValue,
    this.readingValue,
    this.description,
  );
}

class MealHealthPattern {
  final String title, foodLabel, readingLabel, method;
  final List<MealHealthPoint> points;
  final int distinctDays;
  final double? correlation;
  final String? withheldReason;
  const MealHealthPattern({
    required this.title,
    required this.foodLabel,
    required this.readingLabel,
    required this.method,
    required this.points,
    required this.distinctDays,
    this.correlation,
    this.withheldReason,
  });
  bool get available => correlation != null;
}

class DietInsights {
  final WeeklyDietReview week;
  final DateTime patternFrom, patternTo;
  final List<MealHealthPattern> patterns;
  const DietInsights(
    this.week,
    this.patternFrom,
    this.patternTo,
    this.patterns,
  );
}
