import 'package:physical_treatment_and_health_support_system/model/entity/treatment_plan.dart';

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

/// What the patient's own history says to do next (hybrid-3.0): [start]
/// without history, [progress] after a completed plan, [ease] after repeated
/// attempts that did not pass or a possible fall, [stay] otherwise.
enum NextStep {
  start('START'),
  progress('PROGRESS'),
  stay('STAY'),
  ease('EASE');

  final String wire;
  const NextStep(this.wire);
  static NextStep fromWire(String? s) =>
      values.firstWhere((v) => v.wire == s, orElse: () => start);
}

/// Result of /recommend: up to three plans, best first, each carrying its
/// suitability score (FR500_06, FR500_07).
class Recommendation {
  final RecommendationStatus status;
  final List<TreatmentPlan> plans;
  final String modelVersion;
  final NextStep nextStep;

  /// One sentence for the patient explaining [nextStep]; empty for [NextStep.start].
  final String nextStepReason;

  const Recommendation({
    required this.status,
    required this.plans,
    required this.modelVersion,
    this.nextStep = NextStep.start,
    this.nextStepReason = '',
  });
}
