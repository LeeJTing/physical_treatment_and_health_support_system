import 'package:physical_treatment_and_health_support_system/model/business_logic/suitability_service/suitability_service.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/diet_food_guidance.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/diet_plan.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/enums.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/food_item.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/meal_log.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/plan_comparison.dart';

/// Portion-specific, deterministic guidance. Missing meals never imply fasting.
/// Historical nutrient snapshots explain changes; today's catalogue/profile gates
/// every proposed increase. No third-party upload or automatic plan modification.
class DietFoodGuidanceService {
  const DietFoodGuidanceService();
  static DateTime day(DateTime d) =>
      DateTime(d.toLocal().year, d.toLocal().month, d.toLocal().day);
  static String key(FoodItem f) => f.foodKey.isEmpty ? f.foodId : f.foodKey;

  DietFoodGuidance build({
    required PlanComparisonReport comparison,
    required List<MealLog> meals,
    required Iterable<DietPlan> plans,
    required String accountId,
    required DateTime now,
    DietContext? context,
  }) {
    final valid = {for (final m in meals) m.mealId: m}.values
        .where(
          (m) =>
              m.accountId == accountId &&
              !m.consumedAt.isAfter(now) &&
              m.items.isNotEmpty &&
              m.items.every(
                (i) =>
                    i.portionSizeG.isFinite &&
                    i.portionSizeG > 0 &&
                    i.nutrients.toJson().values.every(
                      (v) => v is num && v.isFinite && v >= 0,
                    ),
              ),
        )
        .toList();
    final foods = <String, FoodItem>{
      for (final p in plans.where((p) => p.accountId == accountId))
        for (final m in p.meals) key(m.food): m.food,
      for (final m in valid)
        for (final i in m.items) key(i.food): i.food,
    };
    final ready =
        context != null &&
        !context.failSafe &&
        context.age != null &&
        context.gender != null &&
        context.weightKg != null &&
        context.weightKg!.isFinite &&
        context.weightKg! > 0 &&
        context.heightCm != null &&
        context.heightCm!.isFinite &&
        context.heightCm! > 0;
    final days = <DailyFoodGuidance>[];
    const suitability = SuitabilityService();
    for (final d in comparison.days.where(
      (d) => !d.future && !d.date.isAfter(day(now)),
    )) {
      final logs = valid.where((m) => day(m.consumedAt) == d.date).toList();
      final complete = [
        MealSlot.breakfast,
        MealSlot.lunch,
        MealSlot.dinner,
      ].every((s) => logs.any((m) => m.mealType == s));
      final actions = <FoodGuidanceAction>[];
      if (ready && logs.isNotEmpty) {
        // Budget independent increases together, including condition-specific
        // protein, saturated fat and caffeine limits; never spend an assumed
        // reduction before the user has actually made it.
        var projected = Nutrients.sum(logs.map((m) => m.totals));
        var extras = logs
            .expand((m) => m.items)
            .fold(
              FoodExtras.zero,
              (a, i) => a + i.food.extrasFor(i.portionSizeG),
            );
        for (final slot in MealSlot.values) {
          final items = <String, (FoodItem, double, Nutrients)>{};
          for (final i
              in logs.where((m) => m.mealType == slot).expand((m) => m.items)) {
            final old = items[key(i.food)];
            items[key(i.food)] = (
              i.food,
              (old?.$2 ?? 0) + i.portionSizeG,
              (old?.$3 ?? Nutrients.zero) + i.nutrients,
            );
          }
          final matched = d.meals
              .where((m) => m.slot == slot && m.comparable)
              .firstOrNull;
          for (final entry in items.entries) {
            final (food, grams, nutrients) = entry.value;
            final verdicts = suitability
                .assess(MealItem.of(food, grams: grams), context)
                .where((v) => v.verdict == Verdict.notSuitable)
                .toList();
            final planned = matched?.foods
                .where((f) => f.key == entry.key)
                .firstOrNull;
            final sodiumHigh =
                d.logged.sodiumMg > context.dailySodiumMg &&
                nutrients.sodiumMg > 0;
            final sugarHigh =
                d.logged.sugarG > context.dailySugarG && nutrients.sugarG > 0;
            if (verdicts.isNotEmpty) {
              actions.add(
                FoodGuidanceAction(
                  foodKey: entry.key,
                  foodName: food.foodName,
                  slot: slot,
                  kind: FoodGuidanceKind.replace,
                  loggedG: grams,
                  suggestedG: 0,
                  summary: verdicts.first.reasonText,
                  reason:
                      '${verdicts.first.reasonText} Replace this food with a suitable option in the meal simulator; do not skip the meal.',
                ),
              );
            } else if (planned != null &&
                planned.plannedG > 0 &&
                grams > planned.plannedG * 1.1 &&
                (sodiumHigh ||
                    sugarHigh ||
                    complete &&
                        d.logged.energyKcal > context.dailyEnergyKcal)) {
              final cut = nutrients.scale((grams - planned.plannedG) / grams);
              actions.add(
                FoodGuidanceAction(
                  foodKey: entry.key,
                  foodName: food.foodName,
                  slot: slot,
                  kind: FoodGuidanceKind.reduce,
                  loggedG: grams,
                  suggestedG: planned.plannedG,
                  summary: _saving(cut),
                  reason:
                      'Return toward the saved ${FoodGuidanceAction.grams(planned.plannedG)} g portion. ${_saving(cut)} ${_limit(d, context)} Review a balanced replacement if you are still hungry.',
                ),
              );
            } else if ((sodiumHigh &&
                        nutrients.sodiumMg >= context.dailySodiumMg * .2 ||
                    sugarHigh &&
                        nutrients.sugarG >= context.dailySugarG * .2) &&
                (planned == null || planned.plannedG == 0)) {
              final cut = nutrients.scale(.25);
              actions.add(
                FoodGuidanceAction(
                  foodKey: entry.key,
                  foodName: food.foodName,
                  slot: slot,
                  kind: FoodGuidanceKind.reduce,
                  loggedG: grams,
                  suggestedG: grams * .75,
                  summary:
                      'A 25% smaller portion: ${_saving(cut, sentence: false)}',
                  reason:
                      'An example 25% smaller portion would mean ${_saving(cut, sentence: false)} ${_limit(d, context)} This alone may not meet the limit; compare a lower-sugar or lower-sodium replacement.',
                ),
              );
            }
          }
        }
        final usedSwaps = <String>{};
        for (final meal in d.meals.where((m) => m.comparable)) {
          for (final f in meal.foods.where(
            (f) => f.plannedG > f.loggedG * 1.1 && f.plannedG - f.loggedG > 1,
          )) {
            // Keep a conditional swap self-contained; later options must not
            // silently depend on the user having made that proposed swap.
            if (usedSwaps.isNotEmpty) {
              continue;
            }
            final food = foods[f.key];
            if (context.targets.watchPotassium ||
                food == null ||
                !suitability.suitsPatient(food, context, f.plannedG)) {
              continue;
            }
            final deltaG = f.plannedG - f.loggedG;
            final delta = food.nutrientsFor(deltaG),
                extra = food.extrasFor(deltaG);
            var next = projected + delta, nextExtras = extras + extra;
            bool withinLimits(Nutrients n, FoodExtras e) {
              final values = <String, double>{
                ...n.toJson().map((k, v) => MapEntry(k, (v as num).toDouble())),
                'sat_fat_g': e.satFatG,
                'caffeine_mg': e.caffeineMg,
              };
              return !context.targets.limits.entries.any(
                (e) =>
                    !(values[e.key]?.isFinite ?? false) ||
                    (values[e.key] ?? double.infinity) > e.value + .01,
              );
            }

            ComparedFood? swap;
            if (!withinLimits(next, nextExtras)) {
              swap = meal.foods
                  .where(
                    (candidate) =>
                        candidate.key != f.key &&
                        candidate.loggedG > 0 &&
                        !usedSwaps.contains(
                          '${meal.slot.db}|${candidate.key}',
                        ) &&
                        actions.any(
                          (a) =>
                              a.foodKey == candidate.key &&
                              a.slot == meal.slot &&
                              a.kind == FoodGuidanceKind.replace,
                        ),
                  )
                  .firstOrNull;
              final swapFood = swap == null ? null : foods[swap.key];
              if (swap == null || swapFood == null) continue;
              next = next - swap.logged;
              nextExtras = nextExtras + swapFood.extrasFor(-swap.loggedG);
              if (!withinLimits(next, nextExtras)) continue;
            }
            // Do not call an arbitrary calorie increase a nutritional benefit.
            final benefit = extra.fibreG >= .5
                ? '${extra.fibreG.toStringAsFixed(1)} g fibre for digestive health'
                : delta.proteinG >= 2
                ? '${delta.proteinG.toStringAsFixed(1)} g protein for maintaining body tissues'
                : extra.calciumMg >= 50
                ? '${extra.calciumMg.round()} mg calcium for bone health'
                : null;
            if (benefit == null) continue;
            actions.add(
              FoodGuidanceAction(
                foodKey: f.key,
                foodName: f.name,
                slot: meal.slot,
                kind: FoodGuidanceKind.restore,
                loggedG: f.loggedG,
                suggestedG: f.plannedG,
                summary:
                    'Provides approximately $benefit.${swap == null ? '' : ' Only as a swap for ${FoodGuidanceAction.grams(swap.loggedG)} g ${swap.name}, not extra food.'}',
                reason:
                    '${swap == null ? 'Review' : 'Only if replacing the ${FoodGuidanceAction.grams(swap.loggedG)} g ${swap.name} in this meal, review'} ${FoodGuidanceAction.grams(deltaG)} g more toward the saved portion; approximately $benefit. ${swap == null ? '' : 'This is a swap, not extra food on top of the logged meal. '}This is a meal-planning option, not a diagnosis of deficiency.${complete ? '' : ' Finish logging the day before adding food.'}',
              ),
            );
            projected = next;
            extras = nextExtras;
            if (swap != null) usedSwaps.add('${meal.slot.db}|${swap.key}');
          }
        }
      }
      final compared = d.meals.where((m) => m.comparable).length;
      days.add(
        DailyFoodGuidance(
          d.date,
          logs.isEmpty
              ? 'No meal logs. Intake is unknown; no food amounts are recommended.'
              : !ready
              ? 'Your profile is unavailable. Reload it before reviewing personalised food amounts.'
              : '${complete ? 'All three main meals logged' : 'Partial day: daily intake may be understated'}; $compared meals comparable with a plan. ${_limit(d, context)}${actions.isEmpty ? ' No supported portion change identified. Keep suitable planned portions and check unlogged snacks.' : ' Review the priority food changes below; they are options for a similar future meal.'}',
          [
            ...actions.where((a) => a.kind != FoodGuidanceKind.restore).take(2),
            ...actions.where((a) => a.kind == FoodGuidanceKind.restore).take(2),
          ],
        ),
      );
    }
    final groups = <String, List<(DateTime, FoodGuidanceAction)>>{};
    for (final d in days) {
      for (final a in d.actions) {
        (groups['${a.foodKey}|${a.slot.db}|${a.kind.name}'] ??= []).add((
          d.date,
          a,
        ));
      }
    }
    final sorted = groups.values.toList()
      ..sort((a, b) => b.length.compareTo(a.length));
    final priorities = [
      for (final g in sorted.take(6))
        WeeklyFoodPriority(
          '${g.first.$2.label}: ${g.first.$2.foodName} (${g.first.$2.slot.label.toLowerCase()})',
          '${g.length} recorded meal${g.length == 1 ? '' : 's'} across ${g.map((e) => e.$1).toSet().length} days. ${g.first.$2.kind == FoodGuidanceKind.restore ? 'Restore' : 'Reduce / replace'} ${FoodGuidanceAction.grams(g.fold(0.0, (v, e) => v + (e.$2.suggestedG - e.$2.loggedG).abs()))} g in total across these occurrences. Example: ${g.first.$2.portion}. ${g.first.$2.summary} Review each day for its own portion.',
          g.map((e) => e.$1).toSet().toList()..sort(),
        ),
    ];
    return DietFoodGuidance(
      'Based on your current profile, saved plan and recorded portions. Complete missing logs first. Nutrient changes are estimates; fibre and calcium use the current catalogue. Weekly totals cover recorded meals, not extra allowances. Check a full meal in the simulator before changing it.',
      days,
      priorities,
    );
  }

  static String _saving(Nutrients n, {bool sentence = true}) =>
      '${sentence ? 'Estimated reduction: ' : ''}${n.energyKcal.round()} kcal, ${n.sodiumMg.round()} mg sodium and ${n.sugarG.toStringAsFixed(1)} g free sugars.';
  static String _limit(ComparisonDay d, DietContext c) {
    final parts = <String>[
      if (d.logged.sodiumMg > c.dailySodiumMg)
        'Recorded sodium ${d.logged.sodiumMg.round()} / ${c.dailySodiumMg.round()} mg limit.',
      if (d.logged.sugarG > c.dailySugarG)
        'Recorded free sugars ${d.logged.sugarG.toStringAsFixed(1)} / ${c.dailySugarG.toStringAsFixed(1)} g limit.',
    ];
    return parts.isEmpty ? '' : '${parts.join(' ')} ';
  }
}
