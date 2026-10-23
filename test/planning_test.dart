import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';

import 'package:physical_treatment_and_health_support_system/model/entity/patient_treatment_plan.dart';
import 'package:physical_treatment_and_health_support_system/model/result.dart';
import 'package:physical_treatment_and_health_support_system/viewmodel/ui_state.dart';
import 'package:physical_treatment_and_health_support_system/core/constants/app_constants.dart';
import 'package:physical_treatment_and_health_support_system/shared_client/api_client/api_client.dart';
import 'package:physical_treatment_and_health_support_system/model/business_logic/risk_assessment_service/risk_assessment_service.dart';
import 'package:physical_treatment_and_health_support_system/model/business_logic/recommendation_service/recommendation_service.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/enums.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/exercise_session.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/health_profile.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/lookups.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/rehab_info.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/reminder.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/treatment_plan.dart';
import 'package:physical_treatment_and_health_support_system/model/repository/auth_repository/fake_auth_repository.dart';
import 'package:physical_treatment_and_health_support_system/model/repository/notification_repository/fake_notification_repository.dart';
import 'package:physical_treatment_and_health_support_system/model/repository/profile_repository/fake_profile_repository.dart';
import 'package:physical_treatment_and_health_support_system/model/repository/treatment_repository/fake_treatment_repository.dart';
import 'package:physical_treatment_and_health_support_system/model/repository/treatment_repository/i_treatment_repository.dart';
import 'package:physical_treatment_and_health_support_system/model/business_logic/recommendation_service/recommendation.dart';
import 'package:physical_treatment_and_health_support_system/view/planning_view/recommended_plans_view.dart';
import 'package:physical_treatment_and_health_support_system/viewmodel/planning_view_model/planning_view_model.dart';

final String catalogueJson = File(
  'assets/seed/catalogue.json',
).readAsStringSync();

const rehab = RehabInfo(
  affectedBodyArea: 'BOTH_LEGS',
  recoveryStage: RecoveryStage.early,
  mobilityLevel: MobilityLevel.low,
  goal: 'MOBILITY',
);

/// Stand-in for the AI server: returns the first [n] catalogue plans with
/// falling scores, and records the last request body.
class FakeServer {
  Map<String, dynamic>? lastBody;
  int n = 3;
  int status = 200;
  String nextStep = 'START';
  String nextStepReason = '';

  late final client = MockClient((req) async {
    lastBody = jsonDecode(req.body) as Map<String, dynamic>;
    if (status != 200) {
      return http.Response(
        '{"error":{"code":"error","message":"boom"}}',
        status,
      );
    }
    final plans = (lastBody!['plans'] as List)
        .cast<Map<String, dynamic>>()
        .take(n)
        .toList();
    return http.Response(
      jsonEncode({
        'status': n == 0
            ? 'NONE'
            : n == 1
            ? 'ONLY_ONE'
            : 'OK',
        'ranked': [
          for (var i = 0; i < plans.length; i++)
            {
              'plan_id': plans[i]['plan_id'],
              'suitability_score': 0.92 - i * 0.12,
            },
        ],
        'excluded': [],
        'suitable_count': n,
        'model_version': 'hybrid-1.0',
        'next_step': nextStep,
        'next_step_reason': nextStepReason,
      }),
      200,
    );
  });
}

class FailingCatalogue extends FakeTreatmentRepository {
  FailingCatalogue() : super(const []);
  @override
  Future<Result<List<TreatmentPlan>>> getCatalogue() async =>
      const Failure('down', code: 'offline');
}

/// The plan_outcome_stats() RPC is not deployed: the call fails.
class NoOutcomeStats extends FakeTreatmentRepository {
  NoOutcomeStats(super.catalogue);
  @override
  Future<Result<List<PlanOutcome>>> getPlanOutcomes() async =>
      const Failure('function not found', code: 'PGRST202');
}

const PlanOutcome kneeCell = (
  planId: 'p-knee',
  riskLevel: 'Low',
  ageBand: '<60',
  patients: 12,
  completionRate: 0.8,
  meanAccuracy: 84.5,
  meanProgress: null,
);

