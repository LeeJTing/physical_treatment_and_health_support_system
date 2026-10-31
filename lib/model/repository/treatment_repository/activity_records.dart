import 'package:physical_treatment_and_health_support_system/model/result.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/biometric_reading.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/exercise_session.dart';
import 'package:physical_treatment_and_health_support_system/model/repository/treatment_repository/i_treatment_repository.dart';

/// Completed exercise sessions as activity records for M200 (FR200_015, FR200_016; UC700 A8,
/// C14) and M400 (FR400_019), read through the Physical Treatment Module's own repository so M200
/// keeps no copy of them. An extension, so ITreatmentRepository (Elwin's) is unchanged.
extension ActivityRecords on ITreatmentRepository {
  Future<Result<List<ActivityRecord>>> completedSessions(
    String accountId,
    DateTime from,
    DateTime to,
  ) async {
    final plans = await getPlanHistory(accountId);
    if (plans case Failure(:final message, :final code, :final cause)) {
      return Failure(message, code: code, cause: cause);
    }
    final out = <ActivityRecord>[];
    final seen = <String>{};
    for (final p in plans.dataOrNull!) {
      final sessions = (await getSessions(p.patientPlanId)).dataOrNull ?? const <ExerciseSession>[];
      for (final s in sessions) {
        final at = s.completedAt?.toLocal();
        if (!s.isCompleted() || at == null || at.isBefore(from) || at.isAfter(to)) continue;
        if (!seen.add(s.sessionId)) continue;
        final name = p.plan.exercises
                .where((e) => e.exercise.exerciseId == s.exerciseId)
                .firstOrNull
                ?.exercise
                .exerciseName ??
            'Exercise';
        out.add(
          ActivityRecord(
            sessionId: s.sessionId,
            exerciseName: name,
            durationSec: s.durationSec ?? 0,
            completedAt: at,
          ),
        );
      }
    }
    out.sort((a, b) => a.completedAt.compareTo(b.completedAt));
    return Success(out);
  }
}
