import 'package:physical_treatment_and_health_support_system/model/entity/food_item.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/meal_log.dart';

class MealSimulation {
  final List<MealItem> items;
  final Nutrients original, proposed, afterDay, remaining;
  final List<String> warnings;
  const MealSimulation(
    this.items,
    this.original,
    this.proposed,
    this.afterDay,
    this.remaining,
    this.warnings,
  );
  Nutrients get delta => proposed - original;
}
