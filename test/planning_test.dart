import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';

import 'package:physical_treatment_and_health_support_system/core/base/result.dart';
import 'package:physical_treatment_and_health_support_system/core/base/ui_state.dart';
import 'package:physical_treatment_and_health_support_system/core/constants/app_constants.dart';
import 'package:physical_treatment_and_health_support_system/core/services/api_client.dart';
import 'package:physical_treatment_and_health_support_system/core/services/profile_info_service.dart';
import 'package:physical_treatment_and_health_support_system/core/services/recommendation_service.dart';
import 'package:physical_treatment_and_health_support_system/data/models/enums.dart';
import 'package:physical_treatment_and_health_support_system/data/models/health_profile.dart';
import 'package:physical_treatment_and_health_support_system/data/models/lookups.dart';
import 'package:physical_treatment_and_health_support_system/data/models/rehab_info.dart';
import 'package:physical_treatment_and_health_support_system/data/models/treatment_plan.dart';
import 'package:physical_treatment_and_health_support_system/data/repository/fake/fake_auth_repository.dart';
import 'package:physical_treatment_and_health_support_system/data/repository/fake/fake_notification_repository.dart';
import 'package:physical_treatment_and_health_support_system/data/repository/fake/fake_profile_repository.dart';
import 'package:physical_treatment_and_health_support_system/data/repository/fake/fake_treatment_repository.dart';
import 'package:physical_treatment_and_health_support_system/data/repository/interfaces/i_treatment_repository.dart';
import 'package:physical_treatment_and_health_support_system/features/planning/model/recommendation.dart';
import 'package:physical_treatment_and_health_support_system/features/planning/view/recommended_plans_view.dart';
import 'package:physical_treatment_and_health_support_system/features/planning/viewmodel/planning_view_model.dart';

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
      ProfileInfoService(auth, profiles),
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

  group('PlanningViewModel', () {
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
