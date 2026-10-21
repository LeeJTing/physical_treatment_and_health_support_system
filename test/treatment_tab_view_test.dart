// TreatmentTabView (UI Design, Treatment Screen) on the fakes: with and without a plan, the
// progress overview and next reminder, the testing-mode card, and each card's screen.
// NFR_17 coverage (22 Oct).
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:physical_treatment_and_health_support_system/core/routes/routes.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/enums.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/reminder.dart';
import 'package:physical_treatment_and_health_support_system/model/repository/notification_repository/fake_notification_repository.dart';
import 'package:physical_treatment_and_health_support_system/view/treatment_view/treatment_tab_view.dart';
import 'package:physical_treatment_and_health_support_system/viewmodel/test_mode_view_model/test_mode_view_model.dart';
import 'package:physical_treatment_and_health_support_system/viewmodel/treatment_view_model/treatment_view_model.dart';

import 'treatment_test.dart' show Harness;

void main() {
  late Directory tmp;
  setUp(() => tmp = Directory.systemTemp.createTempSync('apths'));
  tearDown(() => tmp.deleteSync(recursive: true));

  /// The tab with the Harness plan (Early Knee Recovery), or none with [noPlan]; with
  /// [reminderHour] an exercise reminder for the plan, every day.
  Future<(Harness, TreatmentViewModel, TestModeViewModel)> open(
    WidgetTester tester, {
    bool noPlan = false,
    int? reminderHour,
    bool testing = false,
  }) async {
    tester.view.physicalSize = const Size(1080, 6000);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final h = Harness();
    final notifications = FakeNotificationRepository();
    late TreatmentViewModel vm;
    await tester.runAsync(() async {
      await h.setUp(tmp);
      final plan = h.vm.activePlan!;
      if (noPlan) await h.treatments.endPlan(plan);
      if (reminderHour != null) {
        await notifications.saveReminder(
          Reminder(
            reminderId: 'r1',
            accountId: plan.accountId,
            patientPlanId: plan.patientPlanId,
            reminderType: ReminderType.exercise,
            title: 'Time for your exercise',
            hour: reminderHour,
            minute: 30,
          ),
        );
      }
      vm = TreatmentViewModel(h.treatments, h.pose, h.auth, notifications);
      await vm.loadPlan();
    });
    final tm = TestModeViewModel()..setEnabled(testing);
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: vm),
          ChangeNotifierProvider.value(value: tm),
        ],
        child: MaterialApp(
          routes: {
            Routes.treatmentPlanning: (_) =>
                Scaffold(appBar: AppBar(), body: const Text('route:planning')),
          },
          home: const Scaffold(body: TreatmentTabView()),
        ),
      ),
    );
    await tester.runAsync(
      vm.loadPlan,
    ); // the post-frame load, finished for real
    await tester.pump();
    return (h, vm, tm);
  }

  Future<void> settle(WidgetTester tester) async {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 300));
    }
  }

  testWidgets('no plan: get one below, and the planning screen opens', (
    tester,
  ) async {
    await open(tester, noPlan: true);
    expect(find.text('No plan yet: get one below'), findsOneWidget);
    expect(find.text('Session history'), findsNothing);
    expect(find.text('Progress overview'), findsNothing);
    expect(find.byKey(const Key('test_mode_card')), findsNothing);
    await tester.tap(find.text('AI-assisted treatment planning'));
    await settle(tester);
    expect(find.text('route:planning'), findsOneWidget);
    await tester.pageBack();
    await settle(tester);
    expect(find.text('Treatment'), findsOneWidget);
  });

  testWidgets('a plan: progress overview and the next reminder', (
    tester,
  ) async {
    final (_, vm, _) = await open(tester, reminderHour: 23);
    expect(
      find.text('View pathway, do exercises, check posture'),
      findsOneWidget,
    );
    expect(find.text('Progress overview'), findsOneWidget);
    expect(find.text('Early Knee Recovery'), findsOneWidget);
    expect(find.text('Started today'), findsOneWidget);
    expect(find.textContaining('x a week'), findsOneWidget);
    expect(vm.nextReminderAt, isNotNull);
    expect(
      find.textContaining(RegExp(r'^(Today|Tomorrow), 11:30 PM · ')),
      findsOneWidget,
    );
    expect(find.text('Your posture results will appear here'), findsOneWidget);
  });

  testWidgets('a plan without reminders says so', (tester) async {
    await open(tester);
    expect(find.text('No reminder scheduled'), findsOneWidget);
  });

  testWidgets('a reminder in the morning shows its time with AM', (
    tester,
  ) async {
    await open(tester, reminderHour: 0);
    expect(find.textContaining('12:30 AM'), findsOneWidget);
  });

  testWidgets('My treatment plan and Session history open their screens', (
    tester,
  ) async {
    await open(tester);
    await tester.tap(find.text('My treatment plan'));
    await settle(tester);
    expect(find.text('Seated Knee Extension'), findsWidgets);
    await tester.pageBack();
    await settle(tester);
    await tester.tap(find.text('Session history'));
    await settle(tester);
    expect(find.text('Treatment'), findsNothing);
    await tester.pageBack();
    await settle(tester);
    expect(find.text('Treatment'), findsOneWidget);
  });

  testWidgets('testing mode: the card opens the list; back ends the test', (
    tester,
  ) async {
    final (_, vm, _) = await open(tester, testing: true);
    expect(find.byKey(const Key('test_mode_card')), findsOneWidget);
    await tester.tap(find.byKey(const Key('test_mode_card')));
    await settle(tester);
    expect(find.byKey(const Key('test_mode_notice')), findsOneWidget);
    await tester.pageBack();
    await settle(tester);
    expect(vm.testing, isFalse);
    expect(find.byKey(const Key('test_mode_card')), findsOneWidget);
  });
}
