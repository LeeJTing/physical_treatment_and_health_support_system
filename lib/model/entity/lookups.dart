import 'package:physical_treatment_and_health_support_system/model/entity/enums.dart';

/// Health condition lookup (Table 4.6).
class HealthCondition {
  final int conditionId;
  final String conditionCode;
  final String conditionName;
  final ConditionCategory category;

  const HealthCondition(
    this.conditionId,
    this.conditionCode,
    this.conditionName,
    this.category,
  );

  bool isCardiovascular() => category == ConditionCategory.cardiovascular;

  factory HealthCondition.fromJson(Map<String, dynamic> j) => HealthCondition(
    (j['condition_id'] as num).toInt(),
    j['condition_code'] as String,
    j['condition_name'] as String,
    ConditionCategory.fromDb(j['category'] as String?),
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

  static const conditions = <HealthCondition>[
    HealthCondition(
      1,
      'HYPERTENSION',
      'High blood pressure',
      ConditionCategory.cardiovascular,
    ),
    HealthCondition(
      2,
      'DIABETES',
      'Diabetes Mellitus',
      ConditionCategory.metabolic,
    ),
    HealthCondition(
      3,
      'HEART_DISEASE',
      'Heart Disease',
      ConditionCategory.cardiovascular,
    ),
    HealthCondition(4, 'STROKE', 'Stroke', ConditionCategory.cardiovascular),
    HealthCondition(
      5,
      'ARTHRITIS',
      'Arthritis',
      ConditionCategory.musculoskeletal,
    ),
    HealthCondition(
      6,
      'OSTEOPOROSIS',
      'Osteoporosis',
      ConditionCategory.musculoskeletal,
    ),
    HealthCondition(7, 'ASTHMA', 'Asthma', ConditionCategory.respiratory),
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
