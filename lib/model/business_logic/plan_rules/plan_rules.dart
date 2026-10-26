import 'dart:math' as math;

import 'package:physical_treatment_and_health_support_system/model/entity/enums.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/patient_treatment_plan.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/reminder.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/safety_limit.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/treatment_plan.dart';

/// How serious a plan check is.
enum PlanIssueLevel {
  /// The plan cannot be added.
  block,

  /// The plan can only be added by stopping [PlanIssue.planId] (or, when null,
  /// one plan the patient chooses).
  replace,

  /// Allowed, but the patient should know.
  warning,

  /// Helpful information only.
  info,
}

class PlanIssue {
  final PlanIssueLevel level;

  /// Stable code for tests and logging, e.g. 'clash', 'risk_cap'.
  final String code;

  /// Patient-facing text.
  final String message;

  /// The active plan this issue is about (the one to replace), if any.
  final String? patientPlanId;

  const PlanIssue(this.level, this.code, this.message, {this.patientPlanId});

  @override
  String toString() => '$level $code';
}

/// Rules for following several treatment plans at once (Elwin, 9 Oct 2026):
///  - two plans clash when their body areas overlap AND their goals match AND they
///    work mostly the same joints (Elwin, 9 Oct: a shoulder plan and a hand plan
///    for both arms can be followed together);
///  - at most 3 / 2 / 1 active plans for Low / Medium / High risk;
///  - one exercise per plan per day, an exercise shared by two plans is done
///    once and counts for both;
///  - every check uses the CURRENT safety limit and risk level.
/// Pure Dart, unit-tested. Not in the Chapter 4 class diagram (PROJECT_STATE §11).
class PlanRules {
  PlanRules._();

  static int maxActivePlans(RiskLevel risk) => switch (risk) {
    RiskLevel.low => 3,
    RiskLevel.medium => 2,
    RiskLevel.high => 1,
  };

  // Body areas as body parts (left arm, right arm, left leg, right leg, core),
  // the same membership the recommender uses.
  static const _parts = {
    'LEFT_ARM': {'la'},
    'RIGHT_ARM': {'ra'},
    'BOTH_ARMS': {'la', 'ra'},
    'LEFT_LEG': {'ll'},
    'RIGHT_LEG': {'rl'},
    'BOTH_LEGS': {'ll', 'rl'},
    'CORE': {'c'},
    'FULL_BODY': {'la', 'ra', 'll', 'rl', 'c'},
  };

  static bool areasOverlap(String a, String b) =>
      (_parts[a] ?? const {}).intersection(_parts[b] ?? const {}).isNotEmpty;

  // Joints each posture exercise trains: the recommender's POSE_PARTS
  // (ai_server/app/recommend/engine.py), keep the two the same.
  static const _poseJoints = {
    'shoulder_abduction': ['shoulder'],
    'shoulder_flexion': ['shoulder'],
    'elbow_flexion': ['elbow'],
    'wall_push_up': ['elbow'],
    'wrist_extension': ['wrist_hand'],
    'hand_open_close': ['wrist_hand'],
    'hip_abduction': ['hip'],
    'seated_marching': ['hip'],
    'march_in_place': ['hip'],
    'glute_bridge': ['hip', 'back'],
    'bird_dog': ['back'],
    'knee_extension': ['knee'],
    'sit_to_stand': ['knee', 'hip'],
    'mini_squat': ['knee', 'hip'],
    'step_up': ['knee', 'hip'],
    'heel_raise': ['ankle_foot'],
    'tandem_stance': ['ankle_foot'],
  };

  /// How many of the plan's exercises train each joint.
  static Map<String, int> jointCounts(TreatmentPlan p) {
    final counts = <String, int>{};
    for (final pe in p.exercises) {
      for (final j in _poseJoints[pe.exercise.poseKey] ?? const <String>[]) {
        counts[j] = (counts[j] ?? 0) + 1;
      }
    }
    return counts;
  }

  /// How much two plans work the same joints, 0 to 1 (cosine of their joint
  /// counts, as the recommender compares plans). Null when either plan has no
  /// exercise with a known joint.
  static double? jointOverlap(TreatmentPlan a, TreatmentPlan b) {
    final x = jointCounts(a);
    final y = jointCounts(b);
    if (x.isEmpty || y.isEmpty) return null;
    var dot = 0;
    for (final e in x.entries) {
      dot += e.value * (y[e.key] ?? 0);
    }
    double norm(Map<String, int> m) =>
        math.sqrt(m.values.fold<int>(0, (s, n) => s + n * n));
    return dot / (norm(x) * norm(y));
  }

