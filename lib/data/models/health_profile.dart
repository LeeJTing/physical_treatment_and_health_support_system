import 'package:physical_treatment_and_health_support_system/core/constants/app_constants.dart';
import 'package:physical_treatment_and_health_support_system/core/utils/id_utils.dart';
import 'package:physical_treatment_and_health_support_system/data/models/enums.dart';
import 'package:physical_treatment_and_health_support_system/data/models/lookups.dart';
import 'package:physical_treatment_and_health_support_system/data/models/safety_limit.dart';

/// The patient's body measurements and assigned risk level (Table 4.7).
class HealthProfile {
  final String profileId;
  final String accountId;
  final int? age;
  final Gender? gender;
  final double? weightKg;
  final double? heightCm;
  final List<HealthCondition> conditions;
  final List<PhysicalLimitation> limitations;
  final List<DietaryRestriction> restrictions;
  final int version; // FR100_053
  final DateTime updatedAt;

  const HealthProfile({
    required this.profileId,
    required this.accountId,
    this.age,
    this.gender,
    this.weightKg,
    this.heightCm,
    this.conditions = const [],
    this.limitations = const [],
    this.restrictions = const [],
    this.version = 0,
    required this.updatedAt,
  });

  factory HealthProfile.empty(String accountId) =>
      HealthProfile(profileId: newId(), accountId: accountId, updatedAt: DateTime.now());

  /// Derives BMI from weight and height (FR100_046). 0 when either is missing.
  double calculateBmi() {
    final w = weightKg, h = heightCm;
    if (w == null || h == null || h <= 0) return 0;
    final m = h / 100;
    return double.parse((w / (m * m)).toStringAsFixed(1));
  }

  double get bmi => calculateBmi();

  /// Risk rule set (Table 3.3, FR100_054):
  /// High = two or more conditions, any cardiovascular condition, or a balance limitation.
  /// Low = no condition and no limitation. Medium = all other cases.
  RiskLevel assignRiskLevel() {
    if (conditions.length >= 2 ||
        conditions.any((c) => c.isCardiovascular()) ||
        limitations.any((l) => l.affectsBalance())) {
      return RiskLevel.high;
    }
    if (conditions.isEmpty && limitations.isEmpty) return RiskLevel.low;
    return RiskLevel.medium;
  }

  RiskLevel get riskLevel => assignRiskLevel();

  /// Produces the safety values from the risk level (FR100_055).
  /// Intensity and duration caps per level are TO CONFIRM with the supervisor;
  /// the calorie target uses Mifflin-St Jeor x 1.2 (sedentary).
  SafetyLimit generateSafetyLimit() {
    final risk = assignRiskLevel();
    final (ExerciseIntensity intensity, int minutes) = switch (risk) {
      RiskLevel.low => (ExerciseIntensity.moderate, 45),
      RiskLevel.medium => (ExerciseIntensity.moderate, 30),
      RiskLevel.high => (ExerciseIntensity.low, 20),
    };
    final sodium = hasCondition('HYPERTENSION') || hasCondition('HEART_DISEASE') ? 1500 : 2000;
    final sugar = hasCondition('DIABETES') ? 25.0 : 50.0;
    return SafetyLimit(
      safetyLimitId: newId(),
      profileId: profileId,
      maxExerciseIntensity: intensity,
      maxSessionDurationMin: minutes,
      dailyCalorieTarget: _calorieTarget(),
      dailySodiumLimitMg: sodium,
      dailySugarLimitG: sugar,
    );
  }

  int _calorieTarget() {
    final w = weightKg, h = heightCm, a = age, g = gender;
    if (w == null || h == null || a == null || g == null) {
      return SafetyLimit.mostRestrictive().dailyCalorieTarget;
    }
    final bmr = 10 * w + 6.25 * h - 5 * a + (g == Gender.male ? 5 : -161);
    return (bmr * 1.2).round();
  }

  bool hasCondition(String code) => conditions.any((c) => c.conditionCode == code);

  List<String> restrictionCodes() => restrictions.map((r) => r.restrictionCode).toList();

  /// Mandatory values that are missing or out of range (FR100_045, FR100_049).
  List<String> validate() {
    final errors = <String>[];
    if (age == null) {
      errors.add('age');
    } else if (age! < AppConstants.ageMin || age! > AppConstants.ageMax) {
      errors.add('age');
    }
    if (gender == null) errors.add('gender');
    if (weightKg == null || weightKg! < AppConstants.weightMin || weightKg! > AppConstants.weightMax) {
      errors.add('weight');
    }
    if (heightCm == null || heightCm! < AppConstants.heightMin || heightCm! > AppConstants.heightMax) {
      errors.add('height');
    }
    return errors;
  }

  bool get isComplete => validate().isEmpty;

  bool isStale([DateTime? now]) =>
      (now ?? DateTime.now()).difference(updatedAt) > AppConstants.profileStaleAfter;

  HealthProfile copyWith({
    int? age,
    Gender? gender,
    double? weightKg,
    double? heightCm,
    List<HealthCondition>? conditions,
    List<PhysicalLimitation>? limitations,
    List<DietaryRestriction>? restrictions,
    int? version,
    DateTime? updatedAt,
  }) =>
      HealthProfile(
        profileId: profileId,
        accountId: accountId,
        age: age ?? this.age,
        gender: gender ?? this.gender,
        weightKg: weightKg ?? this.weightKg,
        heightCm: heightCm ?? this.heightCm,
        conditions: conditions ?? this.conditions,
        limitations: limitations ?? this.limitations,
        restrictions: restrictions ?? this.restrictions,
        version: version ?? this.version,
        updatedAt: updatedAt ?? this.updatedAt,
      );

  /// Row for the health_profile table. The three declaration lists are
  /// written to their association tables by the repository.
  Map<String, dynamic> toJson() => {
        'profile_id': profileId,
        'account_id': accountId,
        'age': age,
        'gender': gender?.db,
        'weight_kg': weightKg,
        'height_cm': heightCm,
        'bmi': calculateBmi(),
        'risk_level': assignRiskLevel().db,
        'is_complete': isComplete,
        'version': version,
        'updated_at': updatedAt.toIso8601String(),
      };

  factory HealthProfile.fromJson(
    Map<String, dynamic> j, {
    List<HealthCondition> conditions = const [],
    List<PhysicalLimitation> limitations = const [],
    List<DietaryRestriction> restrictions = const [],
  }) =>
      HealthProfile(
        profileId: j['profile_id'] as String,
        accountId: j['account_id'] as String,
        age: (j['age'] as num?)?.toInt(),
        gender: Gender.fromDb(j['gender'] as String?),
        weightKg: (j['weight_kg'] as num?)?.toDouble(),
        heightCm: (j['height_cm'] as num?)?.toDouble(),
        conditions: conditions,
        limitations: limitations,
        restrictions: restrictions,
        version: (j['version'] as num?)?.toInt() ?? 0,
        updatedAt: DateTime.parse(j['updated_at'] as String),
      );
}

/// Object returned by UC1000 Retrieve Profile Information (C2).
class ProfileSnapshot {
  final HealthProfile? profile;
  final SafetyLimit safetyLimit;
  final ProfileStatus status;

  const ProfileSnapshot({this.profile, required this.safetyLimit, required this.status});

  RiskLevel get riskLevel => profile?.assignRiskLevel() ?? RiskLevel.high;
}
