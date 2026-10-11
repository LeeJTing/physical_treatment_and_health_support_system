// Plans stop at 65 (Terms of Use, section 2) and every plan says why it was, or was not,
// recommended, with its sources (11 Oct; server: hybrid-3.1 + explain.py, chat-rules-3.49).
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';

import 'package:physical_treatment_and_health_support_system/core/constants/evidence_sources.dart';
import 'package:physical_treatment_and_health_support_system/core/routes/routes.dart';
import 'package:physical_treatment_and_health_support_system/model/business_logic/chatbot_service/chatbot_service.dart';
import 'package:physical_treatment_and_health_support_system/model/business_logic/local_notification_service/local_notification_service.dart';
import 'package:physical_treatment_and_health_support_system/model/business_logic/pose_estimation_service/pose_estimation_service.dart';
import 'package:physical_treatment_and_health_support_system/model/business_logic/recommendation_service/recommendation.dart';
import 'package:physical_treatment_and_health_support_system/model/business_logic/recommendation_service/recommendation_service.dart';
import 'package:physical_treatment_and_health_support_system/model/business_logic/risk_assessment_service/risk_assessment_service.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/enums.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/health_profile.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/lookups.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/patient_treatment_plan.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/rehab_info.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/reminder.dart';
import 'package:physical_treatment_and_health_support_system/model/repository/auth_repository/fake_auth_repository.dart';
import 'package:physical_treatment_and_health_support_system/model/repository/notification_repository/fake_notification_repository.dart';
import 'package:physical_treatment_and_health_support_system/model/repository/profile_repository/fake_profile_repository.dart';
import 'package:physical_treatment_and_health_support_system/model/repository/treatment_repository/fake_treatment_repository.dart';
import 'package:physical_treatment_and_health_support_system/shared_client/api_client/api_client.dart';
import 'package:physical_treatment_and_health_support_system/view/planning_view/age_limit_view.dart';
import 'package:physical_treatment_and_health_support_system/view/planning_view/recommended_plans_view.dart';
import 'package:physical_treatment_and_health_support_system/viewmodel/planning_view_model/planning_view_model.dart';
import 'package:physical_treatment_and_health_support_system/viewmodel/treatment_view_model/treatment_view_model.dart';
import 'package:physical_treatment_and_health_support_system/viewmodel/ui_state.dart';

import 'reminders_test.dart' show FakeScheduler;

final String catalogueJson = File(
  'assets/seed/catalogue.json',
).readAsStringSync();

const rehab = RehabInfo(
  affectedBodyArea: 'BOTH_LEGS',
  recoveryStage: RecoveryStage.early,
  mobilityLevel: MobilityLevel.low,
  goal: 'MOBILITY',
);

/// /recommend and /chat as the server answers them since 11 Oct; records what
/// the app sends.
class FakeServer {
  final List<Map<String, dynamic>> bodies = [];
  final List<Map<String, String>> queries = [];
  String? restriction;

  late final client = MockClient((req) async {
    queries.add(req.url.queryParameters);
    if (req.method == 'GET') {
      return http.Response(
        jsonEncode({'plan_id': null, 'categories': [], 'rules_version': 't'}),
        200,
      );
    }
    final body = jsonDecode(req.body) as Map<String, dynamic>;
    bodies.add(body);
    if (req.url.path.endsWith('/chat')) {
      return http.Response(
        jsonEncode({
          'answer': 'ok',
          'category': 'x',
          'is_matched': true,
          'categories': [],
          'rules_version': 't',
        }),
        200,
      );
    }
    final plans = (body['plans'] as List).cast<Map<String, dynamic>>();
    return http.Response(
      jsonEncode({
        'status': restriction == null ? 'OK' : 'NONE',
        'ranked': restriction != null
            ? []
            : [
                for (final p in plans.take(2))
                  {
                    'plan_id': p['plan_id'],
                    'suitability_score': 0.8,
                    'why': [
                      {'code': 'MATCH_AREA', 'text': 'It trains your legs.'},
                      {
                        'code': 'SAFE',
                        'text':
                            'Every exercise stays within your effort limit.',
                        'sources': ['otago2003'],
                      },
                    ],
                  },
              ],
        'excluded': [
          for (final p in plans.skip(restriction == null ? 2 : 0))
            {
              'plan_id': p['plan_id'],
              'reasons': ['none of its exercises trains BOTH_LEGS'],
              'why': [
                {
                  'code': 'NOT_AREA',
                  'text': 'None of its exercises trains your legs.',
                  'sources': [],
                },
              ],
            },
        ],
        'suitable_count': 2,
        'model_version': 'hybrid-3.1',
        'next_step': 'START',
        'next_step_reason': '',
        'restriction': restriction,
      }),
      200,
    );
  });

