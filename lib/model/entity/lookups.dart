import 'package:physical_treatment_and_health_support_system/model/entity/enums.dart';

/// Health condition lookup (Table 4.6). Since 11 Oct a condition may carry the
/// question the profile asks about its status, and whether a doctor's OK is
/// needed before an exercise plan when the answer is no. On a profile,
/// [controlled] and [note] are the patient's answers (profile_condition).
class HealthCondition {
  final int conditionId;
  final String conditionCode;
  final String conditionName;
  final ConditionCategory category;

  /// E.g. "Is it under control with treatment?"; null = nothing to ask.
  final String? statusQuestion;

  /// When the answer is no, no exercise plan until a doctor agrees.
  final bool needsClearance;

  /// The patient's answer to [statusQuestion] (true when there is none).
  final bool controlled;

  /// What the "Other" condition is.
  final String? note;

  const HealthCondition(
    this.conditionId,
    this.conditionCode,
    this.conditionName,
    this.category, {
    this.statusQuestion,
    this.needsClearance = false,
    this.controlled = true,
    this.note,
  });

  bool isCardiovascular() => category == ConditionCategory.cardiovascular;

  /// Cardiovascular and neurological conditions make the risk level high
  /// (neurological: balance and falls; 11 Oct).
  bool get alwaysHighRisk =>
      isCardiovascular() || category == ConditionCategory.neurological;

  /// The patient said no to a condition that needs a doctor's OK first.
  bool get blocksPlans => needsClearance && !controlled;

  bool get isOther => conditionCode == 'OTHER';

  HealthCondition withStatus({bool? controlled, String? note}) =>
      HealthCondition(
        conditionId,
        conditionCode,
        conditionName,
        category,
        statusQuestion: statusQuestion,
        needsClearance: needsClearance,
        controlled: controlled ?? this.controlled,
        note: note ?? this.note,
      );

  factory HealthCondition.fromJson(Map<String, dynamic> j) => HealthCondition(
    (j['condition_id'] as num).toInt(),
    j['condition_code'] as String,
    j['condition_name'] as String,
    ConditionCategory.fromDb(j['category'] as String?),
    statusQuestion: j['status_question'] as String?,
    needsClearance: j['needs_clearance'] as bool? ?? false,
  );

  @override
  bool operator ==(Object other) =>
      other is HealthCondition && other.conditionId == conditionId;
  @override
  int get hashCode => conditionId.hashCode;
}

/// Physical limitation lookup (Table 4.8).
class PhysicalLimitation {
  final int limitationId;
  final String limitationCode;
  final String limitationName;
  final LimitationCategory category;

  const PhysicalLimitation(
    this.limitationId,
    this.limitationCode,
    this.limitationName,
    this.category,
  );

  bool affectsBalance() => category == LimitationCategory.balance;

  /// Body area the limitation blocks, matched against Exercise.targetBodyArea.
  /// LEFT_ARM_MOBILITY -> LEFT_ARM. Balance limitations block no single area.
  String? blockedBodyArea() {
    if (affectsBalance()) return null;
    return limitationCode.replaceAll('_MOBILITY', '');
  }

  factory PhysicalLimitation.fromJson(Map<String, dynamic> j) =>
      PhysicalLimitation(
        (j['limitation_id'] as num).toInt(),
        j['limitation_code'] as String,
        j['limitation_name'] as String,
        LimitationCategory.fromDb(j['category'] as String?),
      );

  @override
  bool operator ==(Object other) =>
      other is PhysicalLimitation && other.limitationId == limitationId;
  @override
  int get hashCode => limitationId.hashCode;
}

/// Dietary restriction lookup (Table 4.5). Owned by M700; kept here because
/// the shared profile screen lets the patient declare them.
class DietaryRestriction {
  final int restrictionId;
  final String restrictionCode;
  final String restrictionName;
  final RestrictionType restrictionType;

  const DietaryRestriction(
    this.restrictionId,
    this.restrictionCode,
    this.restrictionName,
    this.restrictionType,
  );

  bool isHardBlock() =>
      restrictionType == RestrictionType.allergy ||
      restrictionType == RestrictionType.intolerance;

  factory DietaryRestriction.fromJson(Map<String, dynamic> j) =>
      DietaryRestriction(
        (j['restriction_id'] as num).toInt(),
        j['restriction_code'] as String,
        j['restriction_name'] as String,
        RestrictionType.fromDb(j['restriction_type'] as String?),
      );

  @override
  bool operator ==(Object other) =>
      other is DietaryRestriction && other.restrictionId == restrictionId;
  @override
  int get hashCode => restrictionId.hashCode;
}

/// Seed values from the Table 3.3 lists. Used by the fakes and as the
/// reference for the Supabase seed.
class LookupSeed {
  LookupSeed._();

