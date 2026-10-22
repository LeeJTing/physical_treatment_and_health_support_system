// A plan's exercise reminders end with the plan (audit, 23 Oct): stopping a plan only changed its
// status, and finishing it changed nothing, so "Time for ..." kept ringing for both.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:physical_treatment_and_health_support_system/model/business_logic/local_notification_service/local_notification_service.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/enums.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/reminder.dart';
import 'package:physical_treatment_and_health_support_system/model/repository/notification_repository/fake_notification_repository.dart';
import 'package:physical_treatment_and_health_support_system/viewmodel/treatment_view_model/treatment_view_model.dart';

import 'reminders_test.dart' show FakeScheduler;
import 'treatment_test.dart' show Harness;

void main() {
  late Directory tmp;
  setUp(() => tmp = Directory.systemTemp.createTempSync('apths'));
  tearDown(() => tmp.deleteSync(recursive: true));

  /// The Harness plan (pp1) with an exercise reminder scheduled on the phone, and a view model
  /// that knows the reminders.
  Future<
    (Harness, TreatmentViewModel, FakeNotificationRepository, FakeScheduler)
  >
  setUpWithReminder() async {
    final h = Harness();
    await h.setUp(tmp);
    final notes = FakeNotificationRepository();
    final device = FakeScheduler();
    final local = LocalNotificationService(
      notes,
      h.treatments,
      scheduler: device,
    );
    final plan = h.vm.activePlan!;
    final r = Reminder(
      reminderId: 'r1',
      accountId: plan.accountId,
      patientPlanId: plan.patientPlanId,
      reminderType: ReminderType.exercise,
      title: 'Time for ${plan.plan.planName}',
      hour: 9,
      minute: 0,
    );
    await notes.saveReminder(r);
    await local.schedule(r);
    expect(device.pending, isNotEmpty);
    final vm = TreatmentViewModel(h.treatments, h.pose, h.auth, notes, local);
    await vm.loadPlan();
    return (h, vm, notes, device);
  }

  test(
    'stopping a plan takes its reminders off the phone and out of the list',
    () async {
      final (_, vm, notes, device) = await setUpWithReminder();
      expect(await vm.endPlan(), isTrue);
      expect(device.pending, isEmpty);
      expect(notes.reminders, isEmpty);
    },
  );

  test('finishing a plan does the same', () async {
    final (h, vm, notes, device) = await setUpWithReminder();
    h.server.accuracy = 90; // every exercise passes and moves the plan on
    while (vm.activePlan!.status != PlanStatus.completed) {
      await vm.startExercise(vm.activePlan!.currentExercise()!);
      await vm.submitVideo(h.clip, clipSeconds: 15);
    }
    expect(device.pending, isEmpty);
    expect(notes.reminders, isEmpty);
  });
}
