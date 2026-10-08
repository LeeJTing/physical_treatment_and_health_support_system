import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';

import 'package:physical_treatment_and_health_support_system/model/result.dart';
import 'package:physical_treatment_and_health_support_system/viewmodel/ui_state.dart';
import 'package:physical_treatment_and_health_support_system/core/constants/app_constants.dart';
import 'package:physical_treatment_and_health_support_system/shared_client/api_client/api_client.dart';
import 'package:physical_treatment_and_health_support_system/model/business_logic/risk_assessment_service/risk_assessment_service.dart';
import 'package:physical_treatment_and_health_support_system/model/business_logic/recommendation_service/recommendation_service.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/enums.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/health_profile.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/lookups.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/rehab_info.dart';
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
        expect((body['plans'] as List).length, 10);
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
    Future<Harness> pump(WidgetTester tester, {int n = 3}) async {
      // Phone width, tall enough that all three cards (with their body
      // thumbnails) are built by the ListView.
      tester.view.physicalSize = const Size(1080, 3600);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      final h = Harness()..server.n = n;
      await tester.runAsync(() async {
        await h.signIn();
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
}
