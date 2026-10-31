import 'dart:convert';

import 'package:physical_treatment_and_health_support_system/model/result.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/food_item.dart';
import 'package:physical_treatment_and_health_support_system/model/repository/food_repository/i_food_repository.dart';

/// The catalogue from assets/seed/food_catalogue.json, the same file the AI server uses and the
/// Supabase seed is built from (supabase/seed/build_food_seed.py).
class FakeFoodRepository implements IFoodRepository {
  final List<FoodItem> foods;

  FakeFoodRepository(List<FoodItem> foods)
    : foods = [...foods]..sort((a, b) => a.foodName.compareTo(b.foodName));

  factory FakeFoodRepository.fromJson(String json) {
    final j = jsonDecode(json) as Map<String, dynamic>;
    return FakeFoodRepository(
      (j['foods'] as List)
          .map((f) => FoodItem.fromJson(f as Map<String, dynamic>))
          .toList(),
    );
  }

  @override
  Future<Result<List<FoodItem>>> all() async => Success(foods);

  @override
  Future<Result<List<FoodItem>>> search(String term) async =>
      Success(searchFoods(foods, term));

  @override
  Future<Result<FoodItem?>> byId(String foodId) async =>
      Success(foods.where((f) => f.foodId == foodId).firstOrNull);

  @override
  Future<Result<FoodItem?>> byKey(String foodKey) async =>
      Success(foods.where((f) => f.foodKey == foodKey).firstOrNull);

  @override
  Future<Result<List<String>>> restrictionsFor(String foodId) async => Success(
    foods.where((f) => f.foodId == foodId).firstOrNull?.restrictionCodes ?? const [],
  );

  @override
  Future<Result<List<FoodItem>>> alternativesTo(
    FoodItem f,
    List<String> avoidCodes,
  ) async => Success(
    foods
        .where(
          (g) =>
              g.foodId != f.foodId &&
              g.foodCategory == f.foodCategory &&
              !g.restrictionCodes.any(avoidCodes.contains),
        )
        .toList(),
  );
}
