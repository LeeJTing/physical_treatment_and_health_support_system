import 'package:physical_treatment_and_health_support_system/model/result.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/chat_message.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/exercise_session.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/patient_treatment_plan.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/treatment_plan.dart';

/// Contract for treatment plans, assignments and exercise sessions (Table 4.60).
abstract interface class ITreatmentRepository {
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
