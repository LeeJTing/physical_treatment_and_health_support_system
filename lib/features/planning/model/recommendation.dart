import 'package:physical_treatment_and_health_support_system/data/models/treatment_plan.dart';

/// How many plans survived the safety filter (FR500_14, FR500_15).
enum RecommendationStatus {
  ok('OK'),
  onlyOne('ONLY_ONE'),
  none('NONE');

  final String wire;
  const RecommendationStatus(this.wire);
  static RecommendationStatus fromWire(String? s) =>
      values.firstWhere((v) => v.wire == s, orElse: () => none);
}

/// Result of /recommend: up to three plans, best first, each carrying its
/// suitability score (FR500_06, FR500_07).
class Recommendation {
  final RecommendationStatus status;
  final List<TreatmentPlan> plans;
  final String modelVersion;

  const Recommendation({
    required this.status,
    required this.plans,
    required this.modelVersion,
  });
}