  late final api = ApiClient(
    baseUrl: 'http://ai',
    tokenProvider: () => 'dev-token',
    httpClient: client,
  );
}

class Harness {
  final server = FakeServer();
  final auth = FakeAuthRepository();
  final profiles = FakeProfileRepository();
  final treatments = FakeTreatmentRepository.fromJson(catalogueJson);
  late final risk = RiskAssessmentService(auth, profiles);
  late final planning = PlanningViewModel(
    treatments,
    RecommendationService(server.api),
    risk,
    FakeNotificationRepository(),
  );

  Future<String> signIn(int age) async {
    final account = (await auth.login(
      'demo@apths.test',
      'password123',
    )).dataOrNull!;
    final p = HealthProfile(
      profileId: 'p1',
      accountId: account.accountId,
      age: age,
      gender: Gender.female,
      weightKg: 60,
      heightCm: 160,
      conditions: [LookupSeed.conditions.first], // HYPERTENSION
      updatedAt: DateTime.now(),
    );
    await profiles.saveProfile(p, p.generateSafetyLimit());
    return account.accountId;
  }

  Future<PatientTreatmentPlan> follow(String accountId) async {
    final plan = (await treatments.getCatalogue()).dataOrNull!.firstWhere(
      (p) => p.planName == 'Early Knee Recovery',
    );
    final a = PatientTreatmentPlan(
      patientPlanId: 'pp1',
      accountId: accountId,
      plan: plan,
      selectedAt: DateTime.now(),
    );
    await treatments.assignPlan(a);
    return a;
  }
}

