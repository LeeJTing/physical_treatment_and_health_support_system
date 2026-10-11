import 'package:flutter/material.dart';

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

  /// One-line hints and icons for the questionnaire's answer cards.
  static const goalHint = {
    'STRENGTH': 'Stronger muscles for daily tasks',
    'MOBILITY': 'Bend, reach and turn more easily',
    'BALANCE': 'Steadier on your feet',
    'PAIN_RELIEF': 'Gentle exercises to ease pain',
    'ENDURANCE': 'Keep going for longer',
  };

  static const goalIcon = {
    'STRENGTH': Icons.fitness_center,
    'MOBILITY': Icons.accessibility_new,
    'BALANCE': Icons.balance,
    'PAIN_RELIEF': Icons.healing,
    'ENDURANCE': Icons.favorite_border,
  };

  static const stageIcon = {
    RecoveryStage.early: Icons.eco_outlined,
    RecoveryStage.intermediate: Icons.trending_up,
    RecoveryStage.advanced: Icons.flag_outlined,
  };

  static const mobilityIcon = {
    MobilityLevel.low: Icons.assist_walker,
    MobilityLevel.moderate: Icons.directions_walk,
    MobilityLevel.high: Icons.directions_run,
  };

  /// Optional pace (RehabInfo.pace): how many days a week the patient wants
  /// to exercise; the recommender prefers plans with that frequency.
  static const pace = {
    'SLOW': ('Gentle', 'About 3 days a week', Icons.self_improvement),
    'MEDIUM': ('Steady', 'About 4 days a week', Icons.calendar_view_week),
    'FAST': ('Faster', 'About 5 days a week', Icons.speed),
  };

  static String area(String code) => bodyArea[code] ?? code;

  static String duration(int seconds) => seconds < 60
      ? '$seconds sec'
      : '${(seconds / 60).toStringAsFixed(seconds % 60 == 0 ? 0 : 1)} min';
}
