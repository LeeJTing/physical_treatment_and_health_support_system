import 'package:physical_treatment_and_health_support_system/model/result.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/food_item.dart';

/// Contract for the nutrition catalogue and its restriction tags (Table 4.78).
abstract interface class IFoodRepository {
  /// The whole catalogue, alphabetical (cached after the first read).
  Future<Result<List<FoodItem>>> all();

  /// Manual food lookup by name, Malay or English (FR700_006, FR700_050).
  Future<Result<List<FoodItem>>> search(String term);

  /// Single catalogue read.
  Future<Result<FoodItem?>> byId(String foodId);

  /// The food the recogniser or the planner named by its key (food_item.food_key).
  Future<Result<FoodItem?>> byKey(String foodKey);

  /// Codes of the restrictions the food breaches (food_restriction).
  Future<Result<List<String>>> restrictionsFor(String foodId);

  /// Foods of the same category that carry none of [avoidCodes] (FR700_020). The suitability
  /// service then keeps the ones within the patient's limits and orders them by closeness.
  Future<Result<List<FoodItem>>> alternativesTo(FoodItem f, List<String> avoidCodes);
}

/// Search shared by the fake and the Supabase repository: every word of the term must appear in
/// the name or the key, so "nasi lemak", "lemak" and "ayam goreng" all work.
List<FoodItem> searchFoods(List<FoodItem> foods, String term) {
  final words = term.toLowerCase().split(RegExp(r'\s+')).where((w) => w.isNotEmpty);
  if (words.isEmpty) return foods;
  return foods.where((f) {
    final hay = '${f.foodName} ${f.foodKey.replaceAll('_', ' ')} ${f.foodCategory}'.toLowerCase();
    return words.every(hay.contains);
  }).toList();
}
