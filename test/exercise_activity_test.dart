import 'package:flutter_test/flutter_test.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/enums.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/exercise_session.dart';
import 'package:physical_treatment_and_health_support_system/model/repository/treatment_repository/activity_records.dart';
import 'package:physical_treatment_and_health_support_system/model/repository/treatment_repository/fake_treatment_repository.dart';
import 'package:physical_treatment_and_health_support_system/model/result.dart';
import '../integration_test/support/tracking_graph_fixture.dart';

class BrokenSessions extends FakeTreatmentRepository {
  BrokenSessions(super.plans);
  @override
  Future<Result<List<ExerciseSession>>> getSessions(String id) async =>
      const Failure('Session history unavailable', code: 'offline');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'completed activity preserves details and filters duplicate, foreign and unfinished records',
    () async {
      final f = await TrackingGraphFixture.create();
      addTearDown(f.viewModel.dispose);
      final repo = f.environment.treatments, first = repo.sessions.first;
      repo.sessions.add(first);
      repo.sessions.add(
        ExerciseSession(
          sessionId: 'foreign',
          accountId: 'other',
          patientPlanId: first.patientPlanId,
          exerciseId: first.exerciseId,
          completedAt: first.completedAt,
          durationSec: 600,
          completionStatus: CompletionStatus.completed,
        ),
      );
      repo.sessions.add(
        ExerciseSession(
          sessionId: 'unfinished',
          accountId: first.accountId,
          patientPlanId: first.patientPlanId,
          exerciseId: first.exerciseId,
          completedAt: first.completedAt,
          durationSec: 600,
          completionStatus: CompletionStatus.retried,
        ),
      );
      final result = await repo.completedSessions(
        f.environment.accountId,
        DateTime.now().subtract(const Duration(days: 10)),
        DateTime.now(),
      );
      expect(result.dataOrNull, hasLength(3));
      final activity = result.dataOrNull!.first;
      expect(activity.completedAt, first.completedAt);
      expect(activity.durationSec, 120);
      expect(activity.repetitions, 8);
      expect(activity.postureAccuracy, 84);
      expect(activity.planName, isNotEmpty);
      expect(result.dataOrNull!.last.isDemo, isTrue);
      expect(
        activity.toAnalysisJson().keys,
        unorderedEquals(['completed_at', 'duration_sec']),
      );
    },
  );
  test(
    'a failed assignment session query propagates failure rather than zero activity',
    () async {
      final f = await TrackingGraphFixture.create();
      addTearDown(f.viewModel.dispose);
      final catalogue =
          (await f.environment.treatments.getCatalogue()).dataOrNull!;
      final broken = BrokenSessions(catalogue);
      final plan = (await f.environment.treatments.getPlanHistory(
        f.environment.accountId,
      )).dataOrNull!.first;
      await broken.assignPlan(plan);
      final result = await broken.completedSessions(
        f.environment.accountId,
        DateTime.now().subtract(const Duration(days: 10)),
        DateTime.now(),
      );
      expect(result, isA<Failure>());
      expect((result as Failure).code, 'offline');
    },
  );
}
