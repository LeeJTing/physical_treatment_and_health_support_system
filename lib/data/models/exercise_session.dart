import 'package:physical_treatment_and_health_support_system/data/models/enums.dart';

/// One exercise attempt and its posture result (Table 4.15).
class ExerciseSession {
  /// Accuracy at or above this counts as passing and updates the pathway automatically
  /// (UI Design, Posture Result Screen: "over 80% triggers an auto update").
  static const double passMark = 80;

  final String sessionId;
  final String accountId;
  final String? patientPlanId;
  final String exerciseId;
  final DateTime? completedAt;
  final int? durationSec;
  final int? repetitionsCompleted;
  final CompletionStatus completionStatus;
  final double? postureAccuracy;
  final String? postureFeedback;
  final String? modelVersion;

  const ExerciseSession({
    required this.sessionId,
    required this.accountId,
    this.patientPlanId,
    required this.exerciseId,
    this.completedAt,
    this.durationSec,
    this.repetitionsCompleted,
    required this.completionStatus,
    this.postureAccuracy,
    this.postureFeedback,
    this.modelVersion,
  });

  bool isCompleted() => completionStatus == CompletionStatus.completed;
  bool postureIsPassing() => (postureAccuracy ?? 0) >= passMark;
  double durationMinutes() => (durationSec ?? 0) / 60;

  ExerciseSession withStatus(CompletionStatus s) => ExerciseSession(
        sessionId: sessionId,
        accountId: accountId,
        patientPlanId: patientPlanId,
        exerciseId: exerciseId,
        completedAt: s == CompletionStatus.completed ? (completedAt ?? DateTime.now()) : null,
        durationSec: durationSec,
        repetitionsCompleted: repetitionsCompleted,
        completionStatus: s,
        postureAccuracy: postureAccuracy,
        postureFeedback: postureFeedback,
        modelVersion: modelVersion,
      );

  Map<String, dynamic> toJson() => {
        'session_id': sessionId,
        'account_id': accountId,
        'patient_plan_id': patientPlanId,
        'exercise_id': exerciseId,
        'completed_at': completedAt?.toIso8601String(),
        'duration_sec': durationSec,
        'repetitions_completed': repetitionsCompleted,
        'completion_status': completionStatus.db,
        'posture_accuracy': postureAccuracy,
        'posture_feedback': postureFeedback,
        'model_version': modelVersion,
      };

  factory ExerciseSession.fromJson(Map<String, dynamic> j) => ExerciseSession(
        sessionId: j['session_id'] as String,
        accountId: j['account_id'] as String,
        patientPlanId: j['patient_plan_id'] as String?,
        exerciseId: j['exercise_id'] as String,
        completedAt: j['completed_at'] == null ? null : DateTime.parse(j['completed_at'] as String),
        durationSec: (j['duration_sec'] as num?)?.toInt(),
        repetitionsCompleted: (j['repetitions_completed'] as num?)?.toInt(),
        completionStatus: CompletionStatus.fromDb(j['completion_status'] as String?),
        postureAccuracy: (j['posture_accuracy'] as num?)?.toDouble(),
        postureFeedback: j['posture_feedback'] as String?,
        modelVersion: j['model_version'] as String?,
      );
}

/// Response of the /pose endpoint (FR300_07 to FR300_10). Not stored on its own: copied
/// into an ExerciseSession (one result per session). Errors (no body found, body not fully in
/// frame, no repetition) come back as failures instead, so a result always has a detected pose.
class PostureResult {
  final bool fullBodyVisible;
  final double accuracy; // 0..100
  final int repetitions;
  final double? holdSeconds; // hold exercises such as Tandem Stance
  final List<String> feedback;
  final Map<String, int> mistakes; // mistake label -> repetitions it was seen in
  final String modelVersion;

  const PostureResult({
    this.fullBodyVisible = true,
    required this.accuracy,
    required this.repetitions,
    this.holdSeconds,
    required this.feedback,
    this.mistakes = const {},
    required this.modelVersion,
  });

  bool get isPassing => accuracy >= ExerciseSession.passMark;

  factory PostureResult.fromJson(Map<String, dynamic> j) => PostureResult(
        fullBodyVisible: (j['full_body_visible'] ?? true) as bool,
        accuracy: (j['accuracy'] as num?)?.toDouble() ?? 0,
        repetitions: (j['repetitions'] as num?)?.toInt() ?? 0,
        holdSeconds: (j['hold_seconds'] as num?)?.toDouble(),
        feedback: ((j['feedback'] as List?) ?? const []).map((e) => e.toString()).toList(),
        mistakes: {
          for (final e in ((j['mistakes'] as Map?) ?? const {}).entries) e.key.toString(): (e.value as num).toInt()
        },
        modelVersion: (j['model_version'] ?? 'unknown') as String,
      );
}
