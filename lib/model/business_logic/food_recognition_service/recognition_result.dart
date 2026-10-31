import 'package:physical_treatment_and_health_support_system/model/entity/food_item.dart';

/// One food the recogniser found in the photo, already resolved onto the catalogue.
class RecognisedFood {
  final FoodItem food;
  final double confidence;

  /// The main food of the photo (false for a drink or side found in one corner).
  final bool primary;

  /// The next most likely foods, for a one-tap correction (FR700_006).
  final List<FoodItem> candidates;

  const RecognisedFood({
    required this.food,
    required this.confidence,
    this.primary = true,
    this.candidates = const [],
  });
}

/// What /recognise returned for one photo (UC800 BF-9, BF-10).
class RecognitionResult {
  final List<RecognisedFood> items;

  /// Confidence of the main food, calibrated so 0.60 means what UC800 C6 says.
  final double confidence;
  final bool isFood;

  /// Version of the model that produced the result (FR700_008).
  final String modelVersion;
  final int elapsedMs;

  const RecognitionResult({
    required this.items,
    required this.confidence,
    required this.isFood,
    required this.modelVersion,
    this.elapsedMs = 0,
  });

  /// Below 0.60, or not a photo of food: the patient enters the food instead (FR700_005).
  bool get needsManualEntry => !isFood || confidence < 0.60 || items.isEmpty;
}
