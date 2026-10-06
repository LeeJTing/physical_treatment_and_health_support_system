import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:physical_treatment_and_health_support_system/core/services/api_client.dart';
import 'package:physical_treatment_and_health_support_system/core/services/pose_estimation_service.dart';
import 'package:physical_treatment_and_health_support_system/core/utils/id_utils.dart';
import 'package:physical_treatment_and_health_support_system/data/models/enums.dart';
import 'package:physical_treatment_and_health_support_system/data/models/exercise_session.dart';
import 'package:physical_treatment_and_health_support_system/data/models/patient_treatment_plan.dart';
import 'package:physical_treatment_and_health_support_system/data/repository/fake/fake_auth_repository.dart';
import 'package:physical_treatment_and_health_support_system/data/repository/fake/fake_treatment_repository.dart';
import 'package:physical_treatment_and_health_support_system/features/treatment/view/session_history_view.dart';
import 'package:physical_treatment_and_health_support_system/features/treatment/viewmodel/treatment_view_model.dart';

final String catalogueJson = File('assets/seed/catalogue.json').readAsStringSync();

class _Setup {
  final auth = FakeAuthRepository();
  final treatments = FakeTreatmentRepository.fromJson(catalogueJson);
  late final vm = TreatmentViewModel(
      treatments, PoseEstimationService(ApiClient(baseUrl: 'http://ai', tokenProvider: () => 'dev-token')), auth);
  late PatientTreatmentPlan plan;

  Future<void> withPlan({List<(int stage, double accuracy, int daysAgo)> attempts = const []}) async {
    final account = (await auth.login('demo@apths.test', 'password123')).dataOrNull!;
    final catalogue = (await treatments.getCatalogue()).dataOrNull!;
    plan = PatientTreatmentPlan(
        patientPlanId: newId(), accountId: account.accountId, plan: catalogue.first, selectedAt: DateTime.now());
    await treatments.assignPlan(plan);
    final ordered = plan.plan.orderedExercises();
    for (final (stage, acc, daysAgo) in attempts) {
      await treatments.saveSession(ExerciseSession(
        sessionId: newId(),
        accountId: account.accountId,
        patientPlanId: plan.patientPlanId,
        exerciseId: ordered[stage].exerciseId,
        completedAt: DateTime.now().subtract(Duration(days: daysAgo)),
        repetitionsCompleted: 5,
        completionStatus: acc >= ExerciseSession.passMark ? CompletionStatus.completed : CompletionStatus.retried,
        postureAccuracy: acc,
        postureFeedback: acc >= ExerciseSession.passMark ? 'Good form. Keep it up!' : 'Raise your arms higher.',
        modelVersion: 'rules-1.0',
      ));
    }
    await vm.loadPlan();
  }
}

void main() {
  test('history is newest first, with exercise names and summary numbers', () async {
    final s = _Setup();
    await s.withPlan(attempts: [(0, 60, 3), (0, 85, 2), (1, 90, 0)]);
    final h = s.vm.history;
    expect(h, hasLength(3));
    expect(h.first.session.postureAccuracy, 90); // today
    expect(h.last.session.postureAccuracy, 60); // 3 days ago
    final ordered = s.plan.plan.orderedExercises();
    expect(h.last.exerciseName, ordered[0].exercise.exerciseName);
    expect(s.vm.averageAccuracy, closeTo(78.33, 0.01));
    expect(s.vm.bestAccuracy, 90);
    expect(s.vm.completedSessionCount, 2); // the 60% attempt was a retry
  });

  test('no plan or no sessions gives an empty history', () async {
    final s = _Setup();
    await s.withPlan();
    expect(s.vm.history, isEmpty);
    expect(s.vm.averageAccuracy, isNull);
    expect(s.vm.bestAccuracy, isNull);
  });

  testWidgets('the screen shows the summary, the trend and every attempt', (tester) async {
    tester.view.physicalSize = const Size(1080, 3000);
    addTearDown(tester.view.reset);
    final s = _Setup();
    await tester.runAsync(() => s.withPlan(attempts: [(0, 60, 3), (0, 85, 2), (1, 90, 0)]));
    await tester.pumpWidget(MaterialApp(
      home: ChangeNotifierProvider.value(value: s.vm, child: const SessionHistoryView()),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Posture accuracy over time'), findsOneWidget);
    expect(find.text('90%'), findsWidgets); // best, and the newest attempt
    expect(find.text('Raise your arms higher.'), findsOneWidget);
    expect(find.textContaining('Tried again'), findsOneWidget);
  });

  testWidgets('without sessions the screen explains where results will appear', (tester) async {
    final s = _Setup();
    await tester.runAsync(() => s.withPlan());
    await tester.pumpWidget(MaterialApp(
      home: ChangeNotifierProvider.value(value: s.vm, child: const SessionHistoryView()),
    ));
    await tester.pumpAndSettle();
    expect(find.textContaining('No sessions recorded yet'), findsOneWidget);
  });
}
