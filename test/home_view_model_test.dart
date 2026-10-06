import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:physical_treatment_and_health_support_system/core/base/ui_state.dart';
import 'package:physical_treatment_and_health_support_system/core/constants/app_constants.dart';
import 'package:physical_treatment_and_health_support_system/core/services/profile_info_service.dart';
import 'package:physical_treatment_and_health_support_system/core/utils/id_utils.dart';
import 'package:physical_treatment_and_health_support_system/data/models/enums.dart';
import 'package:physical_treatment_and_health_support_system/data/models/exercise_session.dart';
import 'package:physical_treatment_and_health_support_system/data/models/health_profile.dart';
import 'package:physical_treatment_and_health_support_system/data/models/lookups.dart';
import 'package:physical_treatment_and_health_support_system/data/models/patient_treatment_plan.dart';
import 'package:physical_treatment_and_health_support_system/data/models/reminder.dart';
import 'package:physical_treatment_and_health_support_system/data/repository/fake/fake_auth_repository.dart';
import 'package:physical_treatment_and_health_support_system/data/repository/fake/fake_notification_repository.dart';
import 'package:physical_treatment_and_health_support_system/data/repository/fake/fake_profile_repository.dart';
import 'package:physical_treatment_and_health_support_system/data/repository/fake/fake_treatment_repository.dart';
import 'package:physical_treatment_and_health_support_system/features/home/viewmodel/home_view_model.dart';

final String catalogueJson = File('assets/seed/catalogue.json').readAsStringSync();

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
    accountId = (await auth.login('demo@apths.test', 'password123')).dataOrNull!.accountId;
    vm = HomeViewModel(auth, ProfileInfoService(auth, profiles), treatments, notifications,
        () => DateTime(2026, 10, 7, 9, 30));
  });

  Future<void> saveProfile({List<HealthCondition> conditions = const []}) async {
    final p = HealthProfile(
        profileId: newId(), accountId: accountId, age: 62, gender: Gender.male, weightKg: 71, heightCm: 168,
        conditions: conditions, updatedAt: DateTime.now());
    await profiles.saveProfile(p, p.generateSafetyLimit());
  }

  Future<PatientTreatmentPlan> assignPlan() async {
    final plan = PatientTreatmentPlan(
        patientPlanId: newId(),
        accountId: accountId,
        plan: (await treatments.getCatalogue()).dataOrNull!.first,
        selectedAt: DateTime.now());
    await treatments.assignPlan(plan);
    return plan;
  }

  test('a new patient: no profile, no plan, prompted to complete the profile', () async {
    await vm.load();
    final d = vm.data!;
    expect(d.username, 'demo');
    expect(d.profileNeedsAttention, isTrue);
    expect(HomeViewModel.riskPill(d), 'Complete your profile');
    expect(d.plan, isNull);
    // Fail-safe limits until the profile exists (UC1000 C5).
    expect(d.profile.safetyLimit.dailySodiumLimitMg, 1500);
  });

  test('risk pill and limits come from the saved profile', () async {
    await saveProfile(conditions: [LookupSeed.conditions[0]]); // hypertension -> High
    await vm.load();
    expect(HomeViewModel.riskPill(vm.data!), 'High risk · limits active');
    expect(vm.data!.profile.safetyLimit.maxExerciseIntensity, ExerciseIntensity.low);
  });

  test("today's session shows the plan's next exercise and its summary", () async {
    await saveProfile();
    final plan = await assignPlan();
    await vm.load();
    final d = vm.data!;
    expect(d.plan!.patientPlanId, plan.patientPlanId);
    expect(d.nextStage!.exerciseId, plan.plan.orderedExercises().first.exerciseId);
    expect(d.doneToday, isFalse);
    final summary = HomeViewModel.sessionSummary(plan.plan, (a) => a);
    expect(summary, startsWith('${plan.plan.exercises.length} exercise'));
    expect(summary, contains('min'));
  });

  test('a session completed today marks the day as done', () async {
    await saveProfile();
    final plan = await assignPlan();
    await treatments.saveSession(ExerciseSession(
      sessionId: newId(),
      accountId: accountId,
      patientPlanId: plan.patientPlanId,
      exerciseId: plan.plan.orderedExercises().first.exerciseId,
      completedAt: DateTime(2026, 10, 7, 8, 0),
      completionStatus: CompletionStatus.completed,
      postureAccuracy: 90,
    ));
    await vm.load();
    expect(vm.data!.doneToday, isTrue);
  });

  test('the bell shows the unread notification count', () async {
    await notifications.logNotification(NotificationLog(
        notificationId: newId(), accountId: accountId, notificationType: NotificationType.reminder,
        messageBody: 'Time for your exercise', deliveryStatus: DeliveryStatus.delivered, issuedAt: DateTime.now()));
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
    expect(HomeViewModel(auth, ProfileInfoService(auth, profiles), treatments, null, () => DateTime(2026, 1, 1, 15))
        .greeting(), 'Good afternoon');
    expect(HomeViewModel(auth, ProfileInfoService(auth, profiles), treatments, null, () => DateTime(2026, 1, 1, 20))
        .greeting(), 'Good evening');
  });
}
