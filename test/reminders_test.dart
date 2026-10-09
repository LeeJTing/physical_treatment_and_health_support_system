import 'package:flutter_test/flutter_test.dart';

import 'package:physical_treatment_and_health_support_system/model/business_logic/local_notification_service/local_notification_service.dart';
import 'package:physical_treatment_and_health_support_system/device_platform/notification_scheduler/notification_scheduler.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/enums.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/exercise_session.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/reminder.dart';
import 'package:physical_treatment_and_health_support_system/model/repository/notification_repository/fake_notification_repository.dart';
import 'package:physical_treatment_and_health_support_system/model/repository/treatment_repository/fake_treatment_repository.dart';
import 'package:physical_treatment_and_health_support_system/core/constants/app_constants.dart';
import 'package:physical_treatment_and_health_support_system/model/repository/auth_repository/fake_auth_repository.dart';
import 'package:physical_treatment_and_health_support_system/model/result.dart';
import 'package:physical_treatment_and_health_support_system/viewmodel/notification_view_model/notification_view_model.dart';

/// Records what would be scheduled on the phone.
class FakeScheduler implements NotificationScheduler {
  final Map<int, DateTime> pending = {};
  bool allow = true;
  int asked = 0; // system dialogs shown

  @override
  Future<void> init() async {}
  @override
  Future<bool> requestPermission() async {
    asked++;
    return allow;
  }

  @override
  Future<bool> isPermitted() async => allow;
  @override
  Future<void> scheduleOnce(
    int id,
    String title,
    String body,
    DateTime at,
  ) async => pending[id] = at;
  @override
  Future<void> cancel(int id) async => pending.remove(id);
}

/// A notification plugin that fails on every call (no permission service, a platform error).
class ThrowingScheduler implements NotificationScheduler {
  @override
  Future<void> init() async {}
  @override
  Future<bool> requestPermission() async => true;
  @override
  Future<bool> isPermitted() async => true;
  @override
  Future<void> scheduleOnce(int id, String title, String body, DateTime at) =>
      Future.error(Exception('plugin failed'));
  @override
  Future<void> cancel(int id) => Future.error(Exception('plugin failed'));
}

Reminder healthLog({String id = 'h1', String account = 'a1'}) => Reminder(
  reminderId: id,
  accountId: account,
  reminderType: ReminderType.healthLog,
  title: 'Log your health readings',
  hour: 20,
  minute: 0,
);

// Monday 5 October 2026, 08:00: before the 09:00 reminder.
final DateTime now = DateTime(2026, 10, 5, 8);

Reminder reminder({
  String id = 'r1',
  String plan = 'pp1',
  String mask = '1010100',
  bool enabled = true,
}) => Reminder(
  reminderId: id,
  accountId: 'a1',
  patientPlanId: plan,
  reminderType: ReminderType.exercise,
  title: 'Time for Early Knee Recovery',
  hour: 9,
  minute: 0,
  repeatDays: mask,
  isEnabled: enabled,
);

