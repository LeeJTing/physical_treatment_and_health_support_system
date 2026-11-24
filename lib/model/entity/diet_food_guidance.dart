import 'package:physical_treatment_and_health_support_system/model/entity/enums.dart';

enum FoodGuidanceKind { restore, reduce, replace }

/// A review of recorded portions, not an automatic prescription or log edit.
class FoodGuidanceAction {
  final String foodKey, foodName, reason, summary;
  final MealSlot slot;
  final FoodGuidanceKind kind;
  final double loggedG, suggestedG;
  const FoodGuidanceAction({
    required this.foodKey,
    required this.foodName,
    required this.slot,
    required this.kind,
    required this.loggedG,
    required this.suggestedG,
    required this.reason,
    required this.summary,
  });
  String get label => switch (kind) {
    FoodGuidanceKind.restore => 'More / restore',
    FoodGuidanceKind.reduce => 'Less / smaller portion',
    FoodGuidanceKind.replace => 'Choose a replacement',
  };
  String get portion => kind == FoodGuidanceKind.replace
      ? '${slot.label}: $foodName — ${grams(loggedG)} g logged; replace this item'
      : '${slot.label}: $foodName — ${grams(loggedG)} g logged; review ${grams(suggestedG)} g';
  static String grams(double g) => g.toStringAsFixed(g % 1 == 0 ? 0 : 1);
}

class DailyFoodGuidance {
  final DateTime date;
  final String conclusion;
  final List<FoodGuidanceAction> actions;
  const DailyFoodGuidance(this.date, this.conclusion, this.actions);
}

class WeeklyFoodPriority {
  final String title, detail;
  final List<DateTime> dates;
  const WeeklyFoodPriority(this.title, this.detail, this.dates);
}

class DietFoodGuidance {
  final String basis;
  final List<DailyFoodGuidance> days;
  final List<WeeklyFoodPriority> priorities;
  const DietFoodGuidance(this.basis, this.days, this.priorities);
}
