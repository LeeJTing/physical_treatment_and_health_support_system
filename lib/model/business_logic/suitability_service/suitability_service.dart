import 'package:physical_treatment_and_health_support_system/core/constants/app_constants.dart';
import 'package:physical_treatment_and_health_support_system/core/utils/id_utils.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/diet_targets.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/enums.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/food_item.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/health_profile.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/lookups.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/meal_log.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/safety_limit.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/suitability_verdict.dart';

/// What the diet rules need to know about the patient, from UC1000 (UC900 C1): declared
/// conditions, foods they cannot eat and physical limitations, the body measurements for the
/// targets, the safety limit, and whether the profile could be read at all.
class DietContext {
  final List<HealthCondition> conditions;
  final List<DietaryRestriction> restrictions;
  final List<PhysicalLimitation> limitations;
  final SafetyLimit limit;
  final RiskLevel riskLevel;
  final int? age;
  final Gender? gender;
  final double? weightKg;
  final double? heightCm;

  /// The profile could not be read: the most restrictive limits apply (FR700_022, UC900 E1).
  final bool failSafe;

  const DietContext({
    this.conditions = const [],
    this.restrictions = const [],
    this.limitations = const [],
    required this.limit,
    this.riskLevel = RiskLevel.high,
    this.failSafe = false,
    this.age,
    this.gender,
    this.weightKg,
    this.heightCm,
  });

  factory DietContext.from(ProfileSnapshot s) {
    final p = s.profile;
    final failSafe =
        s.status == ProfileStatus.error || s.status == ProfileStatus.unauthenticated;
    return DietContext(
      conditions: p?.conditions ?? const [],
      restrictions: p?.restrictions ?? const [],
      limitations: p?.limitations ?? const [],
      limit: failSafe ? SafetyLimit.mostRestrictive() : s.safetyLimit,
      riskLevel: s.riskLevel,
      failSafe: failSafe,
      age: p?.age,
      gender: p?.gender,
      weightKg: p?.weightKg,
      heightCm: p?.heightCm,
    );
  }

  List<String> get conditionCodes => conditions.map((c) => c.conditionCode).toList();
  List<String> get restrictionCodes =>
      restrictions.map((r) => r.restrictionCode).toList();
  List<String> get limitationCodes => limitations.map((l) => l.limitationCode).toList();

  bool hasCondition(String code) => conditions.any((c) => c.conditionCode == code);
  bool get oneHandOnly => limitationCodes.any(DietTargets.arm.contains);

  /// Daily limits for plans and the remaining allowance (UC900 C10): the safety limit, never above
  /// the WHO 2000 mg sodium / 25 g free sugars.
  double get dailySodiumMg => limit.dailySodiumLimitMg
      .toDouble()
      .clamp(0, AppConstants.whoSodiumMg)
      .toDouble();
  double get dailySugarG =>
      limit.dailySugarLimitG.clamp(0, AppConstants.whoSugarG).toDouble();
  double get dailyEnergyKcal => limit.dailyCalorieTarget.toDouble();

  /// The day's limits and needs for this patient (saturated fat, protein, caffeine, calcium, fibre).
  DietTargets get targets => DietTargets.of(
    energyKcal: dailyEnergyKcal,
    conditions: failSafe ? const ['HYPERTENSION', 'DIABETES'] : conditionCodes,
    limitations: limitationCodes,
    weightKg: weightKg,
    age: age,
    sodiumLimitMg: dailySodiumMg,
    sugarLimitG: dailySugarG,
  );

  /// What the planner needs of the profile: no name or identifier (FR700_046).
  Map<String, dynamic> get profileForPlanner => {
    'age': age,
    'gender': gender?.db,
    'weight_kg': weightKg,
    'height_cm': heightCm,
  };

  Nutrients remaining(Nutrients consumed) => Nutrients(
    energyKcal: dailyEnergyKcal - consumed.energyKcal,
    sodiumMg: dailySodiumMg - consumed.sodiumMg,
    sugarG: dailySugarG - consumed.sugarG,
  );
}

