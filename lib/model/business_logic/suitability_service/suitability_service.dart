import 'package:physical_treatment_and_health_support_system/core/constants/app_constants.dart';
import 'package:physical_treatment_and_health_support_system/core/utils/id_utils.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/enums.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/food_item.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/health_profile.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/lookups.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/meal_log.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/safety_limit.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/suitability_verdict.dart';

/// What the diet rules need to know about the patient, from UC1000 (UC900 C1): declared
/// conditions and restrictions, the safety limit, and whether the profile could be read at all.
class DietContext {
  final List<HealthCondition> conditions;
  final List<DietaryRestriction> restrictions;
  final SafetyLimit limit;
  final RiskLevel riskLevel;

  /// The profile could not be read: the most restrictive limits apply (FR700_022, UC900 E1).
  final bool failSafe;

  const DietContext({
    this.conditions = const [],
    this.restrictions = const [],
    required this.limit,
    this.riskLevel = RiskLevel.high,
    this.failSafe = false,
  });

  factory DietContext.from(ProfileSnapshot s) {
    final p = s.profile;
    final failSafe =
        s.status == ProfileStatus.error || s.status == ProfileStatus.unauthenticated;
    return DietContext(
      conditions: p?.conditions ?? const [],
      restrictions: p?.restrictions ?? const [],
      limit: failSafe ? SafetyLimit.mostRestrictive() : s.safetyLimit,
      riskLevel: s.riskLevel,
      failSafe: failSafe,
    );
  }

  List<String> get conditionCodes => conditions.map((c) => c.conditionCode).toList();
  List<String> get restrictionCodes =>
      restrictions.map((r) => r.restrictionCode).toList();

  /// Daily limits for plans and the remaining allowance (UC900 C10): the safety limit, never above
  /// the WHO 2000 mg sodium / 25 g free sugars.
  double get dailySodiumMg => limit.dailySodiumLimitMg
      .toDouble()
      .clamp(0, AppConstants.whoSodiumMg)
      .toDouble();
  double get dailySugarG =>
      limit.dailySugarLimitG.clamp(0, AppConstants.whoSugarG).toDouble();
  double get dailyEnergyKcal => limit.dailyCalorieTarget.toDouble();

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
/// * Daily limits (WHO 2012, 2015): 2000 mg sodium, 25 g free sugars.
/// * One item against 30 % of the daily limit for the nutrient a declared condition is sensitive to:
///   600 mg sodium for Hypertension, 7.5 g free sugars for Diabetes Mellitus (C2). Heart disease,
///   stroke and chronic kidney disease count as sodium-sensitive too.
/// * A nutrient no declared condition is sensitive to: against the whole daily limit (C6).
/// * Suitable up to 80 % of the limit, Caution 80-100 %, Not Suitable above (C8). A declared
///   dietary restriction the food breaches: always Not Suitable. The most restrictive is shown.
/// * Profile unavailable: Hypertension and Diabetes limits both apply (fail-safe, FR700_022).
class SuitabilityService {
  static const sodiumConditions = {
    'HYPERTENSION': 'high blood pressure',
    'HEART_DISEASE': 'heart disease',
    'STROKE': 'a past stroke',
    'KIDNEY_DISEASE': 'chronic kidney disease',
  };
  static const sugarConditions = {'DIABETES': 'diabetes'};
  static const restrictionWords = {
    'PEANUT': 'peanuts',
    'SHELLFISH': 'shellfish',
    'FISH': 'fish',
    'EGG': 'egg',
    'MILK': 'milk or dairy',
    'GLUTEN': 'gluten (wheat)',
    'BEEF': 'beef',
    'VEGAN': 'animal products',
    'VEGETARIAN': 'meat or fish',
    'HALAL': 'non-halal ingredients',
  };

  const SuitabilityService();

  /// One verdict per applicable condition and restriction (FR700_024).
  List<SuitabilityVerdict> assess(MealItem i, DietContext ctx) => [
    ...checkRestrictions(i.food, ctx),
    ...checkNutrients(i.food, i.portionSizeG, ctx),
  ];

  /// Not Suitable when a food tag matches a declared restriction.
  List<SuitabilityVerdict> checkRestrictions(FoodItem f, DietContext ctx) => [
    for (final r in ctx.restrictions)
      if (f.restrictionCodes.contains(r.restrictionCode))
        SuitabilityVerdict(
          verdictId: newId(),
          verdict: Verdict.notSuitable,
          reasonText:
              'This item contains ${restrictionWords[r.restrictionCode] ?? r.restrictionName.toLowerCase()}, '
              'which your profile says you avoid (${r.restrictionName}).',
          restrictionId: r.restrictionId,
          restrictionCode: r.restrictionCode,
        ),
  ];

  /// Caution or Not Suitable when a limit is exceeded (FR700_018, FR700_019); a Suitable verdict
  /// is kept for a declared condition so the reason can say the item is within it.
  List<SuitabilityVerdict> checkNutrients(FoodItem f, double grams, DietContext ctx) {
    final n = f.nutrientsFor(grams);
    final out = <SuitabilityVerdict>[];
    for (final nutrient in const ['sodium_mg', 'sugar_g']) {
      final value = nutrient == 'sodium_mg' ? n.sodiumMg : n.sugarG;
      final (limit, cond, words) = itemLimit(nutrient, ctx);
      final v = band(value, limit);
      final label = nutrient == 'sodium_mg' ? 'sodium' : 'free sugars';
      String fmt(double x) =>
          nutrient == 'sodium_mg' ? '${x.round()} mg' : '${x.toStringAsFixed(1)} g';
      final String text;
      if (cond == null) {
        if (v == Verdict.suitable) continue;
        text =
            'This item is high in $label: ${fmt(value)}, ${(value / limit * 100).round()}% of '
            '${ctx.failSafe ? 'the conservative limit of' : 'the daily limit of'} ${fmt(limit)}.';
      } else if (v == Verdict.suitable) {
        text =
            '${fmt(value)} $label, within your limit of ${fmt(limit)} for one item because you '
            'have declared $words.';
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

  /// Keeps unsuitable foods out of generated plans (FR700_033).
  bool isExcludedFromPlans(FoodItem f, DietContext ctx, [double? grams]) =>
      mostRestrictive([
        ...checkRestrictions(f, ctx),
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
      final vs = [...checkRestrictions(g, ctx), ...checkNutrients(g, g.baseServingG, ctx)];
      if (mostRestrictive(vs) != Verdict.suitable) continue;
      final n = g.nutrientsFor(g.baseServingG);
      var d = (n.energyKcal - me.energyKcal).abs() / 100;
      if (nutrients.contains('sodium_mg')) d += (n.sodiumMg - me.sodiumMg).abs() / 100;
      if (nutrients.contains('sugar_g')) d += (n.sugarG - me.sugarG).abs() / 2;
      scored.add((d, g));
    }
    scored.sort((a, b) => a.$1.compareTo(b.$1));
    return scored.map((s) => s.$2).toList();
  }
}
