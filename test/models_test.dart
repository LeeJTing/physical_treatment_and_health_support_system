import 'package:physical_treatment_and_health_support_system/data/models/enums.dart';
import 'package:physical_treatment_and_health_support_system/data/models/exercise.dart';
import 'package:physical_treatment_and_health_support_system/data/models/health_profile.dart';
import 'package:physical_treatment_and_health_support_system/data/models/lookups.dart';
import 'package:physical_treatment_and_health_support_system/data/models/reminder.dart';
import 'package:physical_treatment_and_health_support_system/data/models/safety_limit.dart';
import 'package:flutter_test/flutter_test.dart';

HealthCondition cond(String code) => LookupSeed.conditions.firstWhere((c) => c.conditionCode == code);
PhysicalLimitation lim(String code) => LookupSeed.limitations.firstWhere((l) => l.limitationCode == code);

HealthProfile profile({List<HealthCondition> c = const [], List<PhysicalLimitation> l = const []}) =>
    HealthProfile(
      profileId: 'p1',
      accountId: 'a1',
      age: 65,
      gender: Gender.female,
      weightKg: 60,
      heightCm: 155,
      conditions: c,
      limitations: l,
      updatedAt: DateTime(2026, 10, 1),
    );

Exercise ex({String area = 'BOTH_LEGS', ExerciseIntensity i = ExerciseIntensity.low, int sec = 60}) => Exercise(
      exerciseId: 'e1',
      exerciseName: 'Test',
      instructionText: '',
      targetBodyArea: area,
      intensityLevel: i,
      defaultRepetitions: 10,
      defaultDurationSec: sec,
    );

void main() {
  group('Risk rule set (FR100_054)', () {
    test('no condition and no limitation is Low', () {
      expect(profile().assignRiskLevel(), RiskLevel.low);
    });
    test('one non-cardiovascular condition is Medium', () {
      expect(profile(c: [cond('DIABETES')]).assignRiskLevel(), RiskLevel.medium);
    });
    test('one mobility limitation is Medium', () {
      expect(profile(l: [lim('LEFT_ARM_MOBILITY')]).assignRiskLevel(), RiskLevel.medium);
    });
    test('two conditions is High', () {
      expect(profile(c: [cond('DIABETES'), cond('ASTHMA')]).assignRiskLevel(), RiskLevel.high);
    });
    test('any cardiovascular condition is High', () {
      expect(profile(c: [cond('HYPERTENSION')]).assignRiskLevel(), RiskLevel.high);
    });
    test('balance limitation is High', () {
      expect(profile(l: [lim('BALANCE_IMPAIRMENT')]).assignRiskLevel(), RiskLevel.high);
    });
  });

  group('HealthProfile', () {
    test('BMI is weight / height^2 to one decimal (FR100_046)', () {
      expect(profile().calculateBmi(), 25.0);
    });
    test('validate reports missing and out-of-range values (FR100_045, 049)', () {
      final p = HealthProfile(profileId: 'p', accountId: 'a', age: 12, weightKg: 500, updatedAt: DateTime.now());
      expect(p.validate(), containsAll(['age', 'gender', 'weight', 'height']));
      expect(profile().validate(), isEmpty);
    });
    test('High risk produces LOW intensity cap', () {
      final s = profile(c: [cond('STROKE')]).generateSafetyLimit();
      expect(s.maxExerciseIntensity, ExerciseIntensity.low);
      expect(s.dailySodiumLimitMg, 2000);
    });
    test('hypertension lowers sodium, diabetes lowers sugar', () {
      final s = profile(c: [cond('HYPERTENSION'), cond('DIABETES')]).generateSafetyLimit();
      expect(s.dailySodiumLimitMg, 1500);
      expect(s.dailySugarLimitG, 25);
    });
  });

  group('Exercise safety', () {
    test('intensity above the cap is not permitted', () {
      final s = SafetyLimit.mostRestrictive();
      expect(ex(i: ExerciseIntensity.moderate).isSafeFor(s), isFalse);
      expect(ex().isSafeFor(s), isTrue);
    });
    test('duration above the session cap is not permitted', () {
      expect(ex(sec: 20 * 60).isSafeFor(SafetyLimit.mostRestrictive()), isFalse);
    });
    test('left leg limitation conflicts with left leg and both legs', () {
      final l = lim('LEFT_LEG_MOBILITY');
      expect(ex(area: 'LEFT_LEG').conflictsWith(l), isTrue);
      expect(ex(area: 'BOTH_LEGS').conflictsWith(l), isTrue);
      expect(ex(area: 'FULL_BODY').conflictsWith(l), isTrue);
      expect(ex(area: 'BOTH_ARMS').conflictsWith(l), isFalse);
    });
    test('balance limitation blocks no single body area', () {
      expect(ex().conflictsWith(lim('BALANCE_IMPAIRMENT')), isFalse);
    });
  });

  group('Reminder', () {
    test('frequency maps to a weekday mask (FR500_11)', () {
      expect(Reminder.maskForFrequency(3), '1010100');
      expect(Reminder.maskForFrequency(7), '1111111');
      expect(Reminder.maskForFrequency(0), '0000000');
    });
    final r = Reminder(
      reminderId: 'r',
      accountId: 'a',
      reminderType: ReminderType.exercise,
      title: 'Exercise',
      hour: 9,
      minute: 0,
      repeatDays: '1010100',
    );
    test('firesOn follows the mask', () {
      expect(r.firesOn(DateTime(2026, 10, 5)), isTrue); // Monday
      expect(r.firesOn(DateTime(2026, 10, 6)), isFalse); // Tuesday
    });
    test('nextOccurrence skips to the next selected day', () {
      expect(r.nextOccurrence(DateTime(2026, 10, 5, 10)), DateTime(2026, 10, 7, 9)); // Mon 10am -> Wed 9am
      expect(r.nextOccurrence(DateTime(2026, 10, 5, 8)), DateTime(2026, 10, 5, 9)); // Mon 8am -> Mon 9am
    });
    test('only exercise reminders are suppressed (FR600_005)', () {
      expect(r.shouldSuppress(true), isTrue);
      expect(r.shouldSuppress(false), isFalse);
    });
  });

  group('Exercise instruction text', () {
    Exercise withText(String t) => Exercise(
          exerciseId: 'e', exerciseName: 'X', instructionText: t, targetBodyArea: 'BOTH_LEGS',
          intensityLevel: ExerciseIntensity.low, defaultRepetitions: 10, defaultDurationSec: 60);

    test('camera sentence is split from the steps', () {
      final e = withText('Camera: side view, whole body in frame. Sit upright on a chair. Lift one knee.');
      expect(e.cameraTip, 'Side view, whole body in frame.');
      expect(e.steps, 'Sit upright on a chair. Lift one knee.');
    });

    test('text without a camera sentence is unchanged', () {
      final e = withText('Sit upright on a chair.');
      expect(e.cameraTip, isNull);
      expect(e.steps, 'Sit upright on a chair.');
    });
  });
}
