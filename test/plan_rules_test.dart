import 'package:flutter_test/flutter_test.dart';

import 'package:physical_treatment_and_health_support_system/model/business_logic/plan_rules/plan_rules.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/enums.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/exercise.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/patient_treatment_plan.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/safety_limit.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/treatment_plan.dart';

Exercise ex(
  String id, {
  ExerciseIntensity intensity = ExerciseIntensity.low,
  String area = 'BOTH_LEGS',
}) => Exercise(
  exerciseId: id,
  exerciseName: id,
  instructionText: '',
  targetBodyArea: area,
  intensityLevel: intensity,
  defaultRepetitions: 10,
  defaultDurationSec: 60,
);

TreatmentPlan plan(
  String id, {
  String area = 'BOTH_LEGS',
  String? goal = 'STRENGTH',
  int perWeek = 3,
  List<(Exercise, int)>? exercises,
}) => TreatmentPlan(
  planId: id,
  planName: id,
  aim: '',
  targetBodyArea: area,
  recoveryStage: RecoveryStage.early,
  mobilityLevel: MobilityLevel.low,
  frequencyPerWeek: perWeek,
  goal: goal,
  exercises: [
    for (final (i, (e, sec))
        in (exercises ?? [(ex('$id-a'), 60), (ex('$id-b'), 90)]).indexed)
      PlanExercise(
        planId: id,
        exercise: e,
        sequenceOrder: i + 1,
        prescribedRepetitions: 10,
        prescribedDurationSec: sec,
      ),
  ],
);

PatientTreatmentPlan following(TreatmentPlan p) => PatientTreatmentPlan(
  patientPlanId: 'pp-${p.planId}',
  accountId: 'acc',
  plan: p,
  selectedAt: DateTime(2026, 10, 1),
);

SafetyLimit limit({
  ExerciseIntensity max = ExerciseIntensity.moderate,
  int minutes = 30,
}) => SafetyLimit(
  safetyLimitId: 's',
  maxExerciseIntensity: max,
  maxSessionDurationMin: minutes,
  dailyCalorieTarget: 2000,
  dailySodiumLimitMg: 1500,
  dailySugarLimitG: 50,
);

List<String> codes(List<PlanIssue> issues) => [for (final i in issues) i.code];

List<PlanIssue> check(
  TreatmentPlan c,
  List<TreatmentPlan> active, {
  RiskLevel risk = RiskLevel.low,
  SafetyLimit? l,
}) => PlanRules.checkAdd(
  candidate: c,
  active: [for (final p in active) following(p)],
  risk: risk,
  limit: l ?? limit(),
);

