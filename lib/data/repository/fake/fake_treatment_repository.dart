import 'dart:convert';

import 'package:physical_treatment_and_health_support_system/core/base/result.dart';
import 'package:physical_treatment_and_health_support_system/data/models/chat_message.dart';
import 'package:physical_treatment_and_health_support_system/data/models/enums.dart';
import 'package:physical_treatment_and_health_support_system/data/models/exercise_session.dart';
import 'package:physical_treatment_and_health_support_system/data/models/patient_treatment_plan.dart';
import 'package:physical_treatment_and_health_support_system/data/models/treatment_plan.dart';
import 'package:physical_treatment_and_health_support_system/data/repository/interfaces/i_treatment_repository.dart';

/// In-memory treatment data. The catalogue is the same seed that goes into
/// Supabase (assets/seed/catalogue.json, built by supabase/seed/build_seed.py).
class FakeTreatmentRepository implements ITreatmentRepository {
  final List<TreatmentPlan> _catalogue;
  final Map<String, PatientTreatmentPlan> _assigned = {};
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

  @override
  Future<Result<PatientTreatmentPlan?>> getActivePlan(String accountId) async {
    final p = _assigned[accountId];
    return Success(p != null && p.isActive() ? p : null);
  }

  @override
  Future<Result<List<TreatmentPlan>>> getCatalogue() async => Success(List<TreatmentPlan>.unmodifiable(_catalogue));

  @override
  Future<Result<void>> assignPlan(PatientTreatmentPlan p) async {
    _assigned[p.accountId] = p; // replaces (abandons) any previous plan
    return const Success(null);
  }

  @override
  Future<Result<void>> saveSession(ExerciseSession s, {PatientTreatmentPlan? advancedPlan}) async {
    sessions.add(s);
    if (advancedPlan != null) _assigned[advancedPlan.accountId] = advancedPlan;
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
    return sessions.any((s) =>
        s.accountId == accountId &&
        s.completionStatus == CompletionStatus.completed &&
        s.completedAt != null &&
        s.completedAt!.year == now.year &&
        s.completedAt!.month == now.month &&
        s.completedAt!.day == now.day);
  }
}
