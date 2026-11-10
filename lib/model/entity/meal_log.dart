import 'package:physical_treatment_and_health_support_system/core/utils/id_utils.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/enums.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/food_item.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/food_recognition_details.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/suitability_verdict.dart';

/// One food inside a logged meal, with its portion and the nutrients for that portion (Table 4.50).
class MealItem {
  final String mealItemId;
  final String? mealId;
  final FoodItem food;
  final double portionSizeG;

  /// Stored so a later catalogue correction cannot rewrite logged history.
  final double energyKcal;
  final double carbG;
  final double proteinG;
  final double fatG;
  final double sodiumMg;
  final double sugarG;

  /// Set when the patient replaced the identified food (FR700_006).
  final bool isUserCorrected;

  /// Recognition confidence of this food, when it came from a photo.
  final double? confidence;

  /// Other likely foods from the recogniser, for a one-tap correction (FR700_006).
  final List<String> candidateKeys;

  /// One verdict per applicable condition and restriction (FR700_024).
  final List<SuitabilityVerdict> verdicts;
  final FoodRecognitionDetails? recognitionDetails;

  const MealItem({
    required this.mealItemId,
    this.mealId,
    required this.food,
    required this.portionSizeG,
    required this.energyKcal,
    required this.carbG,
    required this.proteinG,
    required this.fatG,
    required this.sodiumMg,
    required this.sugarG,
    this.isUserCorrected = false,
    this.confidence,
    this.candidateKeys = const [],
    this.verdicts = const [],
    this.recognitionDetails,
  });

  /// A new item at [grams] (default: one standard serving, UC800 C8).
  factory MealItem.of(
    FoodItem food, {
    double? grams,
    double? confidence,
    List<String> candidateKeys = const [],
    bool corrected = false,
    FoodRecognitionDetails? recognitionDetails,
  }) {
    final g = grams ?? food.baseServingG;
    final n = food.nutrientsFor(g);
    return MealItem(
      mealItemId: newId(),
      food: food,
      portionSizeG: g,
      energyKcal: n.energyKcal,
      carbG: n.carbG,
      proteinG: n.proteinG,
      fatG: n.fatG,
      sodiumMg: n.sodiumMg,
      sugarG: n.sugarG,
      isUserCorrected: corrected,
      confidence: confidence,
      candidateKeys: candidateKeys,
      recognitionDetails: recognitionDetails,
    );
  }

  Nutrients get nutrients => Nutrients(
    energyKcal: energyKcal,
    carbG: carbG,
    proteinG: proteinG,
    fatG: fatG,
    sodiumMg: sodiumMg,
    sugarG: sugarG,
  );

  /// Duplicate rows are merged only within this meal; verdicts are reassessed by its ViewModel.
  static List<MealItem> mergeDuplicates(Iterable<MealItem> items) {
    final rows = <String, MealItem>{};
    for (final item in items) {
      final previous = rows[item.food.foodId];
      if (previous == null) {
        rows[item.food.foodId] = item;
      } else {
        final scaled = previous.scaleTo(previous.portionSizeG + item.portionSizeG);
        rows[item.food.foodId] = MealItem(
          mealItemId: previous.mealItemId,
          mealId: previous.mealId,
          food: previous.food,
          portionSizeG: scaled.portionSizeG,
          energyKcal: scaled.energyKcal,
          carbG: scaled.carbG,
          proteinG: scaled.proteinG,
          fatG: scaled.fatG,
          sodiumMg: scaled.sodiumMg,
          sugarG: scaled.sugarG,
          isUserCorrected: previous.isUserCorrected || item.isUserCorrected,
          confidence: previous.confidence,
          candidateKeys: {...previous.candidateKeys, ...item.candidateKeys}.toList(),
          // The old visual count no longer describes the combined, manually changed amount.
          recognitionDetails: null,
        );
      }
    }
    return rows.values.toList();
  }

