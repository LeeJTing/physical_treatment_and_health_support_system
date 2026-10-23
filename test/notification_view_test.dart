// NotificationView (M600.1 Reminders) on the fakes: the reminder cards (switch, days, time,
// delete), the permission notices, the health-log reminder and the notification log.
// NFR_17 coverage (22 Oct); the scheduling rules are in reminders_test.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:physical_treatment_and_health_support_system/core/constants/app_constants.dart';
import 'package:physical_treatment_and_health_support_system/core/routes/routes.dart';
import 'package:physical_treatment_and_health_support_system/model/business_logic/local_notification_service/local_notification_service.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/enums.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/reminder.dart';
import 'package:physical_treatment_and_health_support_system/model/repository/auth_repository/fake_auth_repository.dart';
import 'package:physical_treatment_and_health_support_system/model/repository/notification_repository/fake_notification_repository.dart';
import 'package:physical_treatment_and_health_support_system/model/repository/treatment_repository/fake_treatment_repository.dart';
import 'package:physical_treatment_and_health_support_system/view/notification_view/notification_view.dart';
import 'package:physical_treatment_and_health_support_system/viewmodel/notification_view_model/notification_view_model.dart';
import 'package:physical_treatment_and_health_support_system/viewmodel/ui_state.dart';

import 'reminders_test.dart' show FakeScheduler;

class _Setup {
  final auth = FakeAuthRepository();
  final repo = FakeNotificationRepository();
  final device = FakeScheduler();
  late final service = LocalNotificationService(
    repo,
    FakeTreatmentRepository(const []),
    scheduler: device,
  );
  late final vm = NotificationViewModel(repo, service, auth);
  late String accountId;

  Future<void> signIn() async {
    accountId = (await auth.login(
      'demo@apths.test',
      'password123',
    )).dataOrNull!.accountId;
  }

  Future<void> exerciseReminder({String days = '1010100'}) => repo.saveReminder(
    Reminder(
      reminderId: 'r1',
      accountId: accountId,
      patientPlanId: 'pp1',
      reminderType: ReminderType.exercise,
      title: 'Time for Early Knee Recovery',
      hour: 9,
      minute: 0,
      repeatDays: days,
    ),
  );

  Future<void> healthReminder() => repo.saveReminder(
    Reminder(
      reminderId: 'h1',
      accountId: accountId,
      reminderType: ReminderType.healthLog,
      title: 'Log your health readings',
      hour: 20,
      minute: 0,
    ),
  );

  Future<void> logged(String body, {bool read = false}) => repo.logNotification(
    NotificationLog(
      notificationId: body,
      accountId: accountId,
      notificationType: NotificationType.reminder,
      messageBody: body,
      deliveryStatus: DeliveryStatus.delivered,
      isRead: read,
      issuedAt: DateTime.now().subtract(const Duration(hours: 1)),
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
            Routes.physicalTreatment: (c) => Scaffold(
              body: Text(
                'route:treatment ${ModalRoute.of(c)!.settings.arguments}',
              ),
            ),
          },
          home: const NotificationView(),
        ),
      ),
    );
    await tester.runAsync(vm.load);
    await tester.pump();
  }

  Reminder byId(String id) => (vm.reminders as UiSuccess<List<Reminder>>).data
      .firstWhere((r) => r.reminderId == id);
}

/// Runs a view model call started by a tap to its end (the fakes are real futures).
Future<void> _finish(WidgetTester tester) async {
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 50)),
  );
  await tester.pump();
}

