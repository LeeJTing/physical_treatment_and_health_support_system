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

/// The nutrients the condition rules and the plan targets use besides [Nutrients], for a portion:
/// saturated fat (heart disease, stroke), fibre (Parkinson's, MS, diabetes), potassium and
/// phosphorus (kidney disease), calcium (osteoporosis), caffeine (pregnancy).
class FoodExtras {
  final double satFatG;
  final double fibreG;
  final double potassiumMg;
  final double phosphorusMg;
  final double calciumMg;
  final double caffeineMg;

  const FoodExtras({
    this.satFatG = 0,
    this.fibreG = 0,
    this.potassiumMg = 0,
    this.phosphorusMg = 0,
    this.calciumMg = 0,
    this.caffeineMg = 0,
  });

  static const zero = FoodExtras();

  FoodExtras operator +(FoodExtras o) => FoodExtras(
    satFatG: satFatG + o.satFatG,
    fibreG: fibreG + o.fibreG,
    potassiumMg: potassiumMg + o.potassiumMg,
    phosphorusMg: phosphorusMg + o.phosphorusMg,
    calciumMg: calciumMg + o.calciumMg,
    caffeineMg: caffeineMg + o.caffeineMg,
  );

  /// Value by the server's key (sat_fat_g, fibre_g, potassium_mg, phosphorus_mg, calcium_mg, caffeine_mg).
  double operator [](String key) => switch (key) {
    'sat_fat_g' => satFatG,
    'fibre_g' => fibreG,
    'potassium_mg' => potassiumMg,
    'phosphorus_mg' => phosphorusMg,
    'calcium_mg' => calciumMg,
    'caffeine_mg' => caffeineMg,
    _ => 0,
  };
}

/// Nutrition catalogue (Table 4.48). Values are per 100 g so any portion scales from one row.
/// [foodKey] is the label the food recogniser and the planner use for the food (food_item.food_key).
/// Since food-catalogue-2.0 the values come from USDA FoodData Central ingredients and a standard
/// recipe of the food, replaced by Malaysian laboratory analyses where the food was analysed
/// ([dataSource] 'lab').
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

  final double totalSugarGPer100g;
  final double satFatGPer100g;
  final double fibreGPer100g;
  final double potassiumMgPer100g;
  final double phosphorusMgPer100g;
  final double calciumMgPer100g;
  final double caffeineMgPer100g;

  /// Needs two hands to eat (bones, shells, whole fish, knife and fork): left out of plans for a
  /// patient with an arm limitation. [twoHandsReason] says why.
  final bool needsTwoHands;
  final String? twoHandsReason;

  /// Why the food is not advised in pregnancy (raw fish, undercooked egg), or null.
  final String? pregnancyCaution;

  /// 'lab' when at least one value is a laboratory analysis, otherwise 'recipe'.
  final String dataSource;

  /// The food names its recipe contains (food_restriction), e.g. ONION, PEANUT, PRAWN.
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
    this.totalSugarGPer100g = 0,
    this.satFatGPer100g = 0,
    this.fibreGPer100g = 0,
    this.potassiumMgPer100g = 0,
    this.phosphorusMgPer100g = 0,
    this.calciumMgPer100g = 0,
    this.caffeineMgPer100g = 0,
    this.needsTwoHands = false,
    this.twoHandsReason,
    this.pregnancyCaution,
    this.dataSource = 'recipe',
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

  /// The extra nutrients for a portion, one decimal.
  FoodExtras extrasFor(double grams) {
    final f = grams / 100;
    double r(double x) => (x * f * 10).roundToDouble() / 10;
    return FoodExtras(
      satFatG: r(satFatGPer100g),
      fibreG: r(fibreGPer100g),
      potassiumMg: r(potassiumMgPer100g),
      phosphorusMg: r(phosphorusMgPer100g),
      calciumMg: r(calciumMgPer100g),
      caffeineMg: r(caffeineMgPer100g),
    );
  }

  /// Whether this food contains the declared food (an old diet label counts as its food names).
  bool breaches(DietaryRestriction r) =>
      DietaryRestriction.expandCodes([r.restrictionCode]).any(restrictionCodes.contains);

  /// Whether the food collides with anything the patient declared.
  bool breachesAny(List<DietaryRestriction> rs) => rs.any(breaches);

  /// The declared food names this food contains.
  List<String> containsOf(Iterable<String> declaredCodes) =>
      DietaryRestriction.expandCodes(declaredCodes).where(restrictionCodes.contains).toList();

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
      totalSugarGPer100g: d('total_sugar_g_per_100g'),
      satFatGPer100g: d('sat_fat_g_per_100g'),
      fibreGPer100g: d('fibre_g_per_100g'),
      potassiumMgPer100g: d('potassium_mg_per_100g'),
      phosphorusMgPer100g: d('phosphorus_mg_per_100g'),
      calciumMgPer100g: d('calcium_mg_per_100g'),
      caffeineMgPer100g: d('caffeine_mg_per_100g'),
      needsTwoHands: j['needs_two_hands'] as bool? ?? false,
      twoHandsReason: j['two_hands_reason'] as String?,
      pregnancyCaution: j['pregnancy_caution'] as String?,
      dataSource: (j['data_source'] ?? 'recipe') as String,
      restrictionCodes: ((j['restrictions'] as List?) ?? const []).cast<String>(),
      planRole: (j['plan_role'] ?? 'meal') as String,
      mealSlots: ((j['meal_slots'] as List?) ?? const []).cast<String>(),
    );
  }
}
