import 'package:physical_treatment_and_health_support_system/model/result.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/chat_message.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/chat_report.dart';
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

  /// Every ACTIVE plan with its pathway, oldest first. A patient may follow
  /// several plans at once (PlanRules; PROJECT_STATE section 11).
  Future<Result<List<PatientTreatmentPlan>>> getActivePlans(String accountId);

  /// Every plan the patient has had (ACTIVE, COMPLETED, ABANDONED), oldest
  /// first: the history the recommender learns the next step from (hybrid-3.0).
  Future<Result<List<PatientTreatmentPlan>>> getPlanHistory(String accountId);

  /// The most recently selected ACTIVE plan, or null when none is assigned.
  Future<Result<PatientTreatmentPlan?>> getActivePlan(String accountId);

  /// Every catalogue plan with its ordered exercises (FR500_04).
  Future<Result<List<TreatmentPlan>>> getCatalogue();

  /// Saves the selected plan (FR500_09) and abandons only the assignments in
  /// [replacing]; other ACTIVE plans keep running.
  Future<Result<void>> assignPlan(
    PatientTreatmentPlan p, {
    List<String> replacing = const [],
  });

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

  /// Stores a patient's report that an answer was wrong (chat_report, status
  /// NEW) for review before the knowledge base changes.
  Future<Result<void>> saveChatReport(ChatReport r);
}
