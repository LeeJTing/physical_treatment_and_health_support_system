import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:physical_treatment_and_health_support_system/viewmodel/ui_state.dart';
import 'package:physical_treatment_and_health_support_system/core/constants/app_constants.dart';
import 'package:physical_treatment_and_health_support_system/model/business_logic/risk_assessment_service/risk_assessment_service.dart';
import 'package:physical_treatment_and_health_support_system/core/utils/id_utils.dart';
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
import 'package:physical_treatment_and_health_support_system/viewmodel/home_view_model/home_view_model.dart';

final String catalogueJson = File(
  'assets/seed/catalogue.json',
).readAsStringSync();

void main() {
  late FakeAuthRepository auth;
  late FakeProfileRepository profiles;
  late FakeTreatmentRepository treatments;
  late FakeNotificationRepository notifications;
  late HomeViewModel vm;
  late String accountId;

  setUp(() async {
    auth = FakeAuthRepository();
    profiles = FakeProfileRepository();
    treatments = FakeTreatmentRepository.fromJson(catalogueJson);
    notifications = FakeNotificationRepository();
    accountId = (await auth.login(
      'demo@apths.test',
      'password123',
    )).dataOrNull!.accountId;
    vm = HomeViewModel(
      auth,
      RiskAssessmentService(auth, profiles),
      treatments,
      notifications,
      () => DateTime(2026, 10, 7, 9, 30),
    );
  });

  Future<void> saveProfile({
    List<HealthCondition> conditions = const [],
  }) async {
    final p = HealthProfile(
      profileId: newId(),
      accountId: accountId,
      age: 62,
      gender: Gender.male,
      weightKg: 71,
      heightCm: 168,
      conditions: conditions,
      updatedAt: DateTime.now(),
    );
    await profiles.saveProfile(p, p.generateSafetyLimit());
  }

  Future<PatientTreatmentPlan> assignPlan() async {
    final plan = PatientTreatmentPlan(
      patientPlanId: newId(),
      accountId: accountId,
      plan: (await treatments.getCatalogue()).dataOrNull!.first,
      selectedAt: DateTime.now(),
    );
    await treatments.assignPlan(plan);
    return plan;
  }

  test(
    'a new patient: no profile, no plan, prompted to complete the profile',
    () async {
      await vm.load();
      final d = vm.data!;
      expect(d.username, 'demo');
      expect(d.profileNeedsAttention, isTrue);
      expect(HomeViewModel.riskPill(d), 'Complete your profile');
      expect(d.plan, isNull);
      // Fail-safe limits until the profile exists (UC1000 C5).
      expect(d.profile.safetyLimit.dailySodiumLimitMg, 1500);
    },
  );

  test('risk pill and limits come from the saved profile', () async {
    await saveProfile(
      conditions: [LookupSeed.conditions[0]],
    ); // hypertension -> High
    await vm.load();
    expect(HomeViewModel.riskPill(vm.data!), 'High risk · limits active');
    expect(
      vm.data!.profile.safetyLimit.maxExerciseIntensity,
      ExerciseIntensity.low,
    );
  });

  test(
    "today's session shows the plan's next exercise and its summary",
    () async {
      await saveProfile();
      final plan = await assignPlan();
      await vm.load();
      final d = vm.data!;
      expect(d.plan!.patientPlanId, plan.patientPlanId);
      expect(
        d.nextStage!.exerciseId,
        plan.plan.orderedExercises().first.exerciseId,
      );
      expect(d.doneToday, isFalse);
      final summary = HomeViewModel.sessionSummary(plan, d.nextStage!, (a) => a);
      // A day is one exercise: today's time, not every exercise added up (audit, 24 Oct).
      final first = plan.plan.orderedExercises().first;
      final min = (first.prescribedDurationSec / 60).ceil().clamp(1, 60);
      expect(
        summary,
        'Exercise 1 of ${plan.plan.exercises.length} · about $min min · '
        '${plan.plan.targetBodyArea}',
      );
    },
  );

  test('a session completed today marks the day as done', () async {
    await saveProfile();
    final plan = await assignPlan();
    await treatments.saveSession(
      ExerciseSession(
        sessionId: newId(),
        accountId: accountId,
        patientPlanId: plan.patientPlanId,
        exerciseId: plan.plan.orderedExercises().first.exerciseId,
        completedAt: DateTime(2026, 10, 7, 8, 0),
        completionStatus: CompletionStatus.completed,
        postureAccuracy: 90,
      ),
    );
    await vm.load();
    expect(vm.data!.doneToday, isTrue);
  });

  Future<PatientTreatmentPlan> assignNamed(String name) async {
    final plan = PatientTreatmentPlan(
      patientPlanId: newId(),
      accountId: accountId,
      plan: (await treatments.getCatalogue()).dataOrNull!.firstWhere(
        (p) => p.planName == name,
      ),
      selectedAt: DateTime.now(),
    );
    await treatments.assignPlan(plan);
    return plan;
  }

  test('two plans: the card shows the one still open today', () async {
    await saveProfile();
    final knee = await assignNamed('Early Knee Recovery');
    final core = await assignNamed('Core and Back Care');
    await treatments.saveSession(
      ExerciseSession(
        sessionId: newId(),
        accountId: accountId,
        patientPlanId: knee.patientPlanId,
        exerciseId: knee.plan.orderedExercises().first.exerciseId,
        completedAt: DateTime(2026, 10, 7, 8, 0),
        completionStatus: CompletionStatus.completed,
        postureAccuracy: 90,
      ),
    );
    await vm.load();
    final d = vm.data!;
    expect(d.planCount, 2);
    expect(d.plansDoneToday, 1);
    expect(d.plan!.patientPlanId, core.patientPlanId);
    expect(d.doneToday, isFalse);
    expect(d.planIssues, isEmpty);
  });

  test('more plans than a new High risk level allows is flagged', () async {
    await saveProfile(
      conditions: [LookupSeed.conditions[0]],
    ); // hypertension -> High: one plan at a time
    await assignNamed('Early Knee Recovery');
    await assignNamed('Core and Back Care');
    await vm.load();
    expect([for (final i in vm.data!.planIssues) i.code], contains('over_cap'));
  });

  test(
    'a condition waiting for a doctor OK is the first plan notice (23 Oct)',
    () async {
      final heart = LookupSeed.conditions
          .firstWhere((c) => c.needsClearance)
          .withStatus(controlled: false);
      await saveProfile(conditions: [heart]);
      await assignPlan();
      await vm.load();
      expect(vm.data!.planIssues.first.code, 'clearance_now');
    },
  );

  test('the bell shows the unread notification count', () async {
    await notifications.logNotification(
      NotificationLog(
        notificationId: newId(),
        accountId: accountId,
        notificationType: NotificationType.reminder,
        messageBody: 'Time for your exercise',
        deliveryStatus: DeliveryStatus.delivered,
        issuedAt: DateTime.now(),
      ),
    );
    await vm.load();
    expect(vm.data!.unread, 1);
  });

  test('signed out shows the session-expired message', () async {
    await auth.signOut();
    await vm.load();
    expect((vm.state as UiError).message, Messages.sessionExpired);
  });

  test('greeting follows the time of day', () {
    expect(vm.greeting(), 'Good morning');
    expect(
      HomeViewModel(
        auth,
        RiskAssessmentService(auth, profiles),
        treatments,
        null,
        () => DateTime(2026, 1, 1, 15),
      ).greeting(),
      'Good afternoon',
    );
    expect(
      HomeViewModel(
        auth,
        RiskAssessmentService(auth, profiles),
        treatments,
        null,
        () => DateTime(2026, 1, 1, 20),
      ).greeting(),
      'Good evening',
    );
    // After midnight (phone test, 8 Oct): not "Good morning" at 00:30.
    expect(
      HomeViewModel(
        auth,
        RiskAssessmentService(auth, profiles),
        treatments,
        null,
        () => DateTime(2026, 1, 1, 0, 30),
      ).greeting(),
      'Hello',
    );
  });
}