/// Decides whether a food is suitable (Table 4.101; UC900 C2, C3, C6, C8; FR700_018 to FR700_028).
/// Deterministic rules, not a learned model, so a verdict is reproducible and explainable
/// (DC700_06). The AI server runs the same rules (ai_server/app/food/suitability.py).
///
/// * Foods the patient cannot eat: a food whose recipe contains a declared food name (Onion, Pork,
///   Prawn, ...) is always Not Suitable.
/// * Daily limits (WHO 2012, 2015): 2000 mg sodium, 25 g free sugars.
/// * One item against 30 % of the daily limit for the nutrient a declared condition is sensitive to:
///   600 mg sodium for Hypertension, 7.5 g free sugars for Diabetes Mellitus (C2). Heart disease,
///   stroke and chronic kidney disease count as sodium-sensitive too.
/// * Heart disease, stroke: saturated fat against 30 % of 20 g a day (WHO 2023).
/// * Chronic kidney disease: potassium against 600 mg and phosphorus against 240 mg per item, at
///   most Caution (how strict depends on the blood tests).
/// * Pregnancy: raw fish, undercooked egg and food cooked with alcohol are Not Suitable; more than
///   100 mg caffeine in one item is Caution.
/// * Arm limitation: a food that needs two hands to eat is Caution, and plans leave it out.
/// * A nutrient no declared condition is sensitive to: against the whole daily limit (C6).
/// * Suitable up to 80 % of the limit, Caution 80-100 %, Not Suitable above (C8). The most
///   restrictive is shown.
/// * Profile unavailable: Hypertension and Diabetes limits both apply (fail-safe, FR700_022).
class SuitabilityService {
  static const sodiumConditions = {
    'HYPERTENSION': 'high blood pressure',
    'HEART_DISEASE': 'heart disease',
    'STROKE': 'a past stroke',
    'KIDNEY_DISEASE': 'chronic kidney disease',
  };
  static const sugarConditions = {'DIABETES': 'diabetes'};
  static const satFatConditions = {'HEART_DISEASE': 'heart disease', 'STROKE': 'a past stroke'};
  static const kidneyConditions = {'KIDNEY_DISEASE': 'chronic kidney disease'};
  static const pregnancyConditions = {'PREGNANCY': 'pregnancy'};
  static const dailySatFatG = 20.0;
  static const dailyPotassiumMg = 2000.0;
  static const dailyPhosphorusMg = 800.0;
  static const caffeineItemMg = 100.0;
  static const _labels = {
    'sodium_mg': 'sodium',
    'sugar_g': 'free sugars',
    'sat_fat_g': 'saturated fat',
    'potassium_mg': 'potassium',
    'phosphorus_mg': 'phosphorus',
    'caffeine_mg': 'caffeine',
  };

  const SuitabilityService();

  /// One verdict per applicable condition, food name and limitation (FR700_024).
  List<SuitabilityVerdict> assess(MealItem i, DietContext ctx) => [
    ...checkRestrictions(i.food, ctx),
    ...checkPregnancy(i.food, ctx),
    ...checkLimitations(i.food, ctx),
    ...checkNutrients(i.food, i.portionSizeG, ctx),
  ];

  static String _foodName(String code) =>
      LookupSeed.restrictions.where((r) => r.restrictionCode == code).firstOrNull?.restrictionName ??
      code.replaceAll('_', ' ');

  /// Not Suitable when the food contains a declared food name.
  List<SuitabilityVerdict> checkRestrictions(FoodItem f, DietContext ctx) => [
    for (final r in ctx.restrictions)
      if (f.containsOf([r.restrictionCode]) case final hit when hit.isNotEmpty)
        SuitabilityVerdict(
          verdictId: newId(),
          verdict: Verdict.notSuitable,
          reasonText:
              'This item contains ${hit.map(_foodName).map((n) => n.toLowerCase()).join(', ')}, '
              'which you said you cannot eat.',
          restrictionId: r.restrictionId,
          restrictionCode: r.restrictionCode,
        ),
  ];

  /// Raw fish, undercooked egg and alcohol are Not Suitable in pregnancy.
  List<SuitabilityVerdict> checkPregnancy(FoodItem f, DietContext ctx) {
    final preg = ctx.conditions.where((c) => c.conditionCode == 'PREGNANCY').firstOrNull;
    if (preg == null) return const [];
    return [
      if (f.pregnancyCaution case final why?)
        SuitabilityVerdict(
          verdictId: newId(),
          verdict: Verdict.notSuitable,
          reasonText: 'Not advised in pregnancy: $why.',
          conditionId: preg.conditionId,
          conditionCode: preg.conditionCode,
        ),
      if (f.restrictionCodes.contains('ALCOHOL'))
        SuitabilityVerdict(
          verdictId: newId(),
          verdict: Verdict.notSuitable,
          reasonText: 'Not advised in pregnancy: it is cooked with alcohol (rice wine).',
          conditionId: preg.conditionId,
          conditionCode: preg.conditionCode,
        ),
    ];
  }

