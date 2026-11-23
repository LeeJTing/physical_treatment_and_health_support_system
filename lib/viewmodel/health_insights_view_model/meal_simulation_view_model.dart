import 'package:physical_treatment_and_health_support_system/core/constants/app_constants.dart';
import 'package:physical_treatment_and_health_support_system/model/business_logic/health_insights_service/meal_simulation_service.dart';
import 'package:physical_treatment_and_health_support_system/model/business_logic/suitability_service/suitability_service.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/food_item.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/meal_log.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/meal_simulation.dart';
import 'package:physical_treatment_and_health_support_system/viewmodel/base_view_model.dart';

class MealSimulationViewModel extends BaseViewModel {
  final List<MealItem> original;
  final Nutrients alreadyLogged;
  final DietContext context;
  late List<MealItem> proposed;
  MealSimulationViewModel(
    List<MealItem> items,
    this.alreadyLogged,
    this.context,
  ) : original = List.unmodifiable(items) {
    proposed = List.of(items);
  }
  MealSimulation get result => const MealSimulationService().compare(
    original: original,
    proposed: proposed,
    alreadyLogged: alreadyLogged,
    context: context,
  );
  String? _validate(List<MealItem> items) {
    if (items.any(
      (i) =>
          !i.portionSizeG.isFinite ||
          i.portionSizeG < AppConstants.portionMinG ||
          i.portionSizeG > AppConstants.portionMaxG,
    )) {
      return 'Each combined food portion must be ${AppConstants.portionMinG}–${AppConstants.portionMaxG} g.';
    }
    return null;
  }

  bool _change(List<MealItem> items) {
    final merged = MealItem.mergeDuplicates(items);
    final error = _validate(merged);
    setError(error);
    if (error != null) return false;
    proposed = merged;
    notifyListeners();
    return true;
  }

  void reset() {
    proposed = List.of(original);
    setError(null);
    notifyListeners();
  }

  void remove(MealItem item) =>
      _change(proposed.where((i) => i.mealItemId != item.mealItemId).toList());
  bool resize(MealItem item, String text) {
    final grams = double.tryParse(text.trim().replaceAll(',', '.'));
    if (grams == null ||
        !grams.isFinite ||
        grams < AppConstants.portionMinG ||
        grams > AppConstants.portionMaxG) {
      setError(
        'Enter a portion from ${AppConstants.portionMinG} to ${AppConstants.portionMaxG} g.',
      );
      return false;
    }
    return _change([
      for (final i in proposed)
        i.mealItemId == item.mealItemId ? i.scaleTo(grams) : i,
    ]);
  }

  bool replace(MealItem item, FoodItem food) => _change([
    for (final i in proposed)
      i.mealItemId == item.mealItemId
          ? MealItem.of(food, grams: food.baseServingG, corrected: true)
          : i,
  ]);
  bool add(FoodItem food) => _change([...proposed, MealItem.of(food)]);
  bool suitable(FoodItem food) =>
      const SuitabilityService().suitsPatient(food, context);
}
