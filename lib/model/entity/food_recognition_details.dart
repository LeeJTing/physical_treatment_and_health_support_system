/// Review metadata only: nutrient values always come from the catalogue and confirmed grams.
class FoodRecognitionDetails {
  final int? count;
  final String? unit;
  final double? unitWeightG;
  final bool estimated;
  final bool confirmed;
  final bool modelEstimate;
  final List<List<double>> boxes;

  const FoodRecognitionDetails({
    this.count,
    this.unit,
    this.unitWeightG,
    this.estimated = true,
    this.confirmed = false,
    this.modelEstimate = false,
    this.boxes = const [],
  });

  factory FoodRecognitionDetails.fromJson(Map<String, dynamic> j) {
    final c = j['count'];
    final w = j['unit_weight_g'];
    final boxes = <List<double>>[];
    for (final b in (j['boxes'] is List ? j['boxes'] as List : const [])) {
      if (b is! List ||
          b.length != 4 ||
          b.any((v) => v is! num || !v.isFinite || v < 0 || v > 1)) {
        continue;
      }
      final v = b.cast<num>().map((n) => n.toDouble()).toList();
      if (v[0] < v[2] && v[1] < v[3]) boxes.add(v);
    }
    return FoodRecognitionDetails(
      count: c is int && c > 0 && c <= 100 ? c : null,
      unit: const ['whole', 'piece', 'serving'].contains(j['count_unit'])
          ? j['count_unit'] as String
          : null,
      unitWeightG: w is num && w.isFinite && w > 0 && w <= 1000
          ? w.toDouble()
          : null,
      estimated: j['portion_estimated'] != false,
      confirmed: j['confirmed'] == true,
      modelEstimate: j['confidence_kind'] == 'model_estimate',
      boxes: boxes,
    );
  }

  String? get countLabel {
    final c = count;
    if (c == null || unit == null) return null;
    return '$c ${switch (unit) {
      'whole' => c == 1 ? 'whole item' : 'whole items',
      'piece' => c == 1 ? 'piece' : 'pieces',
      _ => c == 1 ? 'serving' : 'servings',
    }}';
  }

  FoodRecognitionDetails reviewed({int? count, double? grams}) =>
      FoodRecognitionDetails(
        count: count ?? this.count,
        unit: unit,
        unitWeightG: grams != null && (count ?? this.count) != null
            ? grams / (count ?? this.count)!
            : unitWeightG,
        estimated: true,
        confirmed: true,
        modelEstimate: modelEstimate,
        boxes: boxes,
      );

  Map<String, dynamic> toJson() => {
    'count': count,
    'count_unit': unit,
    'unit_weight_g': unitWeightG,
    'portion_estimated': estimated,
    'confirmed': confirmed,
    'confidence_kind': modelEstimate ? 'model_estimate' : 'calibrated',
    'boxes': boxes,
  };
}
