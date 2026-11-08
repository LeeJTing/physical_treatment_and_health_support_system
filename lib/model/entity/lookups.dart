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

/// Dietary restriction lookup (Table 4.5): since 1 Nov a food name the patient cannot eat (Onion,
/// Garlic, Pork, Prawn, ...), whatever the reason (allergy, religion, dislike). Each catalogue food
/// carries the food names its recipe contains (food_restriction), so a dish with one of them is
/// Not Suitable. Owned by M700; kept here because the shared profile screen lets the patient
/// declare them.
class DietaryRestriction {
  final int restrictionId;
  final String restrictionCode;
  final String restrictionName;
  final RestrictionType restrictionType;

  /// Heading the profile screen groups the names under.
  final String? foodGroup;

  /// False for the diet labels no longer offered (VEGAN, VEGETARIAN, HALAL, SHELLFISH).
  final bool isActive;

  const DietaryRestriction(
    this.restrictionId,
    this.restrictionCode,
    this.restrictionName,
    this.restrictionType, {
    this.foodGroup,
    this.isActive = true,
  });

  bool isHardBlock() =>
      restrictionType == RestrictionType.allergy ||
      restrictionType == RestrictionType.intolerance ||
      restrictionType == RestrictionType.food;

  /// The diet labels saved before the list became food names, and the food names each rules out
  /// (same as the migration 20261101120000 and the AI server's catalogue.expand_restrictions).
  static const retired = <String, List<String>>{
    'SHELLFISH': ['PRAWN', 'SHRIMP_PASTE', 'CRAB', 'SQUID', 'MOLLUSC'],
    'VEGAN': ['PORK', 'LARD', 'BEEF', 'MUTTON', 'CHICKEN', 'DUCK', 'FISH', 'ANCHOVY', 'PRAWN', 'SHRIMP_PASTE', 'CRAB', 'SQUID', 'MOLLUSC', 'EGG', 'MILK'],
    'VEGETARIAN': ['PORK', 'LARD', 'BEEF', 'MUTTON', 'CHICKEN', 'DUCK', 'FISH', 'ANCHOVY', 'PRAWN', 'SHRIMP_PASTE', 'CRAB', 'SQUID', 'MOLLUSC'],
    'HALAL': ['PORK', 'LARD', 'ALCOHOL'],
  };

  /// Food-name codes for a list of declared codes (an old label becomes its food names).
  static List<String> expandCodes(Iterable<String> codes) {
    final out = <String>[];
    for (final c in codes) {
      for (final x in retired[c] ?? [c]) {
        if (!out.contains(x)) out.add(x);
      }
    }
    return out;
  }

