import 'package:physical_treatment_and_health_support_system/model/entity/enums.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/exercise.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/treatment_plan.dart';

/// A programme assigned to one patient, with its progress (Table 4.16).
class PatientTreatmentPlan {
  final String patientPlanId;
  final String accountId;
  final TreatmentPlan plan;
  final double? suitabilityScore;
  final double progressPercentage;
  final PlanStatus status;
  final DateTime selectedAt;

  /// Number of pathway stages completed. Derived from progress so it is not
  /// stored twice.
  int get completedStages => (progressPercentage / 100 * plan.exercises.length)
      .round()
      .clamp(0, plan.exercises.length);

  const PatientTreatmentPlan({
    required this.patientPlanId,
    required this.accountId,
    required this.plan,
    this.suitabilityScore,
    this.progressPercentage = 0,
    this.status = PlanStatus.active,
    required this.selectedAt,
  });

  /// The exercise at the patient's position in the pathway, or null when finished.
  Exercise? currentExercise() {
    final ordered = plan.orderedExercises();
    return completedStages < ordered.length
        ? ordered[completedStages].exercise
        : null;
  }

  PlanExercise? currentStage() {
    final ordered = plan.orderedExercises();
    return completedStages < ordered.length ? ordered[completedStages] : null;
  }

  /// Moves to the next stage after a completed session (FR300_11).
  PatientTreatmentPlan advance() {
    final total = plan.exercises.length;
    if (total == 0) return this;
    final done = (completedStages + 1).clamp(0, total);
    final pct = double.parse((done / total * 100).toStringAsFixed(2));
    return PatientTreatmentPlan(
      patientPlanId: patientPlanId,
      accountId: accountId,
      plan: plan,
      suitabilityScore: suitabilityScore,
      progressPercentage: pct,
      status: done == total ? PlanStatus.completed : status,
      selectedAt: selectedAt,
    );
  }

  double progress() => progressPercentage;
  bool isActive() => status == PlanStatus.active;

  /// Row for patient_plan.
  Map<String, dynamic> toJson() => {
    'patient_plan_id': patientPlanId,
    'account_id': accountId,
    'plan_id': plan.planId,
    'suitability_score': suitabilityScore,
    'progress_percentage': progressPercentage,
    'status': status.db,
    'selected_at': selectedAt.toIso8601String(),
  };

  /// Reads a patient_plan row joined with its treatment_plan.
  factory PatientTreatmentPlan.fromJson(Map<String, dynamic> j) =>
      PatientTreatmentPlan(
        patientPlanId: j['patient_plan_id'] as String,
        accountId: j['account_id'] as String,
        plan: TreatmentPlan.fromJson(
          j['treatment_plan'] as Map<String, dynamic>,
        ),
        suitabilityScore: (j['suitability_score'] as num?)?.toDouble(),
        progressPercentage: (j['progress_percentage'] as num?)?.toDouble() ?? 0,
        status: PlanStatus.fromDb(j['status'] as String?),
        selectedAt: DateTime.parse(j['selected_at'] as String),
      );
}
