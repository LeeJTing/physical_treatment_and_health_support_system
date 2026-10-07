import 'package:physical_treatment_and_health_support_system/model/entity/enums.dart';

/// Patient-facing wording for the stored codes.
class RehabLabels {
  RehabLabels._();

  static const bodyArea = {
    'LEFT_ARM': 'Left arm',
    'RIGHT_ARM': 'Right arm',
    'BOTH_ARMS': 'Both arms',
    'LEFT_LEG': 'Left leg',
    'RIGHT_LEG': 'Right leg',
    'BOTH_LEGS': 'Both legs',
    'CORE': 'Core and back',
    'FULL_BODY': 'Full body',
  };

  static const goal = {
    'STRENGTH': 'Build strength',
    'MOBILITY': 'Move more freely',
    'BALANCE': 'Better balance',
    'PAIN_RELIEF': 'Ease pain',
    'ENDURANCE': 'More stamina',
  };

  static const stage = {
    RecoveryStage.early: ('Early', 'Just started recovering'),
    RecoveryStage.intermediate: ('Intermediate', 'Some movement is back'),
    RecoveryStage.advanced: ('Advanced', 'Nearly back to normal'),
  };

  static const mobility = {
    MobilityLevel.low: ('Low', 'Need support to move'),
    MobilityLevel.moderate: ('Moderate', 'Move slowly on my own'),
    MobilityLevel.high: ('High', 'Move freely'),
  };

  static String area(String code) => bodyArea[code] ?? code;

  static String duration(int seconds) => seconds < 60
      ? '$seconds sec'
      : '${(seconds / 60).toStringAsFixed(seconds % 60 == 0 ? 0 : 1)} min';
}
