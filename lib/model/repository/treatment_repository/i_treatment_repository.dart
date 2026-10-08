import 'package:physical_treatment_and_health_support_system/model/result.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/chat_message.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/exercise_session.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/patient_treatment_plan.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/treatment_plan.dart';

/// One anonymised cohort cell from the `plan_outcome_stats()` RPC: how patients
/// with this risk level and age band did on a plan. Evidence for the
/// collaborative part of the hybrid recommender (FR500_05). A record, not a
/// class, because the Chapter 4 diagram has no aggregate class (PROJECT_STATE §11).
typedef PlanOutcome = ({
  String planId,
  String riskLevel,
  String ageBand,
  int patients,
  double completionRate,
  double? meanAccuracy,
  double? meanProgress,
});

/// Contract for treatment plans, assignments and exercise sessions (Table 4.60).
abstract interface class ITreatmentRepository {
  /// Anonymised per-plan outcomes of other patients (cells of 5 or more), for
  /// the collaborative score. An empty list or a failure means cold start.
  Future<Result<List<PlanOutcome>>> getPlanOutcomes();

  /// The ACTIVE plan with its pathway, or null when none is assigned.
  Future<Result<PatientTreatmentPlan?>> getActivePlan(String accountId);

  /// Every catalogue plan with its ordered exercises (FR500_04).
  Future<Result<List<TreatmentPlan>>> getCatalogue();

  /// Saves the selected plan and abandons any previous ACTIVE one (FR500_09).
  Future<Result<void>> assignPlan(PatientTreatmentPlan p);

  /// Writes the attempt and, when given, the advanced plan progress in one
  /// transaction (FR300_21, ASR_04).
  Future<Result<void>> saveSession(
    ExerciseSession s, {
    PatientTreatmentPlan? advancedPlan,
  });

  /// Every attempt recorded for an assignment, oldest first, for the pathway's posture
  /// badges (FR300_02, FR300_10).
  Future<Result<List<ExerciseSession>>> getSessions(String patientPlanId);

  /// Stops the plan: status ABANDONED, kept for history (UI Design, Physical Treatment Page).
  Future<Result<void>> endPlan(PatientTreatmentPlan p);

  /// Stores one chatbot turn (FR500_17-22). Chat belongs to M500, so it sits
  /// with the treatment data rather than adding a ninth interface.
  Future<Result<void>> saveChatMessage(ChatMessage m);
}