class Harness {
  final server = FakeServer();
  final auth = FakeAuthRepository();
  final profiles = FakeProfileRepository();
  final notifications = FakeNotificationRepository();
  late final ITreatmentRepository treatments;
  late final RecommendationService recommender;
  late final PlanningViewModel vm;

  Harness({ITreatmentRepository? repo}) {
    treatments = repo ?? FakeTreatmentRepository.fromJson(catalogueJson);
    recommender = RecommendationService(
      ApiClient(
        baseUrl: 'http://ai',
        tokenProvider: () => 'dev-token',
        httpClient: server.client,
      ),
    );
    vm = PlanningViewModel(
      treatments,
      recommender,
      RiskAssessmentService(auth, profiles),
      notifications,
    );
  }

  Future<String> signIn({
    bool withProfile = true,
    List<String> limitations = const [],
  }) async {
    final account = (await auth.login(
      'demo@apths.test',
      'password123',
    )).dataOrNull!;
    if (withProfile) {
      final p = HealthProfile(
        profileId: 'p1',
        accountId: account.accountId,
        age: 58,
        gender: Gender.male,
        weightKg: 72,
        heightCm: 170,
        limitations: [
          for (final c in limitations)
            LookupSeed.limitations.firstWhere((l) => l.limitationCode == c),
        ],
        updatedAt: DateTime.now(),
      );
      await profiles.saveProfile(p, p.generateSafetyLimit());
    }
    return account.accountId;
  }
}