  /// From this joint overlap up, two plans "work the same joints". On the
  /// catalogue: Shoulder Mobility Starter vs Hand and Wrist Recovery 0.2 (no
  /// clash); the two balance plans 0.67, the two endurance plans 0.87 and the
  /// two leg-strength plans 0.98 (clash).
  static const sameJoints = 0.5;

  /// Same body area (overlapping) AND the same goal AND mostly the same joints.
  /// Plans whose joints are unknown clash on area and goal alone.
  static bool clashes(TreatmentPlan a, TreatmentPlan b) {
    if (!areasOverlap(a.targetBodyArea, b.targetBodyArea) ||
        a.goal == null ||
        a.goal != b.goal) {
      return false;
    }
    final overlap = jointOverlap(a, b);
    return overlap == null || overlap >= sameJoints;
  }

  /// Worst-case minutes a day with one exercise per plan per day; an exercise
  /// shared by several plans is done once, so it counts once (its longest
  /// prescribed time).
  static int dailyWorstCaseSec(Iterable<TreatmentPlan> plans) {
    final longestByExercise = <String, int>{};
    for (final p in plans) {
      if (p.exercises.isEmpty) continue;
      final longest = p.exercises.reduce(
        (a, b) => a.prescribedDurationSec >= b.prescribedDurationSec ? a : b,
      );
      final id = longest.exerciseId;
      final prev = longestByExercise[id] ?? 0;
      if (longest.prescribedDurationSec > prev) {
        longestByExercise[id] = longest.prescribedDurationSec;
      }
    }
    return longestByExercise.values.fold(0, (a, b) => a + b);
  }

  /// Names of exercises that appear in both plans.
  static List<String> sharedExercises(TreatmentPlan a, TreatmentPlan b) {
    final ids = {for (final pe in b.exercises) pe.exerciseId};
    return [
      for (final pe in a.orderedExercises())
        if (ids.contains(pe.exerciseId)) pe.exercise.exerciseName,
    ];
  }

  /// Whether the plans' reminder weekdays together leave no rest day.
  static bool noRestDay(Iterable<TreatmentPlan> plans) {
    final days = List.filled(7, false);
    for (final p in plans) {
      final mask = Reminder.maskForFrequency(p.frequencyPerWeek);
      for (var i = 0; i < 7 && i < mask.length; i++) {
        if (mask[i] == '1') days[i] = true;
      }
    }
    return days.every((d) => d);
  }

  static String _minutes(int sec) => '${(sec / 60).ceil()} minutes';

  static String _area(String code) => switch (code) {
    'LEFT_ARM' => 'left arm',
    'RIGHT_ARM' => 'right arm',
    'BOTH_ARMS' => 'arms',
    'LEFT_LEG' => 'left leg',
    'RIGHT_LEG' => 'right leg',
    'BOTH_LEGS' => 'legs',
    'CORE' => 'core and back',
    _ => 'whole body',
  };

