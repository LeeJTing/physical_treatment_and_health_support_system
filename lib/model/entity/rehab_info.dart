import 'package:physical_treatment_and_health_support_system/model/entity/enums.dart';

/// Rehabilitation details asked at the start of UC400 (FR500_03): affected
/// body area, recovery stage, mobility level and goal. Not a column in
/// health_profile (see IMPLEMENTATION_PLAN.md open issue 1), so it is sent
/// with the /recommend request rather than stored.
class RehabInfo {
  final String affectedBodyArea;
  final RecoveryStage recoveryStage;
  final MobilityLevel mobilityLevel;

  /// One of STRENGTH, MOBILITY, BALANCE, PAIN_RELIEF, ENDURANCE.
  final String goal;

  /// Finer body parts tapped on the body map (shoulder, elbow, wrist_hand,
  /// hip, knee, ankle_foot, back). Empty when the list fallback was used.
  /// Sent next to `rehab` as focus_parts, not part of [toJson].
  final List<String> focusParts;

  const RehabInfo({
    required this.affectedBodyArea,
    required this.recoveryStage,
    required this.mobilityLevel,
    required this.goal,
    this.focusParts = const [],
  });

  Map<String, dynamic> toJson() => {
    'affected_body_area': affectedBodyArea,
    'recovery_stage': recoveryStage.db,
    'mobility_level': mobilityLevel.db,
    'goal': goal,
  };

  static const bodyAreas = [
    'LEFT_ARM',
    'RIGHT_ARM',
    'BOTH_ARMS',
    'LEFT_LEG',
    'RIGHT_LEG',
    'BOTH_LEGS',
    'CORE',
    'FULL_BODY',
  ];
  static const goals = [
    'STRENGTH',
    'MOBILITY',
    'BALANCE',
    'PAIN_RELIEF',
    'ENDURANCE',
  ];
}