void main() {
  testWidgets('no reminders yet: the note and the health-log offer', (
    tester,
  ) async {
    final s = _Setup();
    await tester.runAsync(s.signIn);
    await s.pump(tester);
    expect(find.textContaining('No reminders yet'), findsOneWidget);
    expect(find.text('Nothing in the last two weeks.'), findsOneWidget);
    await tester.tap(find.text('Remind me to log my health readings'));
    await _finish(tester);
    expect(find.text('Log your health readings'), findsOneWidget);
    expect(find.text('Remind me to log my health readings'), findsNothing);
  });

  testWidgets('an exercise reminder: switch, days and the plan link', (
    tester,
  ) async {
    final s = _Setup();
    await tester.runAsync(() async {
      await s.signIn();
      await s.exerciseReminder();
    });
    await s.pump(tester);
    expect(find.text('Time for Early Knee Recovery'), findsOneWidget);
    expect(find.text('9:00 AM'), findsOneWidget);
    expect(
      find.byTooltip('Delete this reminder'),
      findsNothing,
    ); // a plan's own
    await tester.tap(find.byType(Switch));
    await _finish(tester);
    expect(s.byId('r1').isEnabled, isFalse);
    await tester.tap(find.byType(Switch));
    await _finish(tester);
    expect(s.byId('r1').isEnabled, isTrue);
    await tester.tap(find.text('T').first); // Tuesday
    await _finish(tester);
    expect(s.byId('r1').repeatDays, '1110100');
    await tester.tap(find.text('Open this plan'));
    await tester.pumpAndSettle();
    expect(find.text('route:treatment pp1'), findsOneWidget);
  });

  testWidgets('the last day cannot be turned off', (tester) async {
    final s = _Setup();
    await tester.runAsync(() async {
      await s.signIn();
      await s.exerciseReminder(days: '1000000');
    });
    await s.pump(tester);
    await tester.tap(find.text('M'));
    await _finish(tester);
    expect(find.text(Messages.reminderNeedsADay), findsOneWidget);
    expect(s.byId('r1').repeatDays, '1000000');
  });

  testWidgets('Change opens the time picker; a new time is saved', (
    tester,
  ) async {
    final s = _Setup();
    await tester.runAsync(() async {
      await s.signIn();
      await s.exerciseReminder();
    });
    await s.pump(tester);
    await tester.tap(find.text('Change'));
    await tester.pumpAndSettle();
    expect(find.byType(TimePickerDialog), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(s.byId('r1').hour, 9);
    await tester.tap(find.text('Change'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('PM'));
    await tester.pump();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    await _finish(tester);
    expect(s.byId('r1').hour, 21);
    expect(find.text('9:00 PM'), findsOneWidget);
    // The time is tapped to change it: a full 48 px touch target (audit, 24 Oct).
    final row = find.ancestor(
      of: find.text('9:00 PM'),
      matching: find.byType(InkWell),
    );
    expect(tester.getSize(row.first).height, greaterThanOrEqualTo(48));
  });

  testWidgets('the health-log reminder can be deleted after asking', (
    tester,
  ) async {
    final s = _Setup();
    await tester.runAsync(() async {
      await s.signIn();
      await s.healthReminder();
    });
    await s.pump(tester);
    expect(find.text('8:00 PM'), findsOneWidget);
    await tester.tap(find.byTooltip('Delete this reminder'));
    await tester.pumpAndSettle();
    expect(find.text('Delete this reminder?'), findsOneWidget);
    await tester.tap(find.text('Keep'));
    await tester.pumpAndSettle();
    expect(find.text('Log your health readings'), findsOneWidget);
    await tester.tap(find.byTooltip('Delete this reminder'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    await _finish(tester);
    expect(find.text('Log your health readings'), findsNothing);
    expect(find.text('Remind me to log my health readings'), findsOneWidget);
  });

  testWidgets('notifications refused: the notice opens the settings', (
    tester,
  ) async {
    final s = _Setup();
    s.device.allow = false;
    await tester.runAsync(() async {
      await s.signIn();
      await s.exerciseReminder();
      await s.service.requestPermission();
    });
    await s.pump(tester);
    expect(find.text(Messages.notificationsOff), findsOneWidget);
    await tester.tap(find.text('Turn on notifications'));
    await _finish(tester);
    expect(s.device.openedSettings, 1);
  });

  testWidgets('no exact alarms: the may-be-late notice opens its setting', (
    tester,
  ) async {
    final s = _Setup();
    s.device.exact = false;
    await tester.runAsync(() async {
      await s.signIn();
      await s.exerciseReminder();
    });
    await s.pump(tester);
    expect(find.text(Messages.remindersMayBeLate), findsOneWidget);
    await tester.tap(find.text('Turn on Alarms & reminders'));
    await _finish(tester);
    expect(s.device.openedExact, 1);
  });

  testWidgets('the log: unread count, and a tap marks one read', (
    tester,
  ) async {
    final s = _Setup();
    await tester.runAsync(() async {
      await s.signIn();
      await s.logged('Time for your exercise');
      await s.logged('Old one', read: true);
    });
    await s.pump(tester);
    expect(find.text('1 unread'), findsOneWidget);
    await tester.tap(find.text('Time for your exercise'));
    await _finish(tester);
    expect(find.text('1 unread'), findsNothing);
    expect(s.vm.unreadCount, 0);
  });

  testWidgets('back from the phone settings rechecks the permission', (
    tester,
  ) async {
    final s = _Setup();
    s.device.allow = false;
    await tester.runAsync(() async {
      await s.signIn();
      await s.service.requestPermission();
    });
    await s.pump(tester);
    expect(find.text(Messages.notificationsOff), findsOneWidget);
    s.device.allow = true;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await _finish(tester);
    expect(find.text(Messages.notificationsOff), findsNothing);
  });
}
