import 'package:physical_treatment_and_health_support_system/model/entity/lookups.dart';

/// Energy and the five nutrients the module tracks (UC800 C7): energy (kcal), carbohydrate (g),
/// protein (g), fat (g), sodium (mg), free sugars (g).
class Nutrients {
  final double energyKcal;
  final double carbG;
  final double proteinG;
  final double fatG;
  final double sodiumMg;
  final double sugarG;

  const Nutrients({
    this.energyKcal = 0,
    this.carbG = 0,
    this.proteinG = 0,
    this.fatG = 0,
    this.sodiumMg = 0,
    this.sugarG = 0,
  });

  static const zero = Nutrients();

  Nutrients operator +(Nutrients o) => Nutrients(
    energyKcal: energyKcal + o.energyKcal,
    carbG: carbG + o.carbG,
    proteinG: proteinG + o.proteinG,
    fatG: fatG + o.fatG,
    sodiumMg: sodiumMg + o.sodiumMg,
    sugarG: sugarG + o.sugarG,
  );

  Nutrients operator -(Nutrients o) => Nutrients(
    energyKcal: energyKcal - o.energyKcal,
    carbG: carbG - o.carbG,
    proteinG: proteinG - o.proteinG,
    fatG: fatG - o.fatG,
    sodiumMg: sodiumMg - o.sodiumMg,
    sugarG: sugarG - o.sugarG,
  );

  Nutrients scale(double f) => Nutrients(
    energyKcal: energyKcal * f,
    carbG: carbG * f,
    proteinG: proteinG * f,
    fatG: fatG * f,
    sodiumMg: sodiumMg * f,
    sugarG: sugarG * f,
  );

  static Nutrients sum(Iterable<Nutrients> all) =>
      all.fold(Nutrients.zero, (a, b) => a + b);

  /// One decimal, as stored (numeric(…,1/2) columns).
  Nutrients rounded() {
    double r(double x) => (x * 10).roundToDouble() / 10;
    return Nutrients(
      energyKcal: r(energyKcal),
      carbG: r(carbG),
      proteinG: r(proteinG),
      fatG: r(fatG),
      sodiumMg: r(sodiumMg),
      sugarG: r(sugarG),
    );
  }

  factory Nutrients.fromJson(Map<String, dynamic> j) => Nutrients(
    energyKcal: ((j['energy_kcal'] ?? 0) as num).toDouble(),
    carbG: ((j['carb_g'] ?? 0) as num).toDouble(),
    proteinG: ((j['protein_g'] ?? 0) as num).toDouble(),
    fatG: ((j['fat_g'] ?? 0) as num).toDouble(),
    sodiumMg: ((j['sodium_mg'] ?? 0) as num).toDouble(),
    sugarG: ((j['sugar_g'] ?? 0) as num).toDouble(),
  );

  Map<String, dynamic> toJson() => {
    'energy_kcal': energyKcal,
    'carb_g': carbG,
    'protein_g': proteinG,
    'fat_g': fatG,
    'sodium_mg': sodiumMg,
    'sugar_g': sugarG,
  };
}

/// Nutrition catalogue (Table 4.48). Values are per 100 g so any portion scales from one row.
/// [foodKey] is the label the food recogniser and the planner use for the food (food_item.food_key).
class FoodItem {
  final String foodId;
  final String foodKey;
  final String foodName;
  final String foodCategory;
  final double baseServingG;
  final double energyKcalPer100g;
  final double carbGPer100g;
  final double proteinGPer100g;
  final double fatGPer100g;
  final double sodiumMgPer100g;
  final double sugarGPer100g;

  /// Codes of the dietary restrictions this food breaches (food_restriction).
  final List<String> restrictionCodes;

  /// meal, staple, protein, veg, fruit, drink, snack, dessert or soup: how the planner may use it.
  final String planRole;

  /// Meal slots it is planned for (BREAKFAST, LUNCH, DINNER, SNACK).
  final List<String> mealSlots;

  const FoodItem({
    required this.foodId,
    required this.foodKey,
    required this.foodName,
    required this.foodCategory,
    required this.baseServingG,
    required this.energyKcalPer100g,
    required this.carbGPer100g,
    required this.proteinGPer100g,
    required this.fatGPer100g,
    required this.sodiumMgPer100g,
    required this.sugarGPer100g,
    this.restrictionCodes = const [],
    this.planRole = 'meal',
    this.mealSlots = const [],
  });

  /// Scales the per-100 g figures to a portion (FR700_010, FR700_011).
  Nutrients nutrientsFor(double grams) {
    final f = grams / 100;
    return Nutrients(
      energyKcal: energyKcalPer100g * f,
      carbG: carbGPer100g * f,
      proteinG: proteinGPer100g * f,
      fatG: fatGPer100g * f,
      sodiumMg: sodiumMgPer100g * f,
      sugarG: sugarGPer100g * f,
    ).rounded();
  }

  /// Whether this food carries the restriction tag.
  bool breaches(DietaryRestriction r) => restrictionCodes.contains(r.restrictionCode);

  /// Whether the food collides with anything the patient declared.
  bool breachesAny(List<DietaryRestriction> rs) => rs.any(breaches);

  /// From a row of the catalogue JSON (assets/seed/food_catalogue.json) or of food_item.
  factory FoodItem.fromJson(Map<String, dynamic> j) {
    double d(String k) => ((j[k] ?? 0) as num).toDouble();
    final key = (j['food_key'] ?? j['food_id']) as String;
    return FoodItem(
      foodId: (j['food_id'] ?? key) as String,
      foodKey: key,
      foodName: j['food_name'] as String,
      foodCategory: j['food_category'] as String,
      baseServingG: d('base_serving_g'),
      energyKcalPer100g: d('energy_kcal_per_100g'),
      carbGPer100g: d('carb_g_per_100g'),
      proteinGPer100g: d('protein_g_per_100g'),
      fatGPer100g: d('fat_g_per_100g'),
      sodiumMgPer100g: d('sodium_mg_per_100g'),
      sugarGPer100g: d('sugar_g_per_100g'),
      restrictionCodes: ((j['restrictions'] as List?) ?? const []).cast<String>(),
      planRole: (j['plan_role'] ?? 'meal') as String,
      mealSlots: ((j['meal_slots'] as List?) ?? const []).cast<String>(),
    );
  }
}
