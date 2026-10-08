import 'package:physical_treatment_and_health_support_system/model/entity/enums.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/lookups.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/safety_limit.dart';

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

  static final RegExp _camera = RegExp(r'^Camera:\s*([^.]*)\.\s*');

  /// Pose keys the server checks with its hand model (608b5ce): done seated at
  /// a table, so only the forearm and hand need to be in the picture.
  static const handPoseKeys = {'wrist_extension', 'hand_open_close'};

  /// Recorded seated at a table with the hands in frame, not the whole body.
  bool get recordsHands => handPoseKeys.contains(poseKey);

  /// Where to put the phone when recording, e.g. "side view, whole body in frame".
  /// Null when the instruction text has no "Camera: ..." sentence.
  String? get cameraTip {
    final m = _camera.firstMatch(instructionText);
    if (m == null) return null;
    final tip = m.group(1)!.trim();
    return tip.isEmpty ? null : '${tip[0].toUpperCase()}${tip.substring(1)}.';
  }

  /// The steps and safety points, without the recording tip.
  String get steps => instructionText.replaceFirst(_camera, '').trim();

  bool isSafeFor(SafetyLimit s) => s.permits(this);

  /// Whether the target body area is one the patient cannot use.
  /// BOTH_ARMS conflicts with either arm limitation; BOTH_LEGS / FULL_BODY with either leg.
  bool conflictsWith(PhysicalLimitation l) {
    final blocked = l.blockedBodyArea(); // e.g. LEFT_ARM
    if (blocked == null) return false;
    if (targetBodyArea == blocked) return true;
    final isArm = blocked.endsWith('_ARM');
    if (isArm && targetBodyArea == 'BOTH_ARMS') return true;
    if (!isArm &&
        (targetBodyArea == 'BOTH_LEGS' || targetBodyArea == 'FULL_BODY')) {
      return true;
    }
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
