// HomeView (Figma "Home") on the fakes: the session card in each state, the notices, the bell
// and the quick actions. NFR_17 coverage (22 Oct); the data rules are in home_view_model_test.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:physical_treatment_and_health_support_system/core/constants/app_constants.dart';
import 'package:physical_treatment_and_health_support_system/core/routes/routes.dart';
import 'package:physical_treatment_and_health_support_system/core/utils/id_utils.dart';
import 'package:physical_treatment_and_health_support_system/model/business_logic/risk_assessment_service/risk_assessment_service.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/enums.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/exercise_session.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/health_profile.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/lookups.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/patient_treatment_plan.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/reminder.dart';
import 'package:physical_treatment_and_health_support_system/model/repository/auth_repository/fake_auth_repository.dart';
import 'package:physical_treatment_and_health_support_system/model/repository/notification_repository/fake_notification_repository.dart';
import 'package:physical_treatment_and_health_support_system/model/repository/profile_repository/fake_profile_repository.dart';
import 'package:physical_treatment_and_health_support_system/model/repository/treatment_repository/fake_treatment_repository.dart';
import 'package:physical_treatment_and_health_support_system/view/home_view/home_view.dart';
import 'package:physical_treatment_and_health_support_system/viewmodel/home_view_model/home_view_model.dart';

final String _catalogue = File('assets/seed/catalogue.json').readAsStringSync();

Widget _stub(String name) =>
    Scaffold(appBar: AppBar(), body: Text('route:$name'));

class _Setup {
  final auth = FakeAuthRepository();
  final profiles = FakeProfileRepository();
  final treatments = FakeTreatmentRepository.fromJson(_catalogue);
  final notifications = FakeNotificationRepository();
  late final vm = HomeViewModel(
    auth,
    RiskAssessmentService(auth, profiles),
    treatments,
    notifications,
    () => DateTime(2026, 10, 7, 9, 30),
  );
  late String accountId;

  Future<void> signIn() async {
    accountId = (await auth.login(
      'demo@apths.test',
      'password123',
    )).dataOrNull!.accountId;
  }

  Future<void> profile({
    int age = 62,
    List<HealthCondition> conditions = const [],
  }) async {
    final p = HealthProfile(
      profileId: newId(),
      accountId: accountId,
      age: age,
      gender: Gender.male,
      weightKg: 71,
      heightCm: 168,
      conditions: conditions,
      updatedAt: DateTime.now(),
    );
    await profiles.saveProfile(p, p.generateSafetyLimit());
  }

  Future<PatientTreatmentPlan> plan(String name) async {
    final p = PatientTreatmentPlan(
      patientPlanId: newId(),
      accountId: accountId,
      plan: (await treatments.getCatalogue()).dataOrNull!.firstWhere(
        (c) => c.planName == name,
      ),
      selectedAt: DateTime.now(),
    );
    await treatments.assignPlan(p);
    return p;
  }

  Future<void> doneToday(PatientTreatmentPlan p, {double accuracy = 90}) =>
      treatments.saveSession(
        ExerciseSession(
          sessionId: newId(),
          accountId: accountId,
          patientPlanId: p.patientPlanId,
          exerciseId: p.plan.orderedExercises().first.exerciseId,
          completedAt: DateTime(2026, 10, 7, 8, 0),
          completionStatus: CompletionStatus.completed,
          postureAccuracy: accuracy,
        ),
      );

  Future<void> pump(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 6000);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: vm,
        child: MaterialApp(
          routes: {
            Routes.healthProfile: (_) => _stub('profile'),
            Routes.reminders: (_) => _stub('reminders'),
            Routes.physicalTreatment: (_) => _stub('treatment'),
            Routes.treatmentPlanning: (_) => _stub('planning'),
            Routes.ageLimit: (_) => _stub('age-limit'),
          },
          home: const Scaffold(body: HomeView()),
        ),
      ),
    );
    await tester.runAsync(vm.load); // the post-frame load, finished for real
    await tester.pump();
  }
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 300));
  }
}

Future<void> _openAndBack(WidgetTester tester, Finder f, String route) async {
  await tester.ensureVisible(f);
  await tester.tap(f);
  await _settle(tester);
  expect(find.text('route:$route'), findsOneWidget);
  await tester.pageBack();
  await _settle(tester);
  expect(find.text('route:$route'), findsNothing);
}

