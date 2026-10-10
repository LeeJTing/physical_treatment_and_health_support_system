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
  Future<Result<List<PatientTreatmentPlan>>> getActivePlans(String accountId) =>
      supabaseGuard(
        () async =>
            (await _sb
                    .from('patient_plan')
                    .select('*, treatment_plan($_planWithExercises)')
                    .eq('account_id', accountId)
                    .eq('status', PlanStatus.active.db)
                    .order('selected_at'))
                .map(PatientTreatmentPlan.fromJson)
                .toList(),
        failMessage: Messages.planRetrieveFailed,
      );

  @override
  Future<Result<List<PatientTreatmentPlan>>> getPlanHistory(String accountId) =>
      supabaseGuard(
        () async =>
            (await _sb
                    .from('patient_plan')
                    .select('*, treatment_plan($_planWithExercises)')
                    .eq('account_id', accountId)
                    .order('selected_at'))
                .map(PatientTreatmentPlan.fromJson)
                .toList(),
        failMessage: Messages.planRetrieveFailed,
      );

  /// The newest ACTIVE plan. Not maybeSingle(): with several active plans
  /// that would throw.
  @override
  Future<Result<PatientTreatmentPlan?>> getActivePlan(String accountId) =>
      supabaseGuard(() async {
        final rows = await _sb
            .from('patient_plan')
            .select('*, treatment_plan($_planWithExercises)')
            .eq('account_id', accountId)
            .eq('status', PlanStatus.active.db)
            .order('selected_at', ascending: false)
            .limit(1);
        return rows.isEmpty ? null : PatientTreatmentPlan.fromJson(rows.first);
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

  /// Anonymised outcomes from the `plan_outcome_stats()` RPC (cells of 5+
  /// patients, no account ids). Until the RPC is applied (supabase/proposed/)
  /// the call fails and the recommender runs as a cold start.
  @override
  Future<Result<List<PlanOutcome>>> getPlanOutcomes() =>
      supabaseGuard(() async {
        final rows = await _sb.client.rpc('plan_outcome_stats') as List;
        return [
          for (final r in rows.cast<Map<String, dynamic>>())
            (
              planId: r['plan_id'] as String,
              riskLevel: r['risk_level'] as String,
              ageBand: r['age_band'] as String,
              patients: (r['patients'] as num).toInt(),
              completionRate: (r['completion_rate'] as num).toDouble(),
              meanAccuracy: (r['mean_accuracy'] as num?)?.toDouble(),
              meanProgress: (r['mean_progress'] as num?)?.toDouble(),
            ),
        ];
      });

  /// Abandons only the plans being replaced, then inserts the new one
  /// (FR500_09). Until supabase/proposed/..._multiple_active_plans.sql is
  /// applied, the unique index 'one ACTIVE plan per patient' rejects a second
  /// ACTIVE plan with Postgres code 23505.
  @override
  Future<Result<void>> assignPlan(
    PatientTreatmentPlan p, {
    List<String> replacing = const [],
  }) => supabaseGuard(() async {
    if (replacing.isNotEmpty) {
      await _sb
          .from('patient_plan')
          .update({'status': PlanStatus.abandoned.db})
          .eq('account_id', p.accountId)
          .inFilter('patient_plan_id', replacing);
    }
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
