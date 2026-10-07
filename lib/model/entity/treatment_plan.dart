import 'package:physical_treatment_and_health_support_system/model/entity/enums.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/exercise.dart';

/// One exercise inside a programme, in order (Table 4.17).
class PlanExercise {
  final String planId;
  final Exercise exercise;
  final int sequenceOrder;
  final int prescribedRepetitions;
  final int prescribedDurationSec;

  const PlanExercise({
    required this.planId,
    required this.exercise,
    required this.sequenceOrder,
    required this.prescribedRepetitions,
    required this.prescribedDurationSec,
  });

  String get exerciseId => exercise.exerciseId;

  /// Reads a plan_exercise row joined with its exercise: {..., exercise: {...}}.
  factory PlanExercise.fromJson(Map<String, dynamic> j) => PlanExercise(
    planId: j['plan_id'] as String,
    exercise: Exercise.fromJson(j['exercise'] as Map<String, dynamic>),
    sequenceOrder: (j['sequence_order'] as num).toInt(),
    prescribedRepetitions: (j['prescribed_repetitions'] as num).toInt(),
    prescribedDurationSec: (j['prescribed_duration_sec'] as num).toInt(),
  );

  Map<String, dynamic> toJson() => {
    'plan_id': planId,
    'exercise_id': exercise.exerciseId,
    'sequence_order': sequenceOrder,
    'prescribed_repetitions': prescribedRepetitions,
    'prescribed_duration_sec': prescribedDurationSec,
  };
}

/// Catalogue programme the recommender ranks (Table 4.18).
class TreatmentPlan {
  final String planId;
  final String planName;
  final String aim;
  final String targetBodyArea;
  final RecoveryStage recoveryStage;
  final MobilityLevel mobilityLevel;
  final int frequencyPerWeek;

  /// STRENGTH, MOBILITY, BALANCE, PAIN_RELIEF or ENDURANCE. Extra column, see plan open issue 1.
  final String? goal;
  final List<PlanExercise> exercises;

  /// Filled in by the recommender for display only (FR500_06); not a column.
  final double? suitabilityScore;

  const TreatmentPlan({
    required this.planId,
    required this.planName,
    required this.aim,
    required this.targetBodyArea,
    required this.recoveryStage,
    required this.mobilityLevel,
    required this.frequencyPerWeek,
    this.goal,
    this.exercises = const [],
    this.suitabilityScore,
  });

  /// The pathway in sequence (FR300_02).
  List<PlanExercise> orderedExercises() =>
      [...exercises]
        ..sort((a, b) => a.sequenceOrder.compareTo(b.sequenceOrder));

  int get totalDurationSec =>
      exercises.fold(0, (s, e) => s + e.prescribedDurationSec);

  TreatmentPlan withScore(double score) => TreatmentPlan(
    planId: planId,
    planName: planName,
    aim: aim,
    targetBodyArea: targetBodyArea,
    recoveryStage: recoveryStage,
    mobilityLevel: mobilityLevel,
    frequencyPerWeek: frequencyPerWeek,
    goal: goal,
    exercises: exercises,
    suitabilityScore: score,
  );

  factory TreatmentPlan.fromJson(Map<String, dynamic> j) => TreatmentPlan(
    planId: j['plan_id'] as String,
    planName: j['plan_name'] as String,
    aim: j['aim'] as String,
    targetBodyArea: j['target_body_area'] as String,
    recoveryStage: RecoveryStage.fromDb(j['recovery_stage'] as String?),
    mobilityLevel: MobilityLevel.fromDb(j['mobility_level'] as String?),
    frequencyPerWeek: (j['frequency_per_week'] as num).toInt(),
    goal: j['goal'] as String?,
    exercises: ((j['plan_exercise'] as List?) ?? const [])
        .map((e) => PlanExercise.fromJson(e as Map<String, dynamic>))
        .toList(),
    suitabilityScore: (j['suitability_score'] as num?)?.toDouble(),
  );

  Map<String, dynamic> toJson() => {
    'plan_id': planId,
    'plan_name': planName,
    'aim': aim,
    'target_body_area': targetBodyArea,
    'recovery_stage': recoveryStage.db,
    'mobility_level': mobilityLevel.db,
    'frequency_per_week': frequencyPerWeek,
    'goal': goal,
    'plan_exercise': exercises
        .map((e) => {...e.toJson(), 'exercise': e.exercise.toJson()})
        .toList(),
  };
}