  /// Same rows as supabase/seed/seed_lookups.sql (test/conditions_test.dart).
  static const conditions = <HealthCondition>[
    HealthCondition(
      1,
      'HYPERTENSION',
      'High blood pressure',
      ConditionCategory.cardiovascular,
      statusQuestion: 'Is it under control with treatment?',
      needsClearance: true,
    ),
    HealthCondition(
      2,
      'DIABETES',
      'Diabetes Mellitus',
      ConditionCategory.metabolic,
      statusQuestion: 'Is it under control (no frequent low blood sugar)?',
      needsClearance: true,
    ),
    HealthCondition(
      3,
      'HEART_DISEASE',
      'Heart Disease',
      ConditionCategory.cardiovascular,
      statusQuestion: 'Has your doctor said it is stable?',
      needsClearance: true,
    ),
    HealthCondition(4, 'STROKE', 'Stroke', ConditionCategory.cardiovascular),
    HealthCondition(
      5,
      'ARTHRITIS',
      'Arthritis',
      ConditionCategory.musculoskeletal,
      statusQuestion: 'Is it settled now (no flare-up)?',
    ),
    HealthCondition(
      6,
      'OSTEOPOROSIS',
      'Osteoporosis',
      ConditionCategory.musculoskeletal,
    ),
    HealthCondition(
      7,
      'ASTHMA',
      'Asthma',
      ConditionCategory.respiratory,
      statusQuestion: 'Is it under control with treatment?',
      needsClearance: true,
    ),
    HealthCondition(
      8,
      'PREGNANCY',
      'Pregnancy or recent birth',
      ConditionCategory.reproductive,
      statusQuestion: 'Has your doctor or midwife said exercise is safe for you?',
      needsClearance: true,
    ),
    HealthCondition(
      9,
      'JOINT_REPLACEMENT',
      'Hip, knee or shoulder replacement',
      ConditionCategory.musculoskeletal,
      statusQuestion:
          'Has your surgeon or physiotherapist cleared you to exercise at home?',
      needsClearance: true,
    ),
    HealthCondition(
      10,
      'RHEUMATOID_ARTHRITIS',
      'Rheumatoid arthritis',
      ConditionCategory.musculoskeletal,
      statusQuestion: 'Is it settled now (no flare-up)?',
    ),
    HealthCondition(
      11,
      'COPD',
      'Chronic lung disease (COPD)',
      ConditionCategory.respiratory,
      statusQuestion: 'Is it stable (no flare-up in the last 4 weeks)?',
      needsClearance: true,
    ),
    HealthCondition(
      12,
      'CANCER',
      'Cancer (now or in the past)',
      ConditionCategory.oncology,
      statusQuestion: 'Has your doctor cleared you to exercise?',
      needsClearance: true,
    ),
    HealthCondition(
      13,
      'KIDNEY_DISEASE',
      'Chronic kidney disease',
      ConditionCategory.renal,
      statusQuestion: "Is it stable under your doctor's care?",
    ),
    HealthCondition(
      14,
      'PARKINSONS',
      "Parkinson's disease",
      ConditionCategory.neurological,
    ),
    HealthCondition(
      15,
      'MULTIPLE_SCLEROSIS',
      'Multiple sclerosis',
      ConditionCategory.neurological,
      statusQuestion: 'Is it stable (no relapse in the last month)?',
      needsClearance: true,
    ),
    HealthCondition(
      16,
      'FOOT_ULCER',
      'Foot ulcer or open wound on the foot',
      ConditionCategory.metabolic,
    ),
    HealthCondition(
      17,
      'OTHER',
      'Other condition (not listed)',
      ConditionCategory.other,
      statusQuestion: 'Has your doctor cleared you to exercise?',
      needsClearance: true,
    ),
  ];

  static const limitations = <PhysicalLimitation>[
    PhysicalLimitation(
      1,
      'LEFT_ARM_MOBILITY',
      'Left Arm Mobility Limitation',
      LimitationCategory.mobility,
    ),
    PhysicalLimitation(
      2,
      'RIGHT_ARM_MOBILITY',
      'Right Arm Mobility Limitation',
      LimitationCategory.mobility,
    ),
    PhysicalLimitation(
      3,
      'LEFT_LEG_MOBILITY',
      'Left Leg Mobility Limitation',
      LimitationCategory.mobility,
    ),
    PhysicalLimitation(
      4,
      'RIGHT_LEG_MOBILITY',
      'Right Leg Mobility Limitation',
      LimitationCategory.mobility,
    ),
    PhysicalLimitation(
      5,
      'BALANCE_IMPAIRMENT',
      'Balance Impairment',
      LimitationCategory.balance,
    ),
  ];
}
