import 'package:physical_treatment_and_health_support_system/model/entity/enums.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/food_item.dart';

/// Why one logged item is or is not suitable for this patient (Table 4.53). Raised either by a
/// health condition, when a nutrient limit is exceeded, or by a dietary restriction, when the food is
/// one the patient cannot eat at all (FR700_024 to FR700_028).
class SuitabilityVerdict {
  final String verdictId;
  final String? mealItemId;
  final Verdict verdict;

  /// Plain-language reason naming the nutrient or allergen and the amount by which any limit is
  /// exceeded (FR700_025, FR700_026).
  final String reasonText;

  /// Exactly one of [conditionId] / [restrictionId] raised it (suitability_verdict CHECK). A verdict
  /// against the general limits (no condition declared) keeps the condition null and is not stored.
  final int? conditionId;
  final int? restrictionId;
  final String? conditionCode;
  final String? restrictionCode;

  /// sodium_mg or sugar_g for a nutrient verdict.
  final String? nutrient;
  final double? limit;
  final double? value;

  /// Closest substitute that breaks no limit and no restriction (FR700_020, FR700_027).
  final FoodItem? suggested;

  const SuitabilityVerdict({
    required this.verdictId,
    this.mealItemId,
    required this.verdict,
    required this.reasonText,
    this.conditionId,
    this.restrictionId,
    this.conditionCode,
    this.restrictionCode,
    this.nutrient,
    this.limit,
    this.value,
    this.suggested,
  });

  /// True for Not Suitable, which also excludes the food from generated plans (FR700_033).
  bool isBlocking() => verdict == Verdict.notSuitable;

  /// How far the limit was exceeded (FR700_026); 0 when within it.
  double excessAmount() {
    final l = limit, v = value;
    if (l == null || v == null) return 0;
    return v > l ? v - l : 0;
  }

  /// Names the nutrient or allergen and the condition it relates to (FR700_025).
  String reason() => reasonText;

  FoodItem? suggestAlternative() => suggested;

  /// Stored only when a condition or a restriction raised it (the table's CHECK).
  bool get isStorable => conditionId != null || restrictionId != null;

  SuitabilityVerdict copyWith({String? mealItemId, FoodItem? suggested}) =>
      SuitabilityVerdict(
        verdictId: verdictId,
        mealItemId: mealItemId ?? this.mealItemId,
        verdict: verdict,
        reasonText: reasonText,
        conditionId: conditionId,
        restrictionId: restrictionId,
        conditionCode: conditionCode,
        restrictionCode: restrictionCode,
        nutrient: nutrient,
        limit: limit,
        value: value,
        suggested: suggested ?? this.suggested,
      );

  Map<String, dynamic> toJson() => {
    'verdict_id': verdictId,
    'meal_item_id': mealItemId,
    'condition_id': conditionId,
    'restriction_id': restrictionId,
    'verdict': verdict.db,
    'reason_text': reasonText,
    'suggested_food_id': suggested?.foodId,
  };

  factory SuitabilityVerdict.fromJson(Map<String, dynamic> j) =>
      SuitabilityVerdict(
        verdictId: j['verdict_id'] as String,
        mealItemId: j['meal_item_id'] as String?,
        verdict: Verdict.fromDb(j['verdict'] as String?),
        reasonText: j['reason_text'] as String,
        conditionId: (j['condition_id'] as num?)?.toInt(),
        restrictionId: (j['restriction_id'] as num?)?.toInt(),
      );
}
