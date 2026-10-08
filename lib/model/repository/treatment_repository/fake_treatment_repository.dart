import 'dart:convert';

import 'package:physical_treatment_and_health_support_system/model/result.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/chat_message.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/enums.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/exercise_session.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/patient_treatment_plan.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/treatment_plan.dart';
import 'package:physical_treatment_and_health_support_system/model/repository/treatment_repository/i_treatment_repository.dart';

/// In-memory treatment data. The catalogue is the same seed that goes into
/// Supabase (assets/seed/catalogue.json, built by supabase/seed/build_seed.py).
class FakeTreatmentRepository implements ITreatmentRepository {
  final List<TreatmentPlan> _catalogue;

  /// Every assignment by patientPlanId (several can be ACTIVE per patient).
  final Map<String, PatientTreatmentPlan> _plans = {};
  final List<ExerciseSession> sessions = [];
  final List<ChatMessage> chat = [];

  FakeTreatmentRepository(this._catalogue);

  factory FakeTreatmentRepository.fromJson(String catalogueJson) {
    final j = jsonDecode(catalogueJson) as Map<String, dynamic>;
    final plans = (j['plans'] as List)
        .map((p) => TreatmentPlan.fromJson(p as Map<String, dynamic>))
        .toList();
    return FakeTreatmentRepository(plans);
  }

  List<PatientTreatmentPlan> _active(String accountId) =>
      _plans.values
          .where((p) => p.accountId == accountId && p.isActive())
          .toList()
        ..sort((a, b) => a.selectedAt.compareTo(b.selectedAt));

  @override
  Future<Result<List<PatientTreatmentPlan>>> getActivePlans(
    String accountId,
  ) async => Success(_active(accountId));

  @override
  Future<Result<PatientTreatmentPlan?>> getActivePlan(String accountId) async {
    final all = _active(accountId);
    return Success(all.isEmpty ? null : all.last);
  }

  @override
  Future<Result<List<TreatmentPlan>>> getCatalogue() async =>
      Success(List<TreatmentPlan>.unmodifiable(_catalogue));

  /// Synthetic cohort evidence for tests and demos; empty by default (cold start).
  List<PlanOutcome> planOutcomes = const [];

  @override
  Future<Result<List<PlanOutcome>>> getPlanOutcomes() async =>
      Success(List<PlanOutcome>.unmodifiable(planOutcomes));

  @override
  Future<Result<void>> assignPlan(
    PatientTreatmentPlan p, {
    List<String> replacing = const [],
  }) async {
    for (final id in replacing) {
      final old = _plans[id];
      if (old != null) _plans[id] = _abandoned(old);
    }
    _plans[p.patientPlanId] = p;
    return const Success(null);
  }

  static PatientTreatmentPlan _abandoned(PatientTreatmentPlan p) =>
      PatientTreatmentPlan(
        patientPlanId: p.patientPlanId,
        accountId: p.accountId,
        plan: p.plan,
        suitabilityScore: p.suitabilityScore,
        progressPercentage: p.progressPercentage,
        status: PlanStatus.abandoned,
        selectedAt: p.selectedAt,
      );

  @override
  Future<Result<void>> saveSession(
    ExerciseSession s, {
    PatientTreatmentPlan? advancedPlan,
  }) async {
    sessions.add(s);
    if (advancedPlan != null) _plans[advancedPlan.patientPlanId] = advancedPlan;
    return const Success(null);
  }

  @override
  Future<Result<List<ExerciseSession>>> getSessions(
    String patientPlanId,
  ) async =>
      Success(sessions.where((s) => s.patientPlanId == patientPlanId).toList());

  @override
  Future<Result<void>> endPlan(PatientTreatmentPlan p) async {
    _plans[p.patientPlanId] = _abandoned(p);
    return const Success(null);
  }

  @override
  Future<Result<void>> saveChatMessage(ChatMessage m) async {
    chat.add(m);
    return const Success(null);
  }

  /// Test helper: whether a COMPLETED session exists for today.
  bool completedToday(String accountId) {
    final now = DateTime.now();
    return sessions.any(
      (s) =>
          s.accountId == accountId &&
          s.completionStatus == CompletionStatus.completed &&
          s.completedAt != null &&
          s.completedAt!.year == now.year &&
          s.completedAt!.month == now.month &&
          s.completedAt!.day == now.day,
    );
  }
}