void main() {
  group('RecommendationService', () {
    test('sends the optional pace beside rehab', () async {
      final h = Harness();
      await h.signIn();
      await h.vm.recommend(
        const RehabInfo(
          affectedBodyArea: 'BOTH_LEGS',
          recoveryStage: RecoveryStage.early,
          mobilityLevel: MobilityLevel.low,
          goal: 'MOBILITY',
          pace: 'SLOW',
        ),
      );
      final body = h.server.lastBody!;
      expect(body['pace'], 'SLOW');
      expect((body['rehab'] as Map).containsKey('pace'), isFalse);
      // The plans carry frequency_per_week, which the pace is compared with.
      expect((body['plans'] as List).first['frequency_per_week'], isA<int>());
    });

    test('sends the body-map parts as focus_parts', () async {
      final h = Harness();
      await h.signIn();
      await h.vm.recommend(
        const RehabInfo(
          affectedBodyArea: 'BOTH_ARMS',
          recoveryStage: RecoveryStage.early,
          mobilityLevel: MobilityLevel.low,
          goal: 'MOBILITY',
          focusParts: ['wrist_hand'],
        ),
      );
      final body = h.server.lastBody!;
      expect(body['focus_parts'], ['wrist_hand']);
      expect(body.containsKey('pace'), isFalse); // skipped: no pace block
      // Not inside rehab: RehabInfo.toJson keeps the four FR500_03 answers.
      expect((body['rehab'] as Map).containsKey('focus_parts'), isFalse);
    });

    test(
      'sends rehab, safety limit, limitation codes and the catalogue',
      () async {
        final h = Harness();
        await h.signIn(limitations: ['LEFT_ARM_MOBILITY']);
        await h.vm.recommend(rehab);
        final body = h.server.lastBody!;
        expect(body['rehab'], rehab.toJson());
        expect(body['safety_limit']['max_exercise_intensity'], 'MODERATE');
        expect(body['limitations'], ['LEFT_ARM_MOBILITY']);
        // No body-map parts: no focus block (hybrid-2.0 result).
        expect(body.containsKey('focus_parts'), isFalse);
        // Each exercise carries its pose key, from which the server reads the
        // body parts a plan trains.
        final first = (body['plans'] as List).first as Map;
        expect(
          ((first['plan_exercise'] as List).first
              as Map)['exercise']['pose_key'],
          isNotNull,
        );
        // Every catalogue plan is sent (11 since 608b5ce added Hand and Wrist Recovery).
        expect(
          (body['plans'] as List).length,
          (jsonDecode(catalogueJson)['plans'] as List).length,
        );
      },
    );

    test(
      'maps ranked ids back to plans with their scores, best first',
      () async {
        final h = Harness();
        await h.signIn();
        await h.vm.recommend(rehab);
        expect(h.vm.candidates.length, 3);
        expect(h.vm.candidates.first.suitabilityScore, closeTo(0.92, 1e-9));
        expect(h.recommender.modelVersion, 'hybrid-1.0');
      },
    );

    test('server error becomes the M4 message (FR500_25)', () async {
      final h = Harness()..server.status = 500;
      await h.signIn();
      await h.vm.recommend(rehab);
      expect(h.vm.recommendation, isA<UiError<Recommendation>>());
      expect(
        (h.vm.recommendation as UiError).message,
        Messages.recommendFailed,
      );
    });
  });

  group('collaborative evidence (hybrid-2.0)', () {
    test(
      'sends the cohort and the outcome cells from the repository',
      () async {
        final repo = FakeTreatmentRepository.fromJson(catalogueJson)
          ..planOutcomes = const [kneeCell];
        final h = Harness(repo: repo);
        await h.signIn();
        await h.vm.recommend(rehab);
        final body = h.server.lastBody!;
        expect(body['cohort'], {'risk_level': 'Low', 'age_band': '<60'});
        expect(body['plan_outcomes'], [
          {
            'plan_id': 'p-knee',
            'risk_level': 'Low',
            'age_band': '<60',
            'patients': 12,
            'completion_rate': 0.8,
            'mean_accuracy': 84.5,
            'mean_progress': null,
          },
        ]);
        expect(h.vm.candidates.length, 3);
      },
    );

    test('no evidence by default: empty list, still recommends', () async {
      final h = Harness();
      await h.signIn();
      await h.vm.recommend(rehab);
      expect(h.server.lastBody!['plan_outcomes'], isEmpty);
      expect(h.vm.recommendation, isA<UiSuccess<Recommendation>>());
    });

    test('RPC missing or failing is a cold start, not an error', () async {
      final catalogue = FakeTreatmentRepository.fromJson(catalogueJson);
      final h = Harness(
        repo: NoOutcomeStats((await catalogue.getCatalogue()).dataOrNull!),
      );
      await h.signIn();
      await h.vm.recommend(rehab);
      expect(h.server.lastBody!['plan_outcomes'], isEmpty);
      expect(h.vm.recommendation, isA<UiSuccess<Recommendation>>());
      expect(h.vm.candidates.length, 3);
    });

    test('no profile: no cohort is sent', () async {
      final h = Harness();
      await h.signIn(withProfile: false);
      await h.vm.recommend(rehab);
      expect(h.server.lastBody!.containsKey('cohort'), isFalse);
    });

    test('age bands match the RPC', () {
      expect(RecommendationService.ageBand(59), '<60');
      expect(RecommendationService.ageBand(60), '60-74');
      expect(RecommendationService.ageBand(74), '60-74');
      expect(RecommendationService.ageBand(75), '75+');
    });
  });

  group('PlanningViewModel', () {
    // Found on the phone: the live catalogue was empty (seed not loaded), the
    // app sent plans: [] and the server's 422 surfaced as M4.
    test('empty catalogue gives M1 without calling the server', () async {
      final h = Harness(repo: FakeTreatmentRepository(const []));
      await h.signIn();
      await h.vm.recommend(rehab);
      expect(
        (h.vm.recommendation as UiError).message,
        Messages.conditionNotMet,
      );
      expect(h.server.lastBody, isNull);
    });

    test('no session gives the session-expired message', () async {
      final h = Harness();
      await h.vm.recommend(rehab);
      expect((h.vm.recommendation as UiError).message, Messages.sessionExpired);
    });

    test('profile read failure gives M3 (FR500_24)', () async {
      final h = Harness();
      await h.signIn();
      h.profiles.failNext = true;
      await h.vm.recommend(rehab);
      expect(
        (h.vm.recommendation as UiError).message,
        Messages.healthInfoFailed,
      );
    });

    test(
      'catalogue failure gives M5 (FR500_26) and retry runs again',
      () async {
        final h = Harness(repo: FailingCatalogue());
        await h.signIn();
        await h.vm.recommend(rehab);
        expect(
          (h.vm.recommendation as UiError).message,
          Messages.dbUnavailable,
        );
        expect(h.vm.lastRehab, rehab);
      },
    );

    test('missing profile uses the fail-safe limit and shows M1', () async {
      final h = Harness();
      await h.signIn(withProfile: false);
      await h.vm.recommend(rehab);
      expect(h.vm.notice, Messages.profileNotConfigured);
      expect(
        h.server.lastBody!['safety_limit']['max_exercise_intensity'],
        'LOW',
      );
      expect(h.vm.recommendation, isA<UiSuccess<Recommendation>>());
    });

    test(
      'NONE and ONLY_ONE come through as statuses (FR500_14, FR500_15)',
      () async {
        final h = Harness();
        await h.signIn();
        h.server.n = 0;
        await h.vm.recommend(rehab);
        expect(h.vm.candidates, isEmpty);
        h.server.n = 1;
        await h.vm.recommend(rehab);
        expect(
          (h.vm.recommendation as UiSuccess<Recommendation>).data.status,
          RecommendationStatus.onlyOne,
        );
      },
    );

    test(
      'a plan saved without its reminder still counts as selected (audit, 23 Oct)',
      () async {
        final h = Harness();
        final accountId = await h.signIn();
        final vm = PlanningViewModel(
          h.treatments,
          h.recommender,
          RiskAssessmentService(h.auth, h.profiles),
          _NoReminders(),
        );
        await vm.recommend(rehab);
        final plan = vm.candidates.first;
        expect(await vm.select(plan), isTrue);
        expect(vm.reminderNotSet, isTrue);
        // Selecting it again is refused instead of assigning it twice.
        expect(
          vm.issuesFor(plan).map((i) => i.code),
          contains('already_following'),
        );
        expect(
          (await h.treatments.getActivePlans(accountId)).dataOrNull,
          hasLength(1),
        );
      },
    );

    test('Select tapped twice at once assigns the plan once (23 Oct)', () async {
      final h = Harness();
      await h.signIn();
      await h.vm.recommend(rehab);
      final plan = h.vm.candidates.first;
      final results = await Future.wait([h.vm.select(plan), h.vm.select(plan)]);
      expect(results.where((ok) => ok), hasLength(1));
    });

    test(
      'select saves the plan and a reminder for its weekly frequency (FR500_09, FR500_11)',
      () async {
        final h = Harness();
        final accountId = await h.signIn();
        await h.vm.recommend(rehab);
        final plan = h.vm.candidates.first;
        expect(await h.vm.select(plan), isTrue);

        final active = (await h.treatments.getActivePlan(
          accountId,
        )).dataOrNull!;
        expect(active.plan.planId, plan.planId);
        expect(active.suitabilityScore, plan.suitabilityScore);
        final reminders = (await h.notifications.getReminders(
          accountId,
        )).dataOrNull!;
        expect(reminders.single.patientPlanId, active.patientPlanId);
        expect(reminders.single.reminderType, ReminderType.exercise);
        expect(reminders.single.weekdays.length, plan.frequencyPerWeek);
      },
    );

    test(
      'rejectAll clears the plans and saves nothing (FR500_12, FR500_13)',
      () async {
        final h = Harness();
        final accountId = await h.signIn();
        await h.vm.recommend(rehab);
        h.vm.rejectAll();
        expect(h.vm.recommendation, isA<Idle<Recommendation>>());
        expect(
          (await h.treatments.getActivePlan(accountId)).dataOrNull,
          isNull,
        );
      },
    );
  });

  group('RecommendedPlansView', () {
    Future<Harness> pump(
      WidgetTester tester, {
      int n = 3,
      int? following,
    }) async {
      // Phone width, tall enough that all three cards (with their body
      // thumbnails) are built by the ListView.
      tester.view.physicalSize = const Size(1080, 3600);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      final h = Harness()..server.n = n;
      await tester.runAsync(() async {
        final accountId = await h.signIn();
        // Optionally already following catalogue plan [following] (33% done).
        if (following != null) {
          final catalogue = (await h.treatments.getCatalogue()).dataOrNull!;
          await h.treatments.assignPlan(
            PatientTreatmentPlan(
              patientPlanId: 'current',
              accountId: accountId,
              plan: catalogue[following],
              progressPercentage: 33,
              selectedAt: DateTime(2026, 10, 1),
            ),
          );
        }
        await h.vm.recommend(rehab);
      });
      await tester.pumpWidget(
        MaterialApp(
          home: ChangeNotifierProvider.value(
            value: h.vm,
            child: const RecommendedPlansView(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      return h;
    }

    Future<List<PatientTreatmentPlan>> activeOf(
      WidgetTester tester,
      Harness h,
    ) async => (await tester.runAsync(
      () async => (await h.treatments.getActivePlans(
        h.vm.activePlans.first.accountId,
      )).dataOrNull!,
    ))!;

    testWidgets('a plan for another area is added beside the current one', (
      tester,
    ) async {
      // Following Core and Back Care (6); Early Knee Recovery (0) is offered first.
      final h = await pump(tester, following: 6);
      expect(
        find.text('Can be followed together with your current plans.'),
        findsWidgets,
      );
      await tester.tap(find.text('Select').first);
      await tester.pumpAndSettle();
      expect(find.text('Add Early Knee Recovery?'), findsOneWidget);
      await tester.tap(find.text('Add plan'));
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pumpAndSettle();
      final active = await activeOf(tester, h);
      expect(
        [for (final a in active) a.plan.planName],
        ['Core and Back Care', 'Early Knee Recovery'],
      );
    });

    testWidgets('same area and goal: replace, and Keep changes nothing', (
      tester,
    ) async {
      // Following Advanced Leg Function (9, legs + strength); Lower Limb
      // Strength Builder (1, legs + strength) is offered second.
      final h = await pump(tester, following: 9);
      expect(
        find.textContaining('Clashes with Advanced Leg Function'),
        findsOneWidget,
      );
      await tester.tap(find.text('Select').at(1));
      await tester.pumpAndSettle();
      expect(find.text('Replace your plan?'), findsOneWidget);
      expect(
        find.textContaining('This stops Advanced Leg Function (33% done)'),
        findsOneWidget,
      );
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(
        [for (final a in await activeOf(tester, h)) a.plan.planName],
        ['Advanced Leg Function'],
      );

      await tester.tap(find.text('Select').at(1));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Replace'));
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pumpAndSettle();
      expect(
        [for (final a in await activeOf(tester, h)) a.plan.planName],
        ['Lower Limb Strength Builder'],
      );
    });

    testWidgets('the plan already followed is blocked with an explanation', (
      tester,
    ) async {
      final h = await pump(tester, following: 0);
      expect(find.text('You are already following this plan.'), findsWidgets);
      await tester.tap(find.text('Select').first);
      await tester.pumpAndSettle();
      expect(find.text('You cannot add Early Knee Recovery'), findsOneWidget);
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      final active = await activeOf(tester, h);
      expect(active.single.patientPlanId, 'current');
    });

    testWidgets('shows three plans as in the design', (tester) async {
      final h = await pump(tester);
      expect(find.text('Recommended plans'), findsOneWidget);
      expect(find.text('Based on your health profile'), findsOneWidget);
      expect(find.text(h.vm.candidates.first.planName), findsOneWidget);
      expect(find.text('92% match'), findsOneWidget);
      expect(find.text('View details'), findsNWidgets(3));
      expect(find.text('Select'), findsNWidgets(3));
      await tester.scrollUntilVisible(find.text('Reject all plans'), 200);
      expect(find.text('Reject all plans'), findsOneWidget);
    });

    testWidgets('only one plan shows the FR500_15 message', (tester) async {
      await pump(tester, n: 1);
      expect(find.text(Messages.onlyOnePlan), findsOneWidget);
      expect(find.text('Select'), findsOneWidget);
    });

    testWidgets('no plan shows the FR500_14 message', (tester) async {
      await pump(tester, n: 0);
      expect(find.text(Messages.conditionNotMet), findsOneWidget);
      expect(find.text('Reject all plans'), findsNothing);
    });

    testWidgets('reject all asks for confirmation first', (tester) async {
      await pump(tester);
      await tester.scrollUntilVisible(find.text('Reject all plans'), 200);
      await tester.tap(find.text('Reject all plans'));
      await tester.pumpAndSettle();
      expect(find.text(Messages.confirmReject), findsOneWidget);
    });
  });

  group('progress (hybrid-3.0)', () {
    Future<TreatmentPlan> planNamed(Harness h, String name) async =>
        (await h.treatments.getCatalogue()).dataOrNull!.firstWhere(
          (p) => p.planName == name,
        );

    test('no history: no progress is sent', () async {
      final h = Harness();
      await h.signIn();
      await h.vm.recommend(rehab);
      expect(h.server.lastBody!.containsKey('progress'), isFalse);
    });

    test(
      'sends each plan with its difficulty and the results per exercise',
      () async {
        final h = Harness();
        final id = await h.signIn();
        final knee = await planNamed(h, 'Early Knee Recovery');
        await h.treatments.assignPlan(
          PatientTreatmentPlan(
            patientPlanId: 'pp1',
            accountId: id,
            plan: knee,
            selectedAt: DateTime(2026, 9, 1),
          ),
        );
        final ext = knee.orderedExercises().first.exerciseId;
        ExerciseSession attempt(
          String sid,
          double accuracy, {
          int? daysAgo,
          String feedback = '',
        }) => ExerciseSession(
          sessionId: sid,
          accountId: id,
          patientPlanId: 'pp1',
          exerciseId: ext,
          completedAt: daysAgo == null
              ? null
              : DateTime.now().subtract(Duration(days: daysAgo)),
          completionStatus: daysAgo == null
              ? CompletionStatus.retried
              : CompletionStatus.completed,
          postureAccuracy: accuracy,
          postureFeedback: feedback,
        );
        const fall = 'You may have lost your balance or fallen.';
        await h.treatments.saveSession(attempt('a', 55));
        await h.treatments.saveSession(attempt('b', 60));
        await h.treatments.saveSession(
          attempt('c', 70, daysAgo: 1, feedback: fall),
        );
        await h.treatments.saveSession(
          attempt('d', 65, daysAgo: 10, feedback: fall),
        );
        await h.vm.recommend(rehab);
        final progress = h.server.lastBody!['progress'] as Map;
        final plan = (progress['plans'] as List).single as Map;
        expect(plan['plan_id'], knee.planId);
        expect(plan['status'], 'ACTIVE');
        expect(plan['consecutive_fails'], 4);
        expect(plan['current_exercise_id'], ext);
        // The questionnaire names no plan: the server only ranks with it.
        expect(progress.containsKey('from_plan_id'), isFalse);
        expect(plan['fall_alerts'], 1); // the fall 10 days ago is too old
        final ex = (progress['exercises'] as List).single as Map;
        expect(ex['exercise_id'], ext);
        expect(ex['attempts'], 4);
        expect(ex['passes'], 0);
        expect(ex['mean_accuracy'], 62.5);
      },
    );

    test('an exercise saved for two plans counts once', () {
      final at = DateTime(2026, 10, 1, 9);
      ExerciseSession s(String plan) => ExerciseSession(
        sessionId: 's-$plan',
        accountId: 'a',
        patientPlanId: plan,
        exerciseId: 'e1',
        completedAt: at,
        completionStatus: CompletionStatus.completed,
        postureAccuracy: 90,
        repetitionsCompleted: 5,
      );
      final json = RecommendationService.progressJson((
        plans: const [],
        sessions: {
          'p1': [s('p1')],
          'p2': [s('p2')],
        },
      ));
      final ex = (json['exercises'] as List).single as Map;
      expect(ex['attempts'], 1);
      expect(ex['passes'], 1);
    });

    test(
      'Find my next plan answers with the plan and keeps the reason',
      () async {
        final h = Harness();
        final id = await h.signIn();
        final knee = await planNamed(h, 'Early Knee Recovery');
        final done = PatientTreatmentPlan(
          patientPlanId: 'pp1',
          accountId: id,
          plan: knee,
          progressPercentage: 100,
          status: PlanStatus.completed,
          selectedAt: DateTime(2026, 9, 1),
        );
        await h.treatments.assignPlan(done);
        h.server
          ..nextStep = 'PROGRESS'
          ..nextStepReason =
              'You completed Early Knee Recovery, so plans for the next stage are included.';
        await h.vm.recommendNext(done);
        final body = h.server.lastBody!;
        expect(body['rehab'], {
          'affected_body_area': 'BOTH_LEGS',
          'recovery_stage': 'EARLY',
          'mobility_level': 'LOW',
          'goal': 'MOBILITY',
        });
        final plans = (body['progress'] as Map)['plans'] as List;
        expect((plans.single as Map)['status'], 'COMPLETED');
        expect((body['progress'] as Map)['from_plan_id'], knee.planId);
        final r = (h.vm.recommendation as UiSuccess<Recommendation>).data;
        expect(r.nextStep, NextStep.progress);
        expect(r.nextStepReason, startsWith('You completed'));
        expect(h.vm.from, same(done));
        expect(h.vm.easingFrom, isNull); // nothing to replace after a step up
        // Try again keeps the next-step request.
        await h.vm.retry();
        expect(h.vm.from, same(done));
      },
    );

    test('an EASE step replaces the plan that is too hard', () async {
      final h = Harness();
      final id = await h.signIn();
      final hard = PatientTreatmentPlan(
        patientPlanId: 'pp1',
        accountId: id,
        plan: await planNamed(h, 'Lower Limb Strength Builder'),
        progressPercentage: 33.33,
        selectedAt: DateTime(2026, 9, 1),
      );
      await h.treatments.assignPlan(hard);
      h.server.nextStep = 'EASE';
      await h.vm.recommendNext(hard);
      expect(h.vm.easingFrom, 'pp1');
      // The checks treat pp1 as replaced: no issue is about it.
      for (final p in h.vm.candidates) {
        expect(
          h.vm.issuesFor(p).where((i) => i.patientPlanId == 'pp1'),
          isEmpty,
        );
      }
      // A new questionnaire forgets the plan it moved on from.
      await h.vm.recommend(rehab);
      expect(h.vm.from, isNull);
      expect(h.vm.easingFrom, isNull);
    });

    testWidgets('with no gentler plan the screen shows the server reason', (
      tester,
    ) async {
      final h = Harness()..server.n = 0;
      const why =
          'The current exercise in Core and Back Care did not pass 3 times in a '
          'row. No gentler plan for this area fits your safety limits, so keep '
          'to your current plan within a comfortable range and rest between '
          'tries, or ask a physiotherapist.';
      await tester.runAsync(() async {
        final id = await h.signIn();
        final core = PatientTreatmentPlan(
          patientPlanId: 'pp1',
          accountId: id,
          plan: await planNamed(h, 'Core and Back Care'),
          selectedAt: DateTime(2026, 9, 1),
        );
        await h.treatments.assignPlan(core);
        h.server
          ..nextStep = 'EASE'
          ..nextStepReason = why;
        await h.vm.recommendNext(core);
      });
      await tester.pumpWidget(
        MaterialApp(
          home: ChangeNotifierProvider.value(
            value: h.vm,
            child: const RecommendedPlansView(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text(why), findsOneWidget);
      expect(find.text(Messages.conditionNotMet), findsNothing);
      expect(find.text('Back'), findsOneWidget);
    });

    testWidgets('the plans screen says why and what the plan replaces', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1080, 3600);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      final h = Harness();
      const why =
          'The current exercise in Lower Limb Strength Builder did not pass 3 '
          'times in a row, so plans that should suit you better are shown.';
      await tester.runAsync(() async {
        final id = await h.signIn();
        final hard = PatientTreatmentPlan(
          patientPlanId: 'pp1',
          accountId: id,
          plan: await planNamed(h, 'Lower Limb Strength Builder'),
          progressPercentage: 33.33,
          selectedAt: DateTime(2026, 9, 1),
        );
        await h.treatments.assignPlan(hard);
        h.server
          ..nextStep = 'EASE'
          ..nextStepReason = why;
        await h.vm.recommendNext(hard);
      });
      await tester.pumpWidget(
        MaterialApp(
          home: ChangeNotifierProvider.value(
            value: h.vm,
            child: const RecommendedPlansView(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.text('Your next step after Lower Limb Strength Builder'),
        findsOneWidget,
      );
      expect(find.text(why), findsOneWidget);
      expect(
        find.text('Replaces Lower Limb Strength Builder for now.'),
        findsWidgets,
      );
      expect(tester.takeException(), isNull);
    });
  });
}

/// Saving a reminder fails, as when the connection drops right after the plan was saved.
class _NoReminders extends FakeNotificationRepository {
  @override
  Future<Result<void>> saveReminder(Reminder r) async =>
      const Failure('down', code: 'offline');
}