void main() {
  testWidgets('a new patient: complete-profile notice and Get a plan', (
    tester,
  ) async {
    final s = _Setup();
    await tester.runAsync(s.signIn);
    await s.pump(tester);
    expect(find.text('Good morning'), findsOneWidget);
    expect(find.text('Complete your profile'), findsOneWidget);
    expect(find.text(Messages.profileNotConfigured), findsOneWidget);
    expect(find.text('No treatment plan yet'), findsOneWidget);
    expect(find.text('Health Score'), findsOneWidget);
    await _openAndBack(tester, find.text('Get a plan'), 'planning');
    await _openAndBack(
      tester,
      find.text(Messages.profileNotConfigured),
      'profile',
    );
    await _openAndBack(tester, find.text('Complete your profile'), 'profile');
  });

  testWidgets('a plan to follow: Start and the next exercise', (tester) async {
    final s = _Setup();
    await tester.runAsync(() async {
      await s.signIn();
      await s.profile();
      await s.plan('Early Knee Recovery');
    });
    await s.pump(tester);
    expect(find.text('Early Knee Recovery'), findsOneWidget);
    expect(find.textContaining('Next: '), findsOneWidget);
    expect(find.text(Messages.profileNotConfigured), findsNothing);
    await _openAndBack(tester, find.text('Start'), 'treatment');
  });

  testWidgets("today's exercise done: View plan, no next exercise", (
    tester,
  ) async {
    final s = _Setup();
    await tester.runAsync(() async {
      await s.signIn();
      await s.profile();
      await s.doneToday(await s.plan('Early Knee Recovery'));
    });
    await s.pump(tester);
    expect(
      find.text("Today's exercise is done. Come back for the next one."),
      findsOneWidget,
    );
    expect(find.text('View plan'), findsOneWidget);
    expect(find.textContaining('Next: '), findsNothing);
  });

  testWidgets('two plans: how many are done today', (tester) async {
    final s = _Setup();
    await tester.runAsync(() async {
      await s.signIn();
      await s.profile();
      await s.doneToday(await s.plan('Early Knee Recovery'));
      await s.plan('Core and Back Care');
    });
    await s.pump(tester);
    expect(find.text('1 of 2 plans done today'), findsOneWidget);
    expect(find.text('Core and Back Care'), findsOneWidget);
  });

  testWidgets('too many plans for a High risk level: the plan notice', (
    tester,
  ) async {
    final s = _Setup();
    await tester.runAsync(() async {
      await s.signIn();
      await s.profile(conditions: [LookupSeed.conditions[0]]);
      await s.plan('Early Knee Recovery');
      await s.plan('Core and Back Care');
    });
    await s.pump(tester);
    final issue = s.vm.data!.planIssues.first.message;
    await _openAndBack(tester, find.text(issue), 'treatment');
  });

  testWidgets('65 and over: plans paused, Why opens the age-limit page', (
    tester,
  ) async {
    final s = _Setup();
    await tester.runAsync(() async {
      await s.signIn();
      await s.profile(age: 70);
    });
    await s.pump(tester);
    expect(find.text('No exercise plan'), findsOneWidget);
    await _openAndBack(tester, find.text('Why'), 'age-limit');
  });

  testWidgets('65 and over with a plan: shown as paused, progress kept', (
    tester,
  ) async {
    final s = _Setup();
    await tester.runAsync(() async {
      await s.signIn();
      await s.profile();
      await s.plan('Early Knee Recovery');
      await s.profile(age: 70);
    });
    await s.pump(tester);
    expect(find.textContaining('Paused: exercise plans'), findsOneWidget);
  });

  testWidgets('the bell shows unread reminders and opens them', (tester) async {
    final s = _Setup();
    await tester.runAsync(() async {
      await s.signIn();
      await s.profile();
      await s.notifications.logNotification(
        NotificationLog(
          notificationId: newId(),
          accountId: s.accountId,
          notificationType: NotificationType.reminder,
          messageBody: 'Time for your exercise',
          deliveryStatus: DeliveryStatus.delivered,
          issuedAt: DateTime.now(),
        ),
      );
    });
    await s.pump(tester);
    expect(find.byTooltip('Reminders, 1 unread'), findsOneWidget);
    await _openAndBack(
      tester,
      find.byTooltip('Reminders, 1 unread'),
      'reminders',
    );
  });

  testWidgets('Log Meal and Add Reading say their module is coming', (
    tester,
  ) async {
    final s = _Setup();
    await tester.runAsync(() async {
      await s.signIn();
      await s.profile();
    });
    await s.pump(tester);
    await tester.ensureVisible(find.text('Log Meal'));
    await tester.tap(find.text('Log Meal'));
    await tester.pump();
    expect(find.textContaining('Logging a meal is part of'), findsOneWidget);
    tester
        .state<ScaffoldMessengerState>(find.byType(ScaffoldMessenger))
        .removeCurrentSnackBar();
    await tester.pump();
    await tester.tap(find.text('Add Reading'));
    await tester.pump();
    expect(find.textContaining('Adding a reading is part of'), findsWidgets);
  });

  testWidgets('signed out: the session-expired message and Try again', (
    tester,
  ) async {
    final s = _Setup();
    await s.pump(tester);
    expect(find.text(Messages.sessionExpired), findsOneWidget);
    await tester.runAsync(s.signIn);
    await tester.tap(find.text('Try again'));
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await _settle(tester);
    await tester.runAsync(s.vm.load);
    await tester.pump();
    expect(find.text(Messages.sessionExpired), findsNothing);
  });

  testWidgets(
    'the header never runs into the Health Score card, with phone text at 1x and 2x (audit, 24 Oct)',
    (tester) async {
      for (final scale in [1.0, 1.5, 2.0]) {
        final s = _Setup();
        await tester.runAsync(s.signIn);
        tester.view.physicalSize = const Size(1080, 2400);
        tester.view.devicePixelRatio = 3; // 360 x 800
        addTearDown(tester.view.reset);
        await tester.pumpWidget(
          ChangeNotifierProvider.value(
            value: s.vm,
            child: MaterialApp(
              builder: (c, child) => MediaQuery(
                data: MediaQuery.of(c).copyWith(
                  textScaler: TextScaler.linear(scale),
                ),
                child: child!,
              ),
              home: const Scaffold(body: HomeView()),
            ),
          ),
        );
        await tester.runAsync(s.vm.load);
        await tester.pump();
        final pill = tester.getRect(find.text('Complete your profile'));
        final card = tester.getRect(
          find.ancestor(
            of: find.text('Health Score'),
            matching: find.byType(Container),
          ).first,
        );
        expect(pill.bottom, lessThanOrEqualTo(card.top), reason: 'scale $scale');
        // Never higher than the Figma's top + 176 (the header's minimum height).
        expect(card.top, greaterThanOrEqualTo(176));
        // The pill opens the profile: a 48 px touch target.
        final tap = find.ancestor(
          of: find.text('Complete your profile'),
          matching: find.byType(InkWell),
        );
        expect(tester.getSize(tap.first).height, greaterThanOrEqualTo(48));
        // The kcal figure ends at the card's right edge (it wraps only when it must).
        await tester.scrollUntilVisible(
          find.textContaining('kcal'),
          200,
          scrollable: find.byType(Scrollable).first,
        );
        final kcal = tester.getRect(find.textContaining('kcal'));
        final limits = tester.getRect(
          find
              .ancestor(
                of: find.text('Energy today'),
                matching: find.byType(Container),
              )
              .first,
        );
        expect(limits.right - kcal.right, closeTo(20, 1), reason: 'scale $scale');
        expect(tester.takeException(), isNull, reason: 'scale $scale');
      }
    },
  );

  testWidgets("the kcal figure stays at the card's right edge when it fits", (
    tester,
  ) async {
    final s = _Setup();
    await tester.runAsync(s.signIn);
    tester.view.physicalSize = const Size(1080, 3000);
    tester.view.devicePixelRatio = 1.5; // 720 wide: the figure fits in its half
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: s.vm,
        child: const MaterialApp(home: Scaffold(body: HomeView())),
      ),
    );
    await tester.runAsync(s.vm.load);
    await tester.pump();
    final kcal = tester.getRect(find.textContaining('kcal'));
    final card = tester.getRect(
      find
          .ancestor(of: find.text('Energy today'), matching: find.byType(Container))
          .first,
    );
    expect(card.right - kcal.right, closeTo(20, 1)); // before: a gap of about a quarter of the card
  });

  testWidgets('ComingSoonView names the tab', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: ComingSoonView('Diet')));
    expect(find.text('Diet'), findsOneWidget);
    expect(find.text('Coming soon'), findsOneWidget);
  });
}
