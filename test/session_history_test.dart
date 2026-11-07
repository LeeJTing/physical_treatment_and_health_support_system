import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:physical_treatment_and_health_support_system/shared_client/api_client/api_client.dart';
import 'package:physical_treatment_and_health_support_system/model/business_logic/pose_estimation_service/pose_estimation_service.dart';
import 'package:physical_treatment_and_health_support_system/core/utils/id_utils.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/enums.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/exercise_session.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/patient_treatment_plan.dart';
import 'package:physical_treatment_and_health_support_system/model/repository/auth_repository/fake_auth_repository.dart';
import 'package:physical_treatment_and_health_support_system/model/repository/treatment_repository/fake_treatment_repository.dart';
import 'package:physical_treatment_and_health_support_system/view/treatment_view/session_history_view.dart';
import 'package:physical_treatment_and_health_support_system/viewmodel/treatment_view_model/treatment_view_model.dart';

final String catalogueJson = File(
  'assets/seed/catalogue.json',
).readAsStringSync();

class _Setup {
  final auth = FakeAuthRepository();
  final treatments = FakeTreatmentRepository.fromJson(catalogueJson);
  late final vm = TreatmentViewModel(
    treatments,
    PoseEstimationService(
      ApiClient(baseUrl: 'http://ai', tokenProvider: () => 'dev-token'),
    ),
    auth,
  );
  late PatientTreatmentPlan plan;

  Future<void> withPlan({
    List<(int stage, double accuracy, int daysAgo)> attempts = const [],
  }) async {
    final account = (await auth.login(
      'demo@apths.test',
      'password123',
    )).dataOrNull!;
    final catalogue = (await treatments.getCatalogue()).dataOrNull!;
    plan = PatientTreatmentPlan(
      patientPlanId: newId(),
      accountId: account.accountId,
      plan: catalogue.first,
      selectedAt: DateTime.now(),
    );
    await treatments.assignPlan(plan);
    final ordered = plan.plan.orderedExercises();
    for (final (stage, acc, daysAgo) in attempts) {
      await treatments.saveSession(
        ExerciseSession(
          sessionId: newId(),
          accountId: account.accountId,
          patientPlanId: plan.patientPlanId,
          exerciseId: ordered[stage].exerciseId,
          completedAt: DateTime.now().subtract(Duration(days: daysAgo)),
          repetitionsCompleted: 5,
          completionStatus: acc >= ExerciseSession.passMark
              ? CompletionStatus.completed
              : CompletionStatus.retried,
          postureAccuracy: acc,
          postureFeedback: acc >= ExerciseSession.passMark
              ? 'Good form. Keep it up!'
              : 'Raise your arms higher.',
          modelVersion: 'rules-1.0',
        ),
      );
    }
    await vm.loadPlan();
  }
}

void main() {
  test(
    'history is newest first, with exercise names and summary numbers',
    () async {
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
    },
  );

  test('no plan or no sessions gives an empty history', () async {
    final s = _Setup();
    await s.withPlan();
    expect(s.vm.history, isEmpty);
    expect(s.vm.averageAccuracy, isNull);
    expect(s.vm.bestAccuracy, isNull);
  });

  testWidgets('the screen shows the summary, the trend and every attempt', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 3600);
    addTearDown(tester.view.reset);
    final s = _Setup();
    await tester.runAsync(
      () => s.withPlan(attempts: [(0, 60, 3), (0, 85, 2), (1, 90, 0)]),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: ChangeNotifierProvider.value(
          value: s.vm,
          child: const SessionHistoryView(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Posture accuracy over time'), findsOneWidget);
    expect(find.text('90%'), findsWidgets); // best, and the newest attempt
    expect(find.text('Raise your arms higher.'), findsOneWidget);
    expect(find.textContaining('Tried again'), findsOneWidget);
  });

  testWidgets(
    'the trend is in time order; a retry without a time is not drawn first (audit, 24 Oct)',
    (tester) async {
      tester.view.physicalSize = const Size(1080, 3600);
      addTearDown(tester.view.reset);
      final s = _Setup();
      await tester.runAsync(() async {
        await s.withPlan(attempts: [(0, 85, 3), (1, 90, 1)]);
        await s.treatments.saveSession(
          ExerciseSession(
            sessionId: newId(),
            accountId: s.plan.accountId,
            patientPlanId: s.plan.patientPlanId,
            exerciseId: s.plan.plan.orderedExercises()[1].exerciseId,
            completionStatus: CompletionStatus.retried, // no time, as stored
            postureAccuracy: 40,
          ),
        );
        await s.vm.loadPlan();
      });
      await tester.pumpWidget(
        MaterialApp(
          home: ChangeNotifierProvider.value(
            value: s.vm,
            child: const SessionHistoryView(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final trend = tester.widget<Semantics>(
        find.byWidgetPredicate(
          (w) =>
              w is Semantics &&
              (w.properties.label ?? '').startsWith('Accuracy of the last'),
        ),
      );
      expect(
        trend.properties.label,
        'Accuracy of the last 2 attempts, from 85% to 90%',
      );
      // Its card says what happened, not "Not finished".
      expect(find.text('Tried again'), findsOneWidget);
      expect(find.textContaining('Not finished'), findsNothing);
    },
  );

  // Audit D2 (23 Oct): large phone text on a 360 dp phone.
  for (final scale in [1.5, 2.0]) {
    testWidgets(
      'at ${scale}x text on 360 dp: no overflow, every attempt shown',
      (tester) async {
        tester.view.physicalSize = const Size(1080, 7200);
        tester.view.devicePixelRatio = 3;
        addTearDown(tester.view.reset);
        final s = _Setup();
        await tester.runAsync(
          () => s.withPlan(attempts: [(0, 60, 3), (0, 85, 2), (1, 90, 0)]),
        );
        await tester.pumpWidget(
          MaterialApp(
            builder: (c, child) => MediaQuery(
              data: MediaQuery.of(
                c,
              ).copyWith(textScaler: TextScaler.linear(scale)),
              child: child!,
            ),
            home: ChangeNotifierProvider.value(
              value: s.vm,
              child: const SessionHistoryView(),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.text('Posture accuracy over time'), findsOneWidget);
        await tester.scrollUntilVisible(
          find.textContaining('Tried again'),
          300,
        );
        expect(find.textContaining('Tried again'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'without sessions the screen explains where results will appear',
    (tester) async {
      final s = _Setup();
      await tester.runAsync(() => s.withPlan());
      await tester.pumpWidget(
        MaterialApp(
          home: ChangeNotifierProvider.value(
            value: s.vm,
            child: const SessionHistoryView(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('No sessions recorded yet'), findsOneWidget);
    },
  );
}