void main() {
  late FakeScheduler device;
  late FakeNotificationRepository repo;
  late FakeTreatmentRepository treatments;
  // One service (architecture diagram): device scheduling and the plan's reminders.
  late LocalNotificationService local;
  late LocalNotificationService service;

  setUp(() {
    device = FakeScheduler();
    repo = FakeNotificationRepository();
    treatments = FakeTreatmentRepository(const []);
    local = LocalNotificationService(
      repo,
      treatments,
      scheduler: device,
      now: () => now,
    );
    service = local;
  });

  group('LocalNotificationService (Table 4.75)', () {
    test(
      'Mon/Wed/Fri at 9:00 gives six notifications in a two-week window',
      () async {
        expect(await local.schedule(reminder()), 6);
        expect(
          device.pending.values.every(
            (t) => t.hour == 9 && const [1, 3, 5].contains(t.weekday),
          ),
          isTrue,
        );
        expect(
          device.pending.values.any((t) => t.day == now.day),
          isTrue,
        ); // today 9:00 is still ahead
      },
    );

    test('a skipped day and a disabled reminder', () async {
      final today = DateTime(now.year, now.month, now.day);
      expect(await local.schedule(reminder(), skipDays: {today}), 5);
      expect(await local.schedule(reminder(enabled: false)), 0);
      expect(
        device.pending,
        isEmpty,
      ); // disabling also cancels what was scheduled
    });

    test(
      'nothing is scheduled without notification permission (FR600_008)',
      () async {
        device.allow = false;
        expect(await local.schedule(reminder()), 0);
        expect(local.permissionGranted, isFalse);
      },
    );

    test('a refusal is asked once, not on every change', () async {
      device.allow = false;
      expect(await local.schedule(reminder()), 0);
      expect(await local.schedule(reminder(id: 'r2')), 0);
      expect(device.asked, 1);
      expect(local.permissionDenied, isTrue);
    });

    test('rescheduling replaces, never duplicates', () async {
      await local.schedule(reminder());
      await local.schedule(reminder());
      expect(device.pending, hasLength(6));
    });
  });

  group('LocalNotificationService: plan reminders (M600.1)', () {
    test(
      'a completed session cancels today\'s reminder and logs it as SUPPRESSED (FR600_005)',
      () async {
        final r = reminder();
        await repo.saveReminder(r);
        await local.schedule(r);
        await service.exerciseDone('a1', 'pp1');
        expect(device.pending, hasLength(5));
        expect(
          device.pending.values.any(
            (t) => t.day == now.day && t.month == now.month,
          ),
          isFalse,
        );
        expect(repo.log.single.deliveryStatus, DeliveryStatus.suppressed);
      },
    );

    test('sync skips today when today\'s session is already done', () async {
      await repo.saveReminder(reminder());
      await treatments.saveSession(
        ExerciseSession(
          sessionId: 's1',
          accountId: 'a1',
          patientPlanId: 'pp1',
          exerciseId: 'e1',
          completedAt: now,
          completionStatus: CompletionStatus.completed,
          postureAccuracy: 85,
        ),
      );
      expect(await service.sync('a1'), 5);
    });

    test('selecting a new plan removes the old plan\'s reminders', () async {
      final old = reminder(id: 'old', plan: 'pp-old');
      await repo.saveReminder(old);
      await local.schedule(old);
      final fresh = reminder(id: 'new', plan: 'pp-new', mask: '1111100');
      await repo.saveReminder(fresh);
      await service.planSelected(fresh, previousPatientPlanId: 'pp-old');
      expect(repo.reminders.keys, ['new']);
      expect(
        device.pending,
        hasLength(10),
      ); // Mon-Fri for two weeks, old ones gone
    });

    test(
      'switching off and changing the time (FR600_004, FR600_006)',
      () async {
        final r = reminder();
        await repo.saveReminder(r);
        final off = (await service.update(r, enabled: false)).dataOrNull!;
        expect(off.isEnabled, isFalse);
        expect(device.pending, isEmpty);
        final moved = (await service.update(
          off,
          enabled: true,
          hour: 18,
          minute: 30,
        )).dataOrNull!;
        expect(repo.reminders['r1']!.hour, 18);
        expect(
          device.pending.values.every((t) => t.hour == 18 && t.minute == 30),
          isTrue,
        );
        expect(moved.isEnabled, isTrue);
      },
    );
  });

  group('Reminder management (M600.1, 9 Oct)', () {
    test(
      'changing the days reschedules on the new days only (FR600_003)',
      () async {
        final r = reminder(); // Mon/Wed/Fri at 9:00
        await repo.saveReminder(r);
        await local.schedule(r);
        final moved = (await service.update(
          r,
          repeatDays: '0100000',
        )).dataOrNull!;
        expect(moved.repeatDays, '0100000');
        expect(repo.reminders['r1']!.repeatDays, '0100000');
        expect(
          device.pending,
          hasLength(2),
        ); // Tuesday 6 and Tuesday 13 October
        expect(
          device.pending.values.every((t) => t.weekday == DateTime.tuesday),
          isTrue,
        );
      },
    );

    test(
      'a health-logging reminder is not suppressed by a finished exercise (FR600_002)',
      () async {
        final h = healthLog();
        await repo.saveReminder(h);
        await local.schedule(h);
        await service.exerciseDone('a1', 'pp1');
        expect(device.pending, hasLength(14)); // every evening for two weeks
        expect(repo.log, isEmpty);
      },
    );

    test(
      'removing a reminder cancels it on the phone and deletes it',
      () async {
        final h = healthLog();
        await repo.saveReminder(h);
        await local.schedule(h);
        expect(await service.remove(h), isA<Success<void>>());
        expect(device.pending, isEmpty);
        expect(repo.reminders, isEmpty);
      },
    );

    test(
      'a failing phone plugin never reaches the caller (services never throw)',
      () async {
        final broken = LocalNotificationService(
          repo,
          treatments,
          scheduler: ThrowingScheduler(),
          now: () => now,
        );
        expect(await broken.schedule(reminder()), 0);
        await broken.cancel('r1');
        await repo.saveReminder(reminder());
        final off = await broken.update(reminder(), enabled: false);
        expect(off.dataOrNull?.isEnabled, isFalse);
      },
    );
  });

  group('NotificationViewModel (Table 4.49)', () {
    late FakeAuthRepository auth;
    late NotificationViewModel vm;

    setUp(() async {
      auth = FakeAuthRepository();
      final id = (await auth.login(
        'demo@apths.test',
        'password123',
      )).dataOrNull!.accountId;
      await repo.saveReminder(
        Reminder(
          reminderId: 'plan-r',
          accountId: id,
          patientPlanId: 'pp1',
          reminderType: ReminderType.exercise,
          title: 'Time for Early Knee Recovery',
          hour: 9,
          minute: 0,
          repeatDays: '1010100',
        ),
      );
      vm = NotificationViewModel(repo, local, auth);
      await vm.load();
    });

    test('a refusal shows on the screen; allowing puts the reminders back (FR600_008)', () async {
      device.allow = false;
      local.permissionGranted = false; // the phone's setting is off; the app has not asked yet
      await vm.toggleReminder('plan-r', true); // asks once, refused
      expect(vm.notificationsBlocked, isTrue);
      expect(device.pending, isEmpty);

      device.allow = true; // turned on in Settings
      await vm.load();
      expect(vm.notificationsBlocked, isFalse);
      expect(device.pending, isNotEmpty);

      local.permissionDenied = true; // refused again later
      local.permissionGranted = false;
      device.pending.clear();
      await vm.askNotificationPermission(); // "Allow notifications"
      expect(vm.notificationsBlocked, isFalse);
      expect(device.pending, isNotEmpty);
    });

    test(
      'adds one health-logging reminder, every day at 8 pm (FR600_002)',
      () async {
        expect(vm.hasHealthLogReminder, isFalse);
        await vm.addHealthLogReminder();
        await vm.addHealthLogReminder(); // a second tap adds nothing
        final logs = repo.reminders.values
            .where((r) => r.reminderType == ReminderType.healthLog)
            .toList();
        expect(logs, hasLength(1));
        expect(logs.single.hour, 20);
        expect(logs.single.repeatDays, '1111111');
        expect(vm.hasHealthLogReminder, isTrue);
      },
    );

    test('a day can be turned off, but not the last one (FR600_003)', () async {
      await vm.toggleDay('plan-r', DateTime.monday);
      expect(repo.reminders['plan-r']!.repeatDays, '0010100');
      await vm.toggleDay('plan-r', DateTime.wednesday);
      await vm.toggleDay('plan-r', DateTime.friday); // would leave no day
      expect(repo.reminders['plan-r']!.repeatDays, '0000100');
      expect(vm.errorMessage, Messages.reminderNeedsADay);
    });

    test('the last-day notice goes once anything else succeeds', () async {
      await vm.addHealthLogReminder();
      final id = repo.reminders.values
          .firstWhere((r) => r.reminderType == ReminderType.healthLog)
          .reminderId;
      for (final d in [1, 2, 3, 4, 5, 6]) {
        await vm.toggleDay(id, d);
      }
      await vm.toggleDay(id, DateTime.sunday);
      expect(vm.errorMessage, Messages.reminderNeedsADay);
      await vm.deleteReminder(id); // phone test, 9 Oct: the notice stayed
      expect(vm.errorMessage, isNull);
      await vm.toggleDay('plan-r', DateTime.monday);
      await vm.toggleDay('plan-r', DateTime.wednesday);
      await vm.toggleDay('plan-r', DateTime.friday);
      expect(vm.errorMessage, Messages.reminderNeedsADay);
      await vm.toggleReminder('plan-r', false);
      expect(vm.errorMessage, isNull);
    });

    test('only reminders the patient added can be deleted', () async {
      await vm.deleteReminder(
        'plan-r',
      ); // a plan's reminder stays with the plan
      expect(repo.reminders.containsKey('plan-r'), isTrue);
      await vm.addHealthLogReminder();
      final id = repo.reminders.values
          .firstWhere((r) => r.reminderType == ReminderType.healthLog)
          .reminderId;
      await vm.deleteReminder(id);
      expect(repo.reminders.containsKey(id), isFalse);
    });
  });
}