  /// Recomputes every nutrient for a new portion (FR700_011).
  MealItem scaleTo(double grams) {
    final n = food.nutrientsFor(grams);
    return MealItem(
      mealItemId: mealItemId,
      mealId: mealId,
      food: food,
      portionSizeG: grams,
      energyKcal: n.energyKcal,
      carbG: n.carbG,
      proteinG: n.proteinG,
      fatG: n.fatG,
      sodiumMg: n.sodiumMg,
      sugarG: n.sugarG,
      isUserCorrected: isUserCorrected,
      confidence: confidence,
      candidateKeys: candidateKeys,
      recognitionDetails: recognitionDetails?.reviewed(grams: grams),
    );
  }

  /// The most restrictive verdict, which is the one displayed (FR700_028).
  Verdict worstVerdict() => verdicts.fold(Verdict.suitable, (w, v) => v.verdict.index > w.index ? v.verdict : w);

  MealItem withVerdicts(List<SuitabilityVerdict> vs) => MealItem(
    mealItemId: mealItemId,
    mealId: mealId,
    food: food,
    portionSizeG: portionSizeG,
    energyKcal: energyKcal,
    carbG: carbG,
    proteinG: proteinG,
    fatG: fatG,
    sodiumMg: sodiumMg,
    sugarG: sugarG,
    isUserCorrected: isUserCorrected,
    confidence: confidence,
    candidateKeys: candidateKeys,
    verdicts: vs,
    recognitionDetails: recognitionDetails,
  );

  MealItem withRecognitionDetails(FoodRecognitionDetails? details) => MealItem(
    mealItemId: mealItemId,
    mealId: mealId,
    food: food,
    portionSizeG: portionSizeG,
    energyKcal: energyKcal,
    carbG: carbG,
    proteinG: proteinG,
    fatG: fatG,
    sodiumMg: sodiumMg,
    sugarG: sugarG,
    isUserCorrected: isUserCorrected,
    confidence: confidence,
    candidateKeys: candidateKeys,
    verdicts: verdicts,
    recognitionDetails: details,
  );

  MealItem withMeal(String mealId) => MealItem(
    mealItemId: mealItemId,
    mealId: mealId,
    food: food,
    portionSizeG: portionSizeG,
    energyKcal: energyKcal,
    carbG: carbG,
    proteinG: proteinG,
    fatG: fatG,
    sodiumMg: sodiumMg,
    sugarG: sugarG,
    isUserCorrected: isUserCorrected,
    confidence: confidence,
    candidateKeys: candidateKeys,
    verdicts: [for (final v in verdicts) v.copyWith(mealItemId: mealItemId)],
    recognitionDetails: recognitionDetails,
  );

  Map<String, dynamic> toJson() => {
    'meal_item_id': mealItemId,
    'meal_id': mealId,
    'food_id': food.foodId,
    'portion_size_g': portionSizeG,
    'energy_kcal': energyKcal,
    'carb_g': carbG,
    'protein_g': proteinG,
    'fat_g': fatG,
    'sodium_mg': sodiumMg,
    'sugar_g': sugarG,
    'is_user_corrected': isUserCorrected,
    if (recognitionDetails != null) 'recognition_details': recognitionDetails!.toJson(),
  };

  factory MealItem.fromJson(Map<String, dynamic> j, FoodItem food, {List<SuitabilityVerdict> verdicts = const []}) {
    double d(String k) => ((j[k] ?? 0) as num).toDouble();
    return MealItem(
      mealItemId: j['meal_item_id'] as String,
      mealId: j['meal_id'] as String?,
      food: food,
      portionSizeG: d('portion_size_g'),
      energyKcal: d('energy_kcal'),
      carbG: d('carb_g'),
      proteinG: d('protein_g'),
      fatG: d('fat_g'),
      sodiumMg: d('sodium_mg'),
      sugarG: d('sugar_g'),
      isUserCorrected: (j['is_user_corrected'] ?? false) as bool,
      verdicts: verdicts,
      recognitionDetails: j['recognition_details'] is Map
          ? FoodRecognitionDetails.fromJson(Map<String, dynamic>.from(j['recognition_details'] as Map))
          : null,
    );
  }
}