void main() {
  group('plans stop at 65', () {
    test('the limit is 65 and needs a known age', () {
      expect(PlanRestriction.forAge(64), isNull);
      expect(PlanRestriction.forAge(65), PlanRestriction.age65Plus);
      expect(PlanRestriction.forAge(null), isNull);
      expect(
        PlanRestriction.fromWire('AGE_65_PLUS'),
        PlanRestriction.age65Plus,
      );
      expect(PlanRestriction.fromWire(null), isNull);
    });

    test('from 65 no plan is requested, also for the next plan', () async {
      final h = Harness();
      final id = await h.signIn(65);
      expect(await h.planning.checkRestriction(), PlanRestriction.age65Plus);
      expect(h.planning.age, 65);
      await h.planning.recommend(rehab);
      final r = (h.planning.recommendation as UiSuccess<Recommendation>).data;
      expect(r.restriction, PlanRestriction.age65Plus);
      expect(r.plans, isEmpty);
      await h.planning.recommendNext(await h.follow(id));
      expect(
        (h.planning.recommendation as UiSuccess<Recommendation>)
            .data
            .restriction,
        PlanRestriction.age65Plus,
      );
      expect(h.server.bodies, isEmpty);
    });

    test('at 64 the request carries the age and the conditions', () async {
      final h = Harness();
      await h.signIn(64);
      expect(await h.planning.checkRestriction(), isNull);
      await h.planning.recommend(rehab);
      final sent = h.server.bodies.single;
      expect(sent['age'], 64);
      expect(sent['conditions'], ['HYPERTENSION']);
    });

    test('a restriction from the server is read too', () async {
      final h = Harness()..server.restriction = 'AGE_65_PLUS';
      await h.signIn(50);
      await h.planning.recommend(rehab);
      final r = (h.planning.recommendation as UiSuccess<Recommendation>).data;
      expect(r.restriction, PlanRestriction.age65Plus);
      expect(r.excluded, isNotEmpty);
    });

    test('a followed plan is paused: nothing can be started', () async {
      final h = Harness();
      final id = await h.signIn(70);
      await h.follow(id);
      final vm = TreatmentViewModel(
        h.treatments,
        PoseEstimationService(h.server.api),
        h.auth,
        null,
        null,
        h.risk,
      );
      await vm.loadPlan();
      expect(vm.restriction, PlanRestriction.age65Plus);
      expect(vm.age, 70);
      expect(vm.activePlan, isNotNull); // kept, not deleted
      expect(
        vm.canStart(vm.activePlan!.currentExercise()!.exerciseId),
        isFalse,
      );
      expect(vm.suggestEasier, isFalse);
    });

    test(
      'exercise reminders stop ringing; health-log reminders still ring',
      () async {
        final device = FakeScheduler();
        var age = 70;
        final local = LocalNotificationService(
          FakeNotificationRepository(),
          FakeTreatmentRepository(const []),
          scheduler: device,
          now: () => DateTime(2026, 10, 12, 7),
          profileAge: () async => age,
        );
        Reminder r(ReminderType t) => Reminder(
          reminderId: t.name,
          accountId: 'a1',
          patientPlanId: t == ReminderType.exercise ? 'pp1' : null,
          reminderType: t,
          title: 'x',
          hour: 9,
          minute: 0,
        );
        expect(await local.schedule(r(ReminderType.exercise)), 0);
        expect(await local.schedule(r(ReminderType.healthLog)), greaterThan(0));
        age = 64;
        expect(await local.schedule(r(ReminderType.exercise)), greaterThan(0));
      },
    );

    test('the chat is told about the restriction', () async {
      final s = FakeServer();
      final chat = ChatbotService(s.api);
      final h = Harness();
      await h.signIn(70);
      final old = (await h.risk.retrieve()).dataOrNull!;
      await chat.ask(text: 'how do I start', profile: old);
      expect(s.bodies.last['restriction'], 'AGE_65_PLUS');
      await chat.categoriesFor(null, age: 70);
      expect(s.queries.last['restriction'], 'AGE_65_PLUS');
      await chat.categoriesFor(null, age: 40);
      expect(s.queries.last.containsKey('restriction'), isFalse);
    });
  });

  group('why this plan, why not', () {
    test('the reasons and their sources are read', () async {
      final h = Harness();
      await h.signIn(50);
      await h.planning.recommend(rehab);
      final r = (h.planning.recommendation as UiSuccess<Recommendation>).data;
      final why = r.why[r.plans.first.planId]!;
      expect(why.map((w) => w.code), ['MATCH_AREA', 'SAFE']);
      expect(why.first.sources, isEmpty);
      expect(why.last.sources, ['otago2003']);
      expect(r.excluded.first.why.single.code, 'NOT_AREA');
    });

    test('sources are cited by name; none means an app safety rule', () {
      expect(EvidenceSources.cite(const []), EvidenceSources.appRuleLabel);
      expect(
        EvidenceSources.cite(const ['otago2003']),
        'Campbell & Robertson (2003)',
      );
      expect(
        EvidenceSources.cite(const ['unknown', 'hk_doh']),
        'Department of Health, Hong Kong (n.d.)',
      );
    });

    Future<Harness> pumpPlans(
      WidgetTester tester,
      int age, {
      String? restriction,
    }) async {
      tester.view.physicalSize = const Size(1080, 4200);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      final h = Harness()..server.restriction = restriction;
      await tester.runAsync(() async {
        await h.signIn(age);
        await h.planning.recommend(rehab);
      });
      await tester.pumpWidget(
        MaterialApp(
          routes: {
            Routes.ageLimit: (ctx) => AgeLimitView(
              age: ModalRoute.of(ctx)?.settings.arguments as int?,
            ),
          },
          home: ChangeNotifierProvider.value(
            value: h.planning,
            child: const RecommendedPlansView(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      return h;
    }

    testWidgets('each plan opens "Why this plan"; the others say why not', (
      tester,
    ) async {
      await pumpPlans(tester, 50);
      expect(find.text('Why this plan'), findsNWidgets(2));
      await tester.tap(find.text('Why this plan').first);
      await tester.pumpAndSettle();
      expect(find.text('It trains your legs.'), findsOneWidget);
      expect(find.text(EvidenceSources.appRuleLabel), findsOneWidget);
      expect(find.text('Source: Campbell & Robertson (2003)'), findsOneWidget);
      await tester.ensureVisible(find.textContaining('Why not the other'));
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('Why not the other'));
      await tester.pumpAndSettle();
      expect(find.text('Why not other plans'), findsOneWidget);
      expect(
        find.text('None of its exercises trains your legs.'),
        findsWidgets,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('from 65 the plans page explains and opens the age-limit page', (
      tester,
    ) async {
      await pumpPlans(tester, 70);
      expect(
        find.text(
          'Exercise plans are for users under 65, as stated in the Terms of Use (section 2).',
        ),
        findsOneWidget,
      );
      await tester.tap(find.text('Why'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Your profile says you are 70.'),
        findsOneWidget,
      );
      expect(find.textContaining('Terms of Use (section 2)'), findsWidgets);
      // Below the fold on a phone-sized test screen.
      await tester.ensureVisible(find.text('Sources'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Sources'));
      await tester.pumpAndSettle();
      expect(find.text('Lacroix et al. (2017)'), findsOneWidget);
      expect(find.text('Campbell & Robertson (2003)'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
