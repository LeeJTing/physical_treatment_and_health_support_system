import 'dart:math' as math;

/// Daily nutrition targets from the patient's profile (UC1000 data, UC900 C10): energy from the
/// body measurements and physical limitations, and what each declared condition limits or needs.
/// The AI server computes the same numbers (fyp-fastapi ai_server/app/food/targets.py);
/// test/diet_targets_test.dart and the server's tests/test_food_targets.py hold the same cases.
///
/// Energy: Mifflin-St Jeor resting energy (10 W + 6.25 H - 5 A + 5 men / - 161 women) times a
/// physical activity level (FAO/WHO/UNU 2004): 1.5, 1.45 with an arm limitation, 1.4 with a leg
/// or balance limitation. Pregnancy + 285 kcal (second trimester). BMI 27.5 or more (Asian cut-off,
/// MOH Malaysia CPG Obesity 2023) and not pregnant: - 500 kcal, never below 1200 (women) / 1500 (men).
///
/// Limits a plan must keep: sodium (at most 2000 mg, WHO 2012), free sugars (at most 25 g,
/// WHO 2015); saturated fat under 10 % of energy (WHO 2023) for heart disease, stroke,
/// hypertension and diabetes; protein at most 0.8 g/kg for chronic kidney disease (KDIGO 2024);
/// caffeine at most 200 mg in pregnancy. Needs a plan aims for: protein 1.2 g/kg for a foot ulcer,
/// cancer, COPD or a joint replacement (1.0 g/kg from age 65; ESPEN); calcium 1000 mg for
/// osteoporosis (MOH CPG 2022); fibre 25 g for Parkinson's, multiple sclerosis and diabetes.
class DietTargets {
  static const arm = {'LEFT_ARM_MOBILITY', 'RIGHT_ARM_MOBILITY'};
  static const legBalance = {'LEFT_LEG_MOBILITY', 'RIGHT_LEG_MOBILITY', 'BALANCE_IMPAIRMENT'};
  static const satFatConditions = {'HEART_DISEASE', 'STROKE', 'HYPERTENSION', 'DIABETES'};
  static const proteinNeed = {'FOOT_ULCER': 1.2, 'CANCER': 1.2, 'COPD': 1.2, 'JOINT_REPLACEMENT': 1.2};
  static const fibreNeed = {'PARKINSONS', 'MULTIPLE_SCLEROSIS', 'DIABETES'};
  static const whoSodiumMg = 2000.0;
  static const whoSugarG = 25.0;
  static const caffeinePregnancyMg = 200.0;

  /// Limits per day, by the server's keys: energy_kcal, sodium_mg, sugar_g and, when they apply,
  /// sat_fat_g, protein_g (maximum), caffeine_mg.
  final Map<String, double> limits;

  /// Amounts to reach per day: protein_g_min, calcium_mg_min, fibre_g_min.
  final Map<String, double> needs;

  /// An arm limitation: only foods that can be eaten with one hand.
  final bool oneHandOnly;
  final bool pregnant;

  /// Kidney disease: potassium and phosphorus are watched.
  final bool watchPotassium;

  /// Where each number comes from, for the plan screen.
  final Map<String, String> basis;

  const DietTargets({
    required this.limits,
    this.needs = const {},
    this.oneHandOnly = false,
    this.pregnant = false,
    this.watchPotassium = false,
    this.basis = const {},
  });

  static double activityLevel(Iterable<String> limitations) {
    final l = limitations.toSet();
    if (l.any(legBalance.contains)) return 1.4;
    if (l.any(arm.contains)) return 1.45;
    return 1.5;
  }

  /// Daily calorie target, or null when a measurement is missing.
  static int? energyTarget({
    required int? age,
    required bool? male,
    required double? weightKg,
    required double? heightCm,
    Iterable<String> limitations = const [],
    Iterable<String> conditions = const [],
  }) {
    if (age == null || male == null || weightKg == null || heightCm == null || heightCm <= 0) {
      return null;
    }
    final bmr = 10 * weightKg + 6.25 * heightCm - 5 * age + (male ? 5 : -161);
    var kcal = bmr * activityLevel(limitations);
    final pregnant = conditions.contains('PREGNANCY');
    if (pregnant) kcal += 285;
    final bmi = weightKg / math.pow(heightCm / 100, 2);
    if (bmi >= 27.5 && !pregnant) kcal = math.max(kcal - 500, male ? 1500.0 : 1200.0);
    return (kcal + 0.5).floor(); // half up, as the server
  }

  factory DietTargets.of({
    required double energyKcal,
    Iterable<String> conditions = const [],
    Iterable<String> limitations = const [],
    double? weightKg,
    int? age,
    double? sodiumLimitMg,
    double? sugarLimitG,
  }) {
    final c = conditions.toSet();
    double r1(double x) => (x * 10).roundToDouble() / 10;
    final limits = <String, double>{
      'energy_kcal': energyKcal,
      'sodium_mg': math.min(sodiumLimitMg ?? whoSodiumMg, whoSodiumMg),
      'sugar_g': math.min(sugarLimitG ?? whoSugarG, whoSugarG),
    };
    final basis = <String, String>{
      'energy_kcal': 'calorie target of your safety limit',
      'sodium_mg': 'your safety limit, at most 2000 mg (WHO)',
      'sugar_g': 'at most 25 g free sugars (WHO)',
    };
    final needs = <String, double>{};
    final satFat = c.where(satFatConditions.contains).toList()..sort();
    if (satFat.isNotEmpty) {
      limits['sat_fat_g'] = r1(0.10 * energyKcal / 9);
      basis['sat_fat_g'] = 'under 10% of energy (WHO) because of ${satFat.map(_words).join(', ')}';
    }
    final kidney = c.contains('KIDNEY_DISEASE');
    if (kidney && weightKg != null) {
      limits['protein_g'] = r1(0.8 * weightKg);
      basis['protein_g'] = 'at most 0.8 g per kg for kidney disease (KDIGO)';
    }
    if (c.contains('PREGNANCY')) {
      limits['caffeine_mg'] = caffeinePregnancyMg;
      basis['caffeine_mg'] = 'at most 200 mg caffeine in pregnancy';
    }
    final perKg = [
      for (final x in c) ?proteinNeed[x],
      if ((age ?? 0) >= 65) 1.0,
    ].fold<double>(0, math.max);
    if (perKg > 0 && weightKg != null && !kidney) {
      needs['protein_g_min'] = r1(perKg * weightKg);
      basis['protein_g_min'] = 'at least $perKg g per kg (ESPEN)';
    }
    if (c.contains('OSTEOPOROSIS')) {
      needs['calcium_mg_min'] = 1000;
      basis['calcium_mg_min'] = 'at least 1000 mg for osteoporosis (MOH)';
    }
    if (c.any(fibreNeed.contains)) {
      needs['fibre_g_min'] = 25;
      basis['fibre_g_min'] = 'at least 25 g fibre (WHO)';
    }
    return DietTargets(
      limits: limits,
      needs: needs,
      oneHandOnly: limitations.any(arm.contains),
      pregnant: c.contains('PREGNANCY'),
      watchPotassium: kidney,
      basis: basis,
    );
  }

  static String _words(String code) => switch (code) {
    'HEART_DISEASE' => 'heart disease',
    'STROKE' => 'a past stroke',
    'HYPERTENSION' => 'high blood pressure',
    'DIABETES' => 'diabetes',
    _ => code.toLowerCase(),
  };
}
