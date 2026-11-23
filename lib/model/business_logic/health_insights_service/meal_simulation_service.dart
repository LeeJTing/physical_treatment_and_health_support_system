import 'package:physical_treatment_and_health_support_system/core/constants/app_constants.dart';
import 'package:physical_treatment_and_health_support_system/model/business_logic/suitability_service/suitability_service.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/food_item.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/meal_log.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/meal_simulation.dart';

class MealSimulationService {
  const MealSimulationService();
  MealSimulation compare({
    required List<MealItem> original,
    required List<MealItem> proposed,
    required Nutrients alreadyLogged,
    required DietContext context,
  }) {
    final merged = MealItem.mergeDuplicates(proposed);
    final totals = Nutrients.sum(merged.map((i) => i.nutrients)),
        after = alreadyLogged + totals;
    final warnings = <String>[
      if (context.failSafe)
        'Your profile is unavailable. Conservative limits apply; suitability cannot be fully confirmed.',
      for (final item in merged) ...[
        if (!item.portionSizeG.isFinite ||
            item.portionSizeG < AppConstants.portionMinG ||
            item.portionSizeG > AppConstants.portionMaxG)
          '${item.food.foodName}: portion must be ${AppConstants.portionMinG}–${AppConstants.portionMaxG} g.',
        ...const SuitabilityService()
            .assess(item, context)
            .where((v) => v.verdict.index > 0)
            .map((v) => '${item.food.foodName}: ${v.reasonText}'),
      ],
      if (after.energyKcal > context.dailyEnergyKcal)
        'Recorded food plus this proposal exceeds today’s energy target.',
      if (after.sodiumMg > context.dailySodiumMg)
        'Recorded food plus this proposal exceeds today’s sodium limit.',
      if (after.sugarG > context.dailySugarG)
        'Recorded food plus this proposal exceeds today’s free-sugar limit.',
    ];
    return MealSimulation(
      merged,
      Nutrients.sum(original.map((i) => i.nutrients)),
      totals,
      after,
      context.remaining(after),
      warnings.toSet().toList(),
    );
  }
}
