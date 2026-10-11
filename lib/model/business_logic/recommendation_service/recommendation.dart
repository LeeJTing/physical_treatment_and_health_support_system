import 'package:physical_treatment_and_health_support_system/core/constants/app_constants.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/health_profile.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/treatment_plan.dart';

/// Why no plan may be generated for this patient at all (Terms of Use,
/// section 2): plans stop at [AppConstants.planAgeLimit]. Everything else in
/// the app stays available.
enum PlanRestriction {
  age65Plus('AGE_65_PLUS'),

  /// A condition that needs a doctor's OK was answered "No" in the health
  /// profile (11 Oct): no new plan until the answer changes. App only.
  clearanceNeeded('CLEARANCE_NEEDED');

  final String wire;
  const PlanRestriction(this.wire);

  static PlanRestriction? fromWire(String? s) =>
      values.where((v) => v.wire == s).firstOrNull;

  /// The restriction for a profile [age]; none when the age is not known.
  static PlanRestriction? forAge(int? age) =>
      age != null && age >= AppConstants.planAgeLimit ? age65Plus : null;

  /// The age limit first, then a condition waiting for a doctor's OK.
  static PlanRestriction? forProfile(HealthProfile? p) =>
      forAge(p?.age) ??
      (p != null && p.conditions.any((c) => c.blocksPlans)
          ? clearanceNeeded
          : null);
}

/// One reason a plan was or was not recommended, as the server words it for
/// the patient, with the keys of the papers behind the rule
/// (EvidenceSources); no keys = our own design rule ("App safety rule").
class PlanReason {
  final String code;
  final String text;
  final List<String> sources;

  const PlanReason(this.code, this.text, [this.sources = const []]);

  factory PlanReason.fromJson(Map<String, dynamic> j) => PlanReason(
    j['code'] as String? ?? '',
    j['text'] as String? ?? '',
    [for (final s in (j['sources'] as List?) ?? const []) s as String],
  );

  static List<PlanReason> listFrom(Object? j) => [
    for (final r in (j as List?) ?? const [])
      PlanReason.fromJson(r as Map<String, dynamic>),
  ];
}

/// A catalogue plan the recommender left out, and why ("Why not other plans").
class ExcludedPlan {
  final TreatmentPlan plan;
  final List<PlanReason> why;

  const ExcludedPlan(this.plan, this.why);
}

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

  /// "Why this plan", by planId (11 Oct).
  final Map<String, List<PlanReason>> why;

  /// "Why not other plans" (11 Oct).
  final List<ExcludedPlan> excluded;

  /// Set when no plan may be generated at all (aged 65 and over).
  final PlanRestriction? restriction;

  const Recommendation({
    required this.status,
    required this.plans,
    required this.modelVersion,
    this.nextStep = NextStep.start,
    this.nextStepReason = '',
    this.why = const {},
    this.excluded = const [],
    this.restriction,
  });

  /// The answer for a restricted patient, decided on the phone without asking
  /// the server.
  const Recommendation.restricted(PlanRestriction this.restriction)
    : status = RecommendationStatus.none,
      plans = const [],
      modelVersion = 'local',
      nextStep = NextStep.start,
      nextStepReason = '',
      why = const {},
      excluded = const [];
}