  /// Checks adding [candidate] to the patient's [active] plans under the
  /// CURRENT [risk] level and safety [limit]. An empty list means it can be
  /// added with nothing to say.
  static List<PlanIssue> checkAdd({
    required TreatmentPlan candidate,
    required List<PatientTreatmentPlan> active,
    required RiskLevel risk,
    required SafetyLimit limit,
  }) {
    final issues = <PlanIssue>[];

    // 1. Already following it.
    for (final a in active) {
      if (a.plan.planId == candidate.planId) {
        return [
          PlanIssue(
            PlanIssueLevel.block,
            'already_following',
            'You are already following ${candidate.planName}.',
            patientPlanId: a.patientPlanId,
          ),
        ];
      }
    }

    // 2. Intensity above the current safety limit (any exercise).
    final tooHard = [
      for (final pe in candidate.exercises)
        if (!limit.permits(pe.exercise)) pe.exercise.exerciseName,
    ];
    if (tooHard.isNotEmpty) {
      issues.add(
        PlanIssue(
          PlanIssueLevel.block,
          'intensity',
          '${tooHard.join(', ')} ${tooHard.length == 1 ? 'is' : 'are'} harder '
              'than your current health profile allows.',
        ),
      );
    }

    // 3. Same body area, goal and joints: only one of the two can stay.
    final clashing = [
      for (final a in active)
        if (clashes(a.plan, candidate)) a,
    ];
    for (final a in clashing) {
      issues.add(
        PlanIssue(
          PlanIssueLevel.replace,
          'clash',
          '${a.plan.planName} already trains the same joints of your '
              '${_area(a.plan.targetBodyArea)} for the same goal. You can follow '
              'one of them: '
              'replace it with ${candidate.planName}?',
          patientPlanId: a.patientPlanId,
        ),
      );
    }

    // Plans that would remain beside the candidate if the clashes are replaced.
    final remaining = [
      for (final a in active)
        if (!clashing.contains(a)) a,
    ];

    // 4. How many plans the current risk level allows.
    final cap = maxActivePlans(risk);
    if (remaining.length + 1 > cap) {
      issues.add(
        PlanIssue(
          PlanIssueLevel.replace,
          'risk_cap',
          'Your health profile allows $cap '
              '${cap == 1 ? 'plan' : 'plans'} at a time. Choose a plan to '
              'replace with ${candidate.planName}.',
        ),
      );
    }

    // 5. Daily time: one exercise per plan per day, shared exercises once.
    final after = [for (final a in remaining) a.plan, candidate];
    final dailySec = dailyWorstCaseSec(after);
    final limitSec = limit.maxSessionDurationMin * 60;
    if (remaining.isNotEmpty && dailySec > limitSec) {
      issues.add(
        PlanIssue(
          PlanIssueLevel.block,
          'daily_time',
          'Together your plans could need up to ${_minutes(dailySec)} a day, '
              'more than the ${limit.maxSessionDurationMin} minutes your '
              'health profile allows.',
        ),
      );
    }

    // 6. The same body part loaded twice a day (allowed: different goals).
    for (final a in remaining) {
      if (areasOverlap(a.plan.targetBodyArea, candidate.targetBodyArea) &&
          !clashes(a.plan, candidate)) {
        issues.add(
          PlanIssue(
            PlanIssueLevel.warning,
            'same_area',
            '${a.plan.planName} and ${candidate.planName} both work your '
                '${_area(candidate.targetBodyArea)}, so you may exercise that '
                'area twice a day. Rest if it feels tiring or sore.',
            patientPlanId: a.patientPlanId,
          ),
        );
      }
    }

    // 7. No rest day in the week.
    if (remaining.isNotEmpty && noRestDay(after)) {
      issues.add(
        const PlanIssue(
          PlanIssueLevel.warning,
          'no_rest_day',
          'With these plans there is no rest day in the week. Muscles get '
              'stronger while resting, so take a day off when you feel tired.',
        ),
      );
    }

    // 8. Exercises in both plans: done once, counts for both.
    for (final a in remaining) {
      final shared = sharedExercises(candidate, a.plan);
      if (shared.isNotEmpty) {
        issues.add(
          PlanIssue(
            PlanIssueLevel.info,
            'shared_exercise',
            '${shared.join(', ')} ${shared.length == 1 ? 'is' : 'are'} in '
                'both ${a.plan.planName} and ${candidate.planName}. Do '
                '${shared.length == 1 ? 'it' : 'them'} once a day; it counts '
                'for both plans.',
            patientPlanId: a.patientPlanId,
          ),
        );
      }
    }
    return issues;
  }

  /// Re-checks the plans already being followed after the health profile
  /// changed: more plans than the risk level allows, an exercise above the
  /// current intensity limit, or a daily time above the current limit. Nothing
  /// is stopped here; the patient chooses what to keep.
  static List<PlanIssue> checkActive({
    required List<PatientTreatmentPlan> active,
    required RiskLevel risk,
    required SafetyLimit limit,
  }) {
    final issues = <PlanIssue>[];
    final cap = maxActivePlans(risk);
    if (active.length > cap) {
      issues.add(
        PlanIssue(
          PlanIssueLevel.replace,
          'over_cap',
          'Your current plans are more than your health profile now allows '
              '($cap at a time). Choose which to keep.',
        ),
      );
    }
    for (final a in active) {
      final tooHard = [
        for (final pe in a.plan.exercises)
          if (!limit.permits(pe.exercise)) pe.exercise.exerciseName,
      ];
      if (tooHard.isNotEmpty) {
        issues.add(
          PlanIssue(
            PlanIssueLevel.warning,
            'intensity_now',
            '${a.plan.planName} has exercises that are now harder than your '
                'health profile allows (${tooHard.join(', ')}). Talk to your '
                'doctor or physiotherapist, or choose a new plan.',
            patientPlanId: a.patientPlanId,
          ),
        );
      }
    }
    final dailySec = dailyWorstCaseSec([for (final a in active) a.plan]);
    if (active.length > 1 && dailySec > limit.maxSessionDurationMin * 60) {
      issues.add(
        PlanIssue(
          PlanIssueLevel.warning,
          'daily_time_now',
          'Together your plans could need up to ${_minutes(dailySec)} a day, '
              'more than the ${limit.maxSessionDurationMin} minutes your '
              'health profile now allows. Consider keeping fewer plans.',
        ),
      );
    }
    return issues;
  }

  static bool canAdd(List<PlanIssue> issues) =>
      issues.every((i) => i.level != PlanIssueLevel.block);
}
