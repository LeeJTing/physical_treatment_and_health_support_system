import 'package:physical_treatment_and_health_support_system/model/entity/biometric_reading.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/exercise_session.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/meal_log.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/plan_comparison.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/recovery_check_in.dart';

enum TimelineKind { planned, meal, reading, exercise, recovery }

class HealthTimelineEvent {
  final String id, title, detail;
  final DateTime at;
  final TimelineKind kind;
  final bool isDemo;
  const HealthTimelineEvent(
    this.id,
    this.at,
    this.kind,
    this.title,
    this.detail, {
    this.isDemo = false,
  });
}

class InsightFact {
  final String title, text;
  final List<DateTime> evidenceDays;
  const InsightFact(this.title, this.text, this.evidenceDays);
}

class ExerciseEvidence {
  final ExerciseSession session;
  final String planName, exerciseName;
  const ExerciseEvidence(this.session, this.planName, this.exerciseName);
  bool get isDemo =>
      (session.modelVersion ?? '').startsWith('presentation-demo');
}

class RecoveryProgress {
  final String planId, planName;
  final List<RecoveryCheckIn> checkIns;
  final List<ExerciseEvidence> sessions;
  const RecoveryProgress(
    this.planId,
    this.planName,
    this.checkIns,
    this.sessions,
  );
  double? get painChange => checkIns.length < 2
      ? null
      : (checkIns.last.pain - checkIns.first.pain).toDouble();
  double? get stiffnessChange => checkIns.length < 2
      ? null
      : (checkIns.last.stiffness - checkIns.first.stiffness).toDouble();
  bool get worsening =>
      checkIns.length >= 2 &&
      (checkIns.last.pain > checkIns[checkIns.length - 2].pain ||
          checkIns.last.stiffness > checkIns[checkIns.length - 2].stiffness);
}

class HealthInsights {
  final String accountId;
  final DateTime start, end, asOf;
  final bool includesDemo;
  final List<MealLog> meals;
  final List<BiometricReading> readings;
  final List<ExerciseEvidence> sessions;
  final List<HealthTimelineEvent> timeline;
  final List<InsightFact> facts;
  final List<RecoveryProgress> recovery;
  final PlanComparisonReport comparison;
  final Map<String, int> sourceCounts;
  final List<String> notices;
  final int demoCount,
      loggedDays,
      completeMealDays,
      elapsedDays,
      invalidReadings;
  final DateTime? lastSync;
  const HealthInsights({
    required this.accountId,
    required this.start,
    required this.end,
    required this.asOf,
    required this.includesDemo,
    required this.meals,
    required this.readings,
    required this.sessions,
    required this.timeline,
    required this.facts,
    required this.recovery,
    required this.comparison,
    required this.sourceCounts,
    required this.notices,
    required this.demoCount,
    required this.loggedDays,
    required this.completeMealDays,
    required this.elapsedDays,
    required this.invalidReadings,
    this.lastSync,
  });
}
