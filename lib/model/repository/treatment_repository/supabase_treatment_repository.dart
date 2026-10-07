import 'package:physical_treatment_and_health_support_system/model/result.dart';
import 'package:physical_treatment_and_health_support_system/core/constants/app_constants.dart';
import 'package:physical_treatment_and_health_support_system/shared_client/supabase_provider/supabase_provider.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/chat_message.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/enums.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/exercise_session.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/patient_treatment_plan.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/treatment_plan.dart';
import 'package:physical_treatment_and_health_support_system/model/repository/treatment_repository/i_treatment_repository.dart';
import 'package:physical_treatment_and_health_support_system/model/repository/supabase_guard.dart';

/// Catalogue, assigned plans, exercise sessions and chat turns (Table 4.60).
class SupabaseTreatmentRepository implements ITreatmentRepository {
  static const String _planWithExercises = '*, plan_exercise(*, exercise(*))';

  final SupabaseProvider _sb;

  SupabaseTreatmentRepository(this._sb);

  @override
  Future<Result<PatientTreatmentPlan?>> getActivePlan(String accountId) =>
      supabaseGuard(() async {
        final row = await _sb
            .from('patient_plan')
            .select('*, treatment_plan($_planWithExercises)')
            .eq('account_id', accountId)
            .eq('status', PlanStatus.active.db)
            .maybeSingle();
        return row == null ? null : PatientTreatmentPlan.fromJson(row);
      }, failMessage: Messages.planRetrieveFailed);

  @override
  Future<Result<List<TreatmentPlan>>> getCatalogue() => supabaseGuard(
    () async =>
        (await _sb
                .from('treatment_plan')
                .select(_planWithExercises)
                .order('plan_name'))
            .map(TreatmentPlan.fromJson)
            .toList(),
  );

  /// Only one ACTIVE plan per patient (unique partial index), so the old one is
  /// abandoned before the new one is inserted (FR500_09).
  @override
  Future<Result<void>> assignPlan(PatientTreatmentPlan p) =>
      supabaseGuard(() async {
        await _sb
            .from('patient_plan')
            .update({'status': PlanStatus.abandoned.db})
            .eq('account_id', p.accountId)
            .eq('status', PlanStatus.active.db);
        await _sb.from('patient_plan').insert(p.toJson());
      });

  /// One RPC, so the attempt and the plan's new progress are written in one
  /// transaction (ASR_04).
  @override
  Future<Result<void>> saveSession(
    ExerciseSession s, {
    PatientTreatmentPlan? advancedPlan,
  }) => supabaseGuard(() async {
    await _sb.client.rpc(
      'complete_exercise_session',
      params: {
        'p_session_id': s.sessionId,
        'p_exercise_id': s.exerciseId,
        'p_completion_status': s.completionStatus.db,
        'p_patient_plan_id': s.patientPlanId,
        'p_completed_at': s.completedAt?.toUtc().toIso8601String(),
        'p_duration_sec': s.durationSec,
        'p_repetitions_completed': s.repetitionsCompleted,
        'p_posture_accuracy': s.postureAccuracy,
        'p_posture_feedback': s.postureFeedback,
        'p_model_version': s.modelVersion,
        if (advancedPlan != null)
          'p_new_progress': advancedPlan.progressPercentage,
        if (advancedPlan != null) 'p_new_plan_status': advancedPlan.status.db,
      },
    );
  }, failMessage: Messages.progressSaveFailed);

  @override
  Future<Result<List<ExerciseSession>>> getSessions(String patientPlanId) =>
      supabaseGuard(
        () async =>
            (await _sb
                    .from('exercise_session')
                    .select()
                    .eq('patient_plan_id', patientPlanId)
                    .order('completed_at', ascending: true, nullsFirst: false))
                .map(ExerciseSession.fromJson)
                .toList(),
      );

  @override
  Future<Result<void>> endPlan(PatientTreatmentPlan p) =>
      supabaseGuard(() async {
        await _sb
            .from('patient_plan')
            .update({'status': PlanStatus.abandoned.db})
            .eq('patient_plan_id', p.patientPlanId);
      });

  @override
  Future<Result<void>> saveChatMessage(ChatMessage m) =>
      supabaseGuard(() async {
        await _sb.from('chat_message').insert(m.toJson());
      });
}
