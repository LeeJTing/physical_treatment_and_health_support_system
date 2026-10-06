import 'package:physical_treatment_and_health_support_system/data/models/enums.dart';
import 'package:physical_treatment_and_health_support_system/data/models/lookups.dart';
import 'package:physical_treatment_and_health_support_system/data/models/safety_limit.dart';

/// Rehabilitation exercise in the shared catalogue (Table 4.14).
class Exercise {
  final String exerciseId;
  final String exerciseName;
  final String instructionText;
  /// One of LEFT_ARM, RIGHT_ARM, BOTH_ARMS, LEFT_LEG, RIGHT_LEG, BOTH_LEGS, CORE, FULL_BODY.
  final String targetBodyArea;
  final ExerciseIntensity intensityLevel;
  final int defaultRepetitions;
  final int defaultDurationSec;
  /// Key of the posture model for this exercise on the AI server, e.g. "sit_to_stand".
  /// Null when the exercise has no posture model yet.
  final String? poseKey;

  const Exercise({
    required this.exerciseId,
    required this.exerciseName,
    required this.instructionText,
    required this.targetBodyArea,
    required this.intensityLevel,
    required this.defaultRepetitions,
    required this.defaultDurationSec,
    this.poseKey,
  });

  bool isSafeFor(SafetyLimit s) => s.permits(this);

  /// Whether the target body area is one the patient cannot use.
  /// BOTH_ARMS conflicts with either arm limitation; BOTH_LEGS / FULL_BODY with either leg.
  bool conflictsWith(PhysicalLimitation l) {
    final blocked = l.blockedBodyArea(); // e.g. LEFT_ARM
    if (blocked == null) return false;
    if (targetBodyArea == blocked) return true;
    final isArm = blocked.endsWith('_ARM');
    if (isArm && targetBodyArea == 'BOTH_ARMS') return true;
    if (!isArm && (targetBodyArea == 'BOTH_LEGS' || targetBodyArea == 'FULL_BODY')) return true;
    return false;
  }

  factory Exercise.fromJson(Map<String, dynamic> j) => Exercise(
        exerciseId: j['exercise_id'] as String,
        exerciseName: j['exercise_name'] as String,
        instructionText: j['instruction_text'] as String,
        targetBodyArea: j['target_body_area'] as String,
        intensityLevel: ExerciseIntensity.fromDb(j['intensity_level'] as String?),
        defaultRepetitions: (j['default_repetitions'] as num).toInt(),
        defaultDurationSec: (j['default_duration_sec'] as num).toInt(),
        poseKey: j['pose_key'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'exercise_id': exerciseId,
        'exercise_name': exerciseName,
        'instruction_text': instructionText,
        'target_body_area': targetBodyArea,
        'intensity_level': intensityLevel.db,
        'default_repetitions': defaultRepetitions,
        'default_duration_sec': defaultDurationSec,
        'pose_key': poseKey,
      };
}