  /// Caution for a food that needs two hands when the patient has an arm limitation.
  List<SuitabilityVerdict> checkLimitations(FoodItem f, DietContext ctx) => [
    if (f.needsTwoHands && ctx.oneHandOnly)
      SuitabilityVerdict(
        verdictId: newId(),
        verdict: Verdict.caution,
        reasonText:
            'This item needs two hands to eat (${f.twoHandsReason ?? 'bones or shells'}). With your arm '
            'limitation, ask for it without bones or shells, or choose another dish.',
      ),
  ];

  /// Caution or Not Suitable when a limit is exceeded (FR700_018, FR700_019); a Suitable verdict
  /// is kept for a declared condition so the reason can say the item is within it.
  List<SuitabilityVerdict> checkNutrients(FoodItem f, double grams, DietContext ctx) {
    final n = f.nutrientsFor(grams);
    final x = f.extrasFor(grams);
    final out = <SuitabilityVerdict>[];
    for (final (nutrient, value) in [
      ('sodium_mg', n.sodiumMg),
      ('sugar_g', n.sugarG),
      ('sat_fat_g', x.satFatG),
      ('potassium_mg', x.potassiumMg),
      ('phosphorus_mg', x.phosphorusMg),
      ('caffeine_mg', x.caffeineMg),
    ]) {
      final rule = itemRule(nutrient, ctx);
      if (rule == null) continue;
      final (limit, cond, words, cautionOnly) = rule;
      var v = band(value, limit);
      if (cautionOnly && v == Verdict.notSuitable) v = Verdict.caution;
      final label = _labels[nutrient]!;
      String fmt(double x) => nutrient.endsWith('_mg') ? '${x.round()} mg' : '${x.toStringAsFixed(1)} g';
      final String text;
      if (cond == null) {
        if (v == Verdict.suitable) continue;
        text =
            'This item is high in $label: ${fmt(value)}, ${(value / limit * 100).round()}% of '
            '${ctx.failSafe ? 'the conservative limit of' : 'the daily limit of'} ${fmt(limit)}.';
      } else if (v == Verdict.suitable) {
        if (nutrient != 'sodium_mg' && nutrient != 'sugar_g') continue;
        text =
            '${fmt(value)} $label, within your limit of ${fmt(limit)} for one item because you '
            'have declared $words.';
      } else if (cautionOnly) {
        text =
            'This item is high in $label (${fmt(value)}). With $words, check with your doctor how much '
            '$label you may have; ${fmt(limit)} is a cautious amount for one item.';
      } else if (v == Verdict.caution) {
        text =
            'This item is high in $label. You have declared $words, so it is to be eaten with '
            'caution. It uses ${(value / limit * 100).round()}% of your limit of ${fmt(limit)} for one item.';
      } else {
        text = Messages.itemFlagged(label, words!, 'not suitable', fmt(value - limit));
      }
      out.add(
        SuitabilityVerdict(
          verdictId: newId(),
          verdict: v,
          reasonText: text,
          conditionId: cond?.conditionId,
          conditionCode: cond?.conditionCode,
          nutrient: nutrient,
          limit: limit,
          value: value,
        ),
      );
    }
    return out;
  }

  /// (limit for one item, the condition that sets it or null, its words, at most Caution) for a
  /// nutrient, or null when no rule applies to it.
  (double, HealthCondition?, String?, bool)? itemRule(String nutrient, DietContext ctx) {
    HealthCondition? find(Map<String, String> m) =>
        ctx.conditions.where((c) => m.containsKey(c.conditionCode)).firstOrNull;
    switch (nutrient) {
      case 'sodium_mg' || 'sugar_g':
        final (l, c, w) = itemLimit(nutrient, ctx);
        return (l, c, w, false);
      case 'sat_fat_g':
        final c = find(satFatConditions);
        return c == null ? null : (dailySatFatG * AppConstants.itemShare, c, satFatConditions[c.conditionCode], false);
      case 'potassium_mg' || 'phosphorus_mg':
        final c = find(kidneyConditions);
        if (c == null) return null;
        final daily = nutrient == 'potassium_mg' ? dailyPotassiumMg : dailyPhosphorusMg;
        return (daily * AppConstants.itemShare, c, kidneyConditions[c.conditionCode], true);
      case 'caffeine_mg':
        final c = find(pregnancyConditions);
        return c == null ? null : (caffeineItemMg, c, 'pregnancy', true);
    }
    return null;
  }