  factory DietaryRestriction.fromJson(Map<String, dynamic> j) =>
      DietaryRestriction(
        (j['restriction_id'] as num).toInt(),
        j['restriction_code'] as String,
        j['restriction_name'] as String,
        RestrictionType.fromDb(j['restriction_type'] as String?),
        foodGroup: j['food_group'] as String?,
        isActive: j['is_active'] as bool? ?? true,
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

  /// Foods the patient cannot eat (M700): the 36 food names of the food catalogue
  /// (assets/seed/food_catalogue.json "exclusions"), the same rows as seed_food.sql and the
  /// migration 20261101120000_food_names_and_targets.sql.
  static const _meat = 'Meat, fish and seafood';
  static const _eggDairy = 'Egg, dairy, nuts and grains';
  static const _vegOther = 'Vegetables, fruit and others';

  /// The headings of [restrictions], in the order the profile screen shows them.
  static const foodGroups = [_meat, _eggDairy, _vegOther];

  static const restrictions = <DietaryRestriction>[
    DietaryRestriction(11, 'PORK', 'Pork', RestrictionType.food, foodGroup: _meat),
    DietaryRestriction(12, 'LARD', 'Lard (pork fat)', RestrictionType.food, foodGroup: _meat),
    DietaryRestriction(10, 'BEEF', 'Beef', RestrictionType.food, foodGroup: _meat),
    DietaryRestriction(13, 'MUTTON', 'Mutton or lamb', RestrictionType.food, foodGroup: _meat),
    DietaryRestriction(14, 'CHICKEN', 'Chicken', RestrictionType.food, foodGroup: _meat),
    DietaryRestriction(15, 'DUCK', 'Duck', RestrictionType.food, foodGroup: _meat),
    DietaryRestriction(6, 'FISH', 'Fish (incl. fish sauce, fish balls)', RestrictionType.food, foodGroup: _meat),
    DietaryRestriction(16, 'ANCHOVY', 'Anchovies (ikan bilis)', RestrictionType.food, foodGroup: _meat),
    DietaryRestriction(17, 'PRAWN', 'Prawn or shrimp (incl. dried shrimp)', RestrictionType.food, foodGroup: _meat),
    DietaryRestriction(18, 'SHRIMP_PASTE', 'Shrimp paste (belacan)', RestrictionType.food, foodGroup: _meat),
    DietaryRestriction(19, 'CRAB', 'Crab', RestrictionType.food, foodGroup: _meat),
    DietaryRestriction(20, 'SQUID', 'Squid or cuttlefish', RestrictionType.food, foodGroup: _meat),
    DietaryRestriction(21, 'MOLLUSC', 'Clams, cockles or oyster sauce', RestrictionType.food, foodGroup: _meat),
    DietaryRestriction(7, 'EGG', 'Egg', RestrictionType.food, foodGroup: _eggDairy),
    DietaryRestriction(8, 'MILK', 'Milk and dairy (incl. condensed milk, ghee)', RestrictionType.food, foodGroup: _eggDairy),
    DietaryRestriction(1, 'PEANUT', 'Peanut', RestrictionType.food, foodGroup: _eggDairy),
    DietaryRestriction(22, 'TREE_NUT', 'Tree nuts (almond, cashew)', RestrictionType.food, foodGroup: _eggDairy),
    DietaryRestriction(23, 'SOY', 'Soy (tofu, tempeh, soy sauce, soya milk)', RestrictionType.food, foodGroup: _eggDairy),
    DietaryRestriction(24, 'SESAME', 'Sesame', RestrictionType.food, foodGroup: _eggDairy),
    DietaryRestriction(25, 'BEANS', 'Beans and lentils (dhal, kacang)', RestrictionType.food, foodGroup: _eggDairy),
    DietaryRestriction(9, 'GLUTEN', 'Wheat (gluten)', RestrictionType.food, foodGroup: _eggDairy),
    DietaryRestriction(26, 'ONION', 'Onion, shallot or spring onion', RestrictionType.food, foodGroup: _vegOther),
    DietaryRestriction(27, 'GARLIC', 'Garlic', RestrictionType.food, foodGroup: _vegOther),
    DietaryRestriction(28, 'CHILLI', 'Chilli', RestrictionType.food, foodGroup: _vegOther),
    DietaryRestriction(29, 'COCONUT', 'Coconut and coconut milk (santan)', RestrictionType.food, foodGroup: _vegOther),
    DietaryRestriction(30, 'MUSHROOM', 'Mushroom', RestrictionType.food, foodGroup: _vegOther),
    DietaryRestriction(31, 'TOMATO', 'Tomato', RestrictionType.food, foodGroup: _vegOther),
    DietaryRestriction(32, 'BRINJAL', 'Brinjal (eggplant)', RestrictionType.food, foodGroup: _vegOther),
    DietaryRestriction(33, 'POTATO', 'Potato', RestrictionType.food, foodGroup: _vegOther),
    DietaryRestriction(34, 'CORN', 'Corn', RestrictionType.food, foodGroup: _vegOther),
    DietaryRestriction(35, 'BANANA', 'Banana', RestrictionType.food, foodGroup: _vegOther),
    DietaryRestriction(36, 'MANGO', 'Mango', RestrictionType.food, foodGroup: _vegOther),
    DietaryRestriction(37, 'PINEAPPLE', 'Pineapple', RestrictionType.food, foodGroup: _vegOther),
    DietaryRestriction(38, 'DURIAN', 'Durian', RestrictionType.food, foodGroup: _vegOther),
    DietaryRestriction(39, 'ALCOHOL', 'Alcohol (incl. cooking wine)', RestrictionType.food, foodGroup: _vegOther),
    DietaryRestriction(40, 'CAFFEINE', 'Coffee or tea (caffeine)', RestrictionType.food, foodGroup: _vegOther),
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