/// One meal the patient recorded, from a photograph or by hand (Table 4.51).
class MealLog {
  /// Below this the patient is prompted for manual entry (UC800 C6, FR700_005).
  static const double confidenceFloor = 0.60;

  final String mealId;
  final String accountId;
  final String? plannedMealId;
  final MealSlot mealType;
  final EntryMethod entryMethod;

  /// Path of the photograph in storage. Written only after the patient confirms the result
  /// (FR700_009) and deleted with the meal (FR700_016).
  final String? imageUri;
  final double? recognitionConfidence;
  final String? modelVersion;
  final DateTime consumedAt;
  final List<MealItem> items;

  const MealLog({
    required this.mealId,
    required this.accountId,
    this.plannedMealId,
    required this.mealType,
    required this.entryMethod,
    this.imageUri,
    this.recognitionConfidence,
    this.modelVersion,
    required this.consumedAt,
    this.items = const [],
  });

  Nutrients get totals => Nutrients.sum(items.map((i) => i.nutrients)).rounded();
  double get totalEnergyKcal => totals.energyKcal;
  double get totalSodiumMg => totals.sodiumMg;
  double get totalSugarG => totals.sugarG;

  /// True when recognition confidence is below 0.60 (FR700_005).
  bool needsManualEntry() => entryMethod == EntryMethod.recognition && (recognitionConfidence ?? 0) < confidenceFloor;

  /// The most restrictive verdict over the items.
  Verdict worstVerdict() =>
      items.fold(Verdict.suitable, (w, i) => i.worstVerdict().index > w.index ? i.worstVerdict() : w);

  MealLog copyWith({
    String? accountId,
    List<MealItem>? items,
    MealSlot? mealType,
    String? imageUri,
    String? plannedMealId,
    DateTime? consumedAt,
  }) => MealLog(
    mealId: mealId,
    accountId: accountId ?? this.accountId,
    plannedMealId: plannedMealId ?? this.plannedMealId,
    mealType: mealType ?? this.mealType,
    entryMethod: entryMethod,
    imageUri: imageUri ?? this.imageUri,
    recognitionConfidence: recognitionConfidence,
    modelVersion: modelVersion,
    consumedAt: consumedAt ?? this.consumedAt,
    items: items ?? this.items,
  );

  /// Adds an item and refreshes the totals.
  MealLog addItem(MealItem i) => copyWith(items: MealItem.mergeDuplicates([...items, i]));

  /// Removes an item and refreshes the totals.
  MealLog removeItem(MealItem i) => copyWith(items: items.where((x) => x.mealItemId != i.mealItemId).toList());

  /// Totals are computed from the items, so re-summing is a no-op kept for the class diagram.
  MealLog recalculateTotals() => this;

  Map<String, dynamic> toJson() {
    final t = totals;
    return {
      'meal_id': mealId,
      'account_id': accountId,
      'planned_meal_id': plannedMealId,
      'meal_type': mealType.db,
      'entry_method': entryMethod.db,
      'image_uri': imageUri,
      'recognition_confidence': recognitionConfidence,
      'model_version': modelVersion,
      'total_energy_kcal': t.energyKcal,
      'total_sodium_mg': t.sodiumMg,
      'total_sugar_g': t.sugarG,
      'consumed_at': consumedAt.toUtc().toIso8601String(),
    };
  }

  factory MealLog.fromJson(Map<String, dynamic> j, List<MealItem> items) => MealLog(
    mealId: j['meal_id'] as String,
    accountId: j['account_id'] as String,
    plannedMealId: j['planned_meal_id'] as String?,
    mealType: MealSlot.fromDb(j['meal_type'] as String?),
    entryMethod: EntryMethod.fromDb(j['entry_method'] as String?),
    imageUri: j['image_uri'] as String?,
    recognitionConfidence: (j['recognition_confidence'] as num?)?.toDouble(),
    modelVersion: j['model_version'] as String?,
    consumedAt: DateTime.parse(j['consumed_at'] as String).toLocal(),
    items: items,
  );
}