  /// (limit for one item, the condition that sets it or null, its words) for a nutrient.
  (double, HealthCondition?, String?) itemLimit(String nutrient, DietContext ctx) {
    final map = nutrient == 'sodium_mg' ? sodiumConditions : sugarConditions;
    final daily = nutrient == 'sodium_mg' ? AppConstants.whoSodiumMg : AppConstants.whoSugarG;
    final cond = ctx.conditions.where((c) => map.containsKey(c.conditionCode)).firstOrNull;
    if (cond != null) return (daily * AppConstants.itemShare, cond, map[cond.conditionCode]);
    if (ctx.failSafe) {
      return (daily * AppConstants.itemShare, null, null);
    }
    return (daily, null, null);
  }

  static Verdict band(double value, double limit) {
    if (limit <= 0) return Verdict.notSuitable;
    final r = value / limit;
    if (r > 1.0) return Verdict.notSuitable;
    if (r >= AppConstants.cautionFrom) return Verdict.caution;
    return Verdict.suitable;
  }

  /// The verdict displayed when several apply (FR700_028).
  Verdict mostRestrictive(List<SuitabilityVerdict> vs) => vs.fold(
    Verdict.suitable,
    (w, v) => v.verdict.index > w.index ? v.verdict : w,
  );

  /// Keeps unsuitable foods out of generated plans (FR700_033), and foods that need two hands
  /// out of the plans of a patient with an arm limitation.
  bool isExcludedFromPlans(FoodItem f, DietContext ctx, [double? grams]) =>
      (f.needsTwoHands && ctx.oneHandOnly) ||
      mostRestrictive([
        ...checkRestrictions(f, ctx),
        ...checkPregnancy(f, ctx),
        ...checkNutrients(f, grams ?? f.baseServingG, ctx),
      ]) ==
      Verdict.notSuitable;

  /// Alternatives for a flagged item (UC900 C3; FR700_020, FR700_027): same food group, below every
  /// limit the item exceeded and breaking no restriction, ordered by the smallest difference in
  /// energy and in the flagged nutrient.
  List<FoodItem> rankAlternatives(MealItem item, List<FoodItem> sameGroup, DietContext ctx) {
    final flagged = assess(item, ctx).where((v) => v.verdict != Verdict.suitable);
    final nutrients = flagged.map((v) => v.nutrient).whereType<String>().toSet();
    final me = item.nutrients;
    final scored = <(double, FoodItem)>[];
    for (final g in sameGroup) {
      if (g.foodId == item.food.foodId) continue;
      final vs = [
        ...checkRestrictions(g, ctx),
        ...checkPregnancy(g, ctx),
        ...checkLimitations(g, ctx),
        ...checkNutrients(g, g.baseServingG, ctx),
      ];
      if (mostRestrictive(vs) != Verdict.suitable) continue;
      final n = g.nutrientsFor(g.baseServingG);
      final gx = g.extrasFor(g.baseServingG), mx = item.food.extrasFor(item.portionSizeG);
      var d = (n.energyKcal - me.energyKcal).abs() / 100;
      if (nutrients.contains('sodium_mg')) d += (n.sodiumMg - me.sodiumMg).abs() / 100;
      if (nutrients.contains('sugar_g')) d += (n.sugarG - me.sugarG).abs() / 2;
      for (final k in nutrients.where((k) => k != 'sodium_mg' && k != 'sugar_g')) {
        d += (gx[k] - mx[k]).abs() / (k.endsWith('_mg') ? 100 : 2);
      }
      scored.add((d, g));
    }
    scored.sort((a, b) => a.$1.compareTo(b.$1));
    return scored.map((s) => s.$2).toList();
  }
}
