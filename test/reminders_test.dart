import 'package:flutter_test/flutter_test.dart';

import 'package:physical_treatment_and_health_support_system/core/services/local_notification_service.dart';
import 'package:physical_treatment_and_health_support_system/core/services/reminder_service.dart';
import 'package:physical_treatment_and_health_support_system/data/models/enums.dart';
import 'package:physical_treatment_and_health_support_system/data/models/exercise_session.dart';
import 'package:physical_treatment_and_health_support_system/data/models/reminder.dart';
import 'package:physical_treatment_and_health_support_system/data/repository/fake/fake_notification_repository.dart';
import 'package:physical_treatment_and_health_support_system/data/repository/fake/fake_treatment_repository.dart';

/// Records what would be scheduled on the phone.
class FakeScheduler implements NotificationScheduler {
  final Map<int, DateTime> pending = {};
  bool allow = true;

  @override
  Future<void> init() async {}
  @override
  Future<bool> requestPermission() async => allow;
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
  late LocalNotificationService local;
  late FakeNotificationRepository repo;
  late FakeTreatmentRepository treatments;
  late ReminderService service;

  setUp(() {
    device = FakeScheduler();
    local = LocalNotificationService(scheduler: device, now: () => now);
    repo = FakeNotificationRepository();
    treatments = FakeTreatmentRepository(const []);
    service = ReminderService(repo, treatments, local, now: () => now);
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

    test('rescheduling replaces, never duplicates', () async {
      await local.schedule(reminder());
      await local.schedule(reminder());
      expect(device.pending, hasLength(6));
    });
  });

  group('ReminderService (M600.1)', () {
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
}
