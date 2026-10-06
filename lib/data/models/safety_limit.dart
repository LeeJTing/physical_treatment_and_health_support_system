import 'package:physical_treatment_and_health_support_system/data/models/enums.dart';
import 'package:physical_treatment_and_health_support_system/data/models/exercise.dart';

/// Safety values generated from the risk level (Table 4.12). Read by M300,
/// M500 and M700 before anything is recommended (FR100_056).
class SafetyLimit {
  final String safetyLimitId;
  final String? profileId;
  final ExerciseIntensity maxExerciseIntensity;
  final int maxSessionDurationMin;
  final int dailyCalorieTarget;
  final int dailySodiumLimitMg;
  final double dailySugarLimitG;
  final bool isCurrent;

  const SafetyLimit({
    required this.safetyLimitId,
    this.profileId,
    required this.maxExerciseIntensity,
    required this.maxSessionDurationMin,
    required this.dailyCalorieTarget,
    required this.dailySodiumLimitMg,
    required this.dailySugarLimitG,
    this.isCurrent = true,
  });

  /// Whether an exercise is within the intensity cap and session duration.
  bool permits(Exercise e) =>
      e.intensityLevel.index <= maxExerciseIntensity.index &&
      e.defaultDurationSec <= maxSessionDurationMin * 60;

  double sodiumRemaining(double consumed) => dailySodiumLimitMg - consumed;
  double sugarRemaining(double consumed) => dailySugarLimitG - consumed;
  double energyRemaining(double consumed) => dailyCalorieTarget - consumed;

  /// Fail-safe default used when the profile cannot be read (UC1000 C5).
  static SafetyLimit mostRestrictive() => const SafetyLimit(
        safetyLimitId: 'fail-safe',
        maxExerciseIntensity: ExerciseIntensity.low,
        maxSessionDurationMin: 15,
        dailyCalorieTarget: 1600,
        dailySodiumLimitMg: 1500,
        dailySugarLimitG: 25,
      );

  factory SafetyLimit.fromJson(Map<String, dynamic> j) => SafetyLimit(
        safetyLimitId: j['safety_limit_id'] as String,
        profileId: j['profile_id'] as String?,
        maxExerciseIntensity: ExerciseIntensity.fromDb(j['max_exercise_intensity'] as String?),
        maxSessionDurationMin: (j['max_session_duration_min'] as num).toInt(),
        dailyCalorieTarget: (j['daily_calorie_target'] as num).toInt(),
        dailySodiumLimitMg: (j['daily_sodium_limit_mg'] as num).toInt(),
        dailySugarLimitG: (j['daily_sugar_limit_g'] as num).toDouble(),
        isCurrent: (j['is_current'] ?? true) as bool,
      );

  Map<String, dynamic> toJson() => {
        'safety_limit_id': safetyLimitId,
        'profile_id': profileId,
        'max_exercise_intensity': maxExerciseIntensity.db,
        'max_session_duration_min': maxSessionDurationMin,
        'daily_calorie_target': dailyCalorieTarget,
        'daily_sodium_limit_mg': dailySodiumLimitMg,
        'daily_sugar_limit_g': dailySugarLimitG,
        'is_current': isCurrent,
      };
}