void main() {
  group('building blocks', () {
    test('risk caps 3 / 2 / 1', () {
      expect(PlanRules.maxActivePlans(RiskLevel.low), 3);
      expect(PlanRules.maxActivePlans(RiskLevel.medium), 2);
      expect(PlanRules.maxActivePlans(RiskLevel.high), 1);
    });
    test('overlapping areas', () {
      expect(PlanRules.areasOverlap('BOTH_LEGS', 'LEFT_LEG'), isTrue);
      expect(PlanRules.areasOverlap('FULL_BODY', 'LEFT_ARM'), isTrue);
      expect(PlanRules.areasOverlap('LEFT_ARM', 'RIGHT_ARM'), isFalse);
      expect(PlanRules.areasOverlap('CORE', 'BOTH_LEGS'), isFalse);
    });
    test('clash needs overlapping area AND the same goal', () {
      expect(PlanRules.clashes(plan('a'), plan('b', area: 'LEFT_LEG')), isTrue);
      expect(PlanRules.clashes(plan('a'), plan('b', goal: 'BALANCE')), isFalse);
      expect(
        PlanRules.clashes(plan('a'), plan('b', area: 'BOTH_ARMS')),
        isFalse,
      );
      expect(
        PlanRules.clashes(plan('a', goal: null), plan('b', goal: null)),
        isFalse,
      );
    });
    test(
      'daily worst case: longest exercise per plan, a shared exercise once',
      () {
        final shared = ex('squat');
        final a = plan('a', exercises: [(shared, 120), (ex('x'), 60)]);
        final b = plan('b', exercises: [(shared, 90), (ex('y'), 60)]);
        expect(PlanRules.dailyWorstCaseSec([a, b]), 120);
        expect(
          PlanRules.dailyWorstCaseSec([
            a,
            plan('c', exercises: [(ex('z'), 300)]),
          ]),
          420,
        );
      },
    );
    test('rest day across plans', () {
      expect(PlanRules.noRestDay([plan('a', perWeek: 5)]), isFalse); // M-F
      expect(
        PlanRules.noRestDay([plan('a', perWeek: 5), plan('b', perWeek: 3)]),
        isFalse,
      ); // M-F + M,W,F
      expect(
        PlanRules.noRestDay([plan('a', perWeek: 6), plan('b', perWeek: 7)]),
        isTrue,
      );
    });
  });

  group('checkAdd', () {
    test('a first plan within limits has nothing to say', () {
      expect(check(plan('a'), []), isEmpty);
    });

    test('the plan already followed is blocked', () {
      final issues = check(plan('a'), [plan('a')]);
      expect(codes(issues), ['already_following']);
      expect(PlanRules.canAdd(issues), isFalse);
    });

    test('same area and goal offers to replace that plan', () {
      final issues = check(plan('b', area: 'LEFT_LEG'), [plan('a')]);
      final clash = issues.singleWhere((i) => i.code == 'clash');
      expect(clash.level, PlanIssueLevel.replace);
      expect(clash.patientPlanId, 'pp-a');
      expect(PlanRules.canAdd(issues), isTrue);
    });

    test('different goal, same area: allowed with a same-area warning', () {
      final issues = check(plan('b', goal: 'BALANCE'), [plan('a')]);
      expect(codes(issues), contains('same_area'));
      expect(codes(issues), isNot(contains('clash')));
      expect(PlanRules.canAdd(issues), isTrue);
    });

    test('different area: no clash, no same-area warning', () {
      final issues = check(plan('b', area: 'BOTH_ARMS'), [plan('a')]);
      expect(codes(issues), isEmpty);
    });

    test('risk cap: High allows one, Medium two, Low three', () {
      final arms = plan('b', area: 'BOTH_ARMS');
      expect(
        codes(check(arms, [plan('a')], risk: RiskLevel.high)),
        contains('risk_cap'),
      );
      expect(
        codes(check(arms, [plan('a')], risk: RiskLevel.medium)),
        isNot(contains('risk_cap')),
      );
      final core = plan('c', area: 'CORE', goal: 'PAIN_RELIEF');
      expect(
        codes(check(core, [plan('a'), arms], risk: RiskLevel.medium)),
        contains('risk_cap'),
      );
      expect(
        codes(check(core, [plan('a'), arms], risk: RiskLevel.low)),
        isNot(contains('risk_cap')),
      );
    });

    test('replacing a clashing plan frees its slot under the cap', () {
      // High risk, one leg-strength plan, a second leg-strength plan: it is a replacement, not over the cap.
      final issues = check(plan('b', area: 'LEFT_LEG'), [
        plan('a'),
      ], risk: RiskLevel.high);
      expect(codes(issues), ['clash']);
    });

    test('an exercise above the CURRENT intensity limit blocks', () {
      final hard = plan(
        'b',
        area: 'BOTH_ARMS',
        exercises: [(ex('push', intensity: ExerciseIntensity.vigorous), 60)],
      );
      final issues = check(hard, [], l: limit(max: ExerciseIntensity.moderate));
      expect(codes(issues), ['intensity']);
      expect(PlanRules.canAdd(issues), isFalse);
    });

    test('combined daily time above the limit blocks', () {
      final a = plan('a', exercises: [(ex('x'), 600)]);
      final b = plan('b', area: 'BOTH_ARMS', exercises: [(ex('y'), 600)]);
      final issues = check(b, [a], l: limit(minutes: 15));
      expect(codes(issues), contains('daily_time'));
      expect(
        issues.firstWhere((i) => i.code == 'daily_time').message,
        contains('20 minutes'),
      );
      expect(PlanRules.canAdd(issues), isFalse);
      expect(
        codes(check(b, [a], l: limit(minutes: 30))),
        isNot(contains('daily_time')),
      );
    });

    test('a shared exercise is counted once in the daily time', () {
      final squat = ex('squat');
      final a = plan('a', exercises: [(squat, 600)]);
      final b = plan('b', goal: 'BALANCE', exercises: [(squat, 600)]);
      expect(
        codes(check(b, [a], l: limit(minutes: 12))),
        isNot(contains('daily_time')),
      );
    });

    test('shared exercises are explained: do once, counts for both', () {
      final squat = ex('Mini Squat');
      final a = plan('a', exercises: [(squat, 60), (ex('x'), 60)]);
      final b = plan(
        'b',
        goal: 'BALANCE',
        exercises: [(squat, 60), (ex('y'), 60)],
      );
      final info = check(b, [
        a,
      ]).singleWhere((i) => i.code == 'shared_exercise');
      expect(info.level, PlanIssueLevel.info);
      expect(info.message, contains('Mini Squat'));
      expect(info.message, contains('counts for both'));
    });

    test('no rest day warning', () {
      final a = plan('a', perWeek: 6);
      final b = plan('b', area: 'BOTH_ARMS', perWeek: 7);
      expect(codes(check(b, [a])), contains('no_rest_day'));
      expect(
        codes(
          check(plan('c', area: 'BOTH_ARMS', perWeek: 3), [
            plan('d', perWeek: 3),
          ]),
        ),
        isNot(contains('no_rest_day')),
      );
    });
  });

  group('checkActive after a profile change', () {
    test('more plans than the new risk level allows', () {
      final issues = PlanRules.checkActive(
        active: [
          following(plan('a')),
          following(plan('b', area: 'BOTH_ARMS')),
        ],
        risk: RiskLevel.high,
        limit: limit(),
      );
      expect(codes(issues), contains('over_cap'));
    });
    test(
      'an exercise now above the intensity limit is flagged, not stopped',
      () {
        final p = plan(
          'a',
          exercises: [(ex('step', intensity: ExerciseIntensity.moderate), 60)],
        );
        final issues = PlanRules.checkActive(
          active: [following(p)],
          risk: RiskLevel.low,
          limit: limit(max: ExerciseIntensity.low),
        );
        expect(issues.single.code, 'intensity_now');
        expect(issues.single.level, PlanIssueLevel.warning);
      },
    );
    test('within limits: nothing', () {
      expect(
        PlanRules.checkActive(
          active: [following(plan('a'))],
          risk: RiskLevel.low,
          limit: limit(),
        ),
        isEmpty,
      );
    });
  });
}
