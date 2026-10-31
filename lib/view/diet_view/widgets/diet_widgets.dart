import 'package:flutter/material.dart';

import 'package:physical_treatment_and_health_support_system/core/constants/app_constants.dart';
import 'package:physical_treatment_and_health_support_system/core/themes/design_tokens.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/enums.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/food_item.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/meal_log.dart';

String fmtNum(num v) =>
    v.round().toString().replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ',');

/// Verdict coded three times, with a glyph, a word and a colour (UI Design, Meal Result).
class VerdictChip extends StatelessWidget {
  final Verdict verdict;
  const VerdictChip(this.verdict, {super.key});

  static (Color, Color, IconData) colours(Verdict v) => switch (v) {
    Verdict.suitable => (AppTokens.goodContainer, AppTokens.good, Icons.check_circle),
    Verdict.caution => (AppTokens.cautionContainer, AppTokens.caution, Icons.error_outline),
    Verdict.notSuitable => (AppTokens.dangerContainer, AppTokens.onDanger, Icons.block),
  };

  @override
  Widget build(BuildContext context) {
    final (bg, fg, icon) = colours(verdict);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: fg),
          const SizedBox(width: 4),
          Text(verdict.label, style: TextStyle(color: fg, fontWeight: FontWeight.w700, fontSize: 14)),
        ],
      ),
    );
  }
}

/// Energy, sodium and free sugars used today against the daily targets, and what is left
/// (FR700_039; shown on Diet and Home so the patient need not move away to decide, UI Design).
class AllowanceCard extends StatelessWidget {
  final Nutrients consumed;
  final double energyTarget;
  final double sodiumLimit;
  final double sugarLimit;
  final String? note;
  const AllowanceCard({
    super.key,
    required this.consumed,
    required this.energyTarget,
    required this.sodiumLimit,
    required this.sugarLimit,
    this.note,
  });

  @override
  Widget build(BuildContext context) {
    Widget bar(double used, double limit) {
      final v = limit <= 0 ? 1.0 : (used / limit).clamp(0.0, 1.0);
      return ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: LinearProgressIndicator(
          value: v,
          minHeight: 10,
          backgroundColor: AppTokens.tint,
          color: used > limit
              ? AppTokens.danger
              : v >= AppConstants.cautionFrom
              ? AppTokens.caution
              : AppTokens.brandDeepAccent,
        ),
      );
    }

    Widget row(String label, double used, double limit, String unit) {
      final left = limit - used;
      return Padding(
        padding: const EdgeInsets.only(top: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: Text(label, style: const TextStyle(fontSize: 16, color: AppTokens.inkMuted))),
                Text(
                  '${fmtNum(used)} / ${fmtNum(limit)} $unit',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: AppTokens.ink),
                ),
              ],
            ),
            const SizedBox(height: 6),
            bar(used, limit),
            const SizedBox(height: 2),
            Text(
              left >= 0 ? '${fmtNum(left)} $unit left today' : '${fmtNum(-left)} $unit over today',
              style: TextStyle(fontSize: 13, color: left >= 0 ? AppTokens.inkMuted : AppTokens.danger),
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppTokens.surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: AppTokens.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Today', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: AppTokens.ink)),
          row('Energy', consumed.energyKcal, energyTarget, 'kcal'),
          row('Sodium', consumed.sodiumMg, sodiumLimit, 'mg'),
          row('Free sugars', consumed.sugarG, sugarLimit, 'g'),
          if (note != null) ...[
            const SizedBox(height: 10),
            Text(note!, style: const TextStyle(fontSize: 13, color: AppTokens.onWarn)),
          ],
        ],
      ),
    );
  }
}

/// The full nutrient breakdown of one portion (UC800 C7, UC900 BF-13).
class NutrientTable extends StatelessWidget {
  final Nutrients n;
  const NutrientTable(this.n, {super.key});

  @override
  Widget build(BuildContext context) {
    Widget cell(String l, String v) => Expanded(
      child: Column(
        children: [
          Text(v, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppTokens.ink)),
          Text(l, style: const TextStyle(fontSize: 12, color: AppTokens.inkMuted)),
        ],
      ),
    );
    return Column(
      children: [
        Row(
          children: [
            cell('kcal', fmtNum(n.energyKcal)),
            cell('carb g', n.carbG.toStringAsFixed(0)),
            cell('protein g', n.proteinG.toStringAsFixed(0)),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            cell('fat g', n.fatG.toStringAsFixed(0)),
            cell('sodium mg', fmtNum(n.sodiumMg)),
            cell('free sugars g', n.sugarG.toStringAsFixed(1)),
          ],
        ),
      ],
    );
  }
}

/// A logged meal: its slot and time, items, totals and the worst verdict with the reasons.
class MealCard extends StatelessWidget {
  final MealLog meal;
  final VoidCallback? onDelete;
  final void Function(MealItem item)? onAlternatives;
  const MealCard({super.key, required this.meal, this.onDelete, this.onAlternatives});

  @override
  Widget build(BuildContext context) {
    final t = meal.consumedAt;
    final verdict = meal.worstVerdict();
    final (bg, _, _) = VerdictChip.colours(verdict);
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: verdict == Verdict.suitable ? AppTokens.surface : bg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppTokens.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '${meal.mealType.label} · ${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}',
                  style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: AppTokens.ink),
                ),
              ),
              VerdictChip(verdict),
              if (onDelete != null)
                IconButton(tooltip: 'Delete', onPressed: onDelete, icon: const Icon(Icons.delete_outline)),
            ],
          ),
          for (final i in meal.items) ...[
            const SizedBox(height: 6),
            Text(
              '${i.food.foodName} · ${i.portionSizeG.round()} g · ${fmtNum(i.energyKcal)} kcal',
              style: const TextStyle(fontSize: 15, color: AppTokens.ink),
            ),
            for (final v in i.verdicts.where((v) => v.verdict != Verdict.suitable))
              Padding(
                padding: const EdgeInsets.only(left: 8, top: 2),
                child: Text('• ${v.reasonText}', style: const TextStyle(fontSize: 14, color: AppTokens.ink)),
              ),
            if (i.worstVerdict() != Verdict.suitable && onAlternatives != null)
              TextButton.icon(
                onPressed: () => onAlternatives!(i),
                icon: const Icon(Icons.swap_horiz),
                label: const Text('See a safer choice'),
              ),
          ],
          const SizedBox(height: 6),
          Text(
            'Total ${fmtNum(meal.totalEnergyKcal)} kcal · ${fmtNum(meal.totalSodiumMg)} mg sodium · '
            '${meal.totalSugarG.toStringAsFixed(1)} g free sugars',
            style: const TextStyle(fontSize: 13, color: AppTokens.inkMuted),
          ),
        ],
      ),
    );
  }
}

/// A food in a list (recommendation, alternative, search result).
class FoodTile extends StatelessWidget {
  final FoodItem food;
  final double? grams;
  final VoidCallback? onTap;
  final Widget? trailing;
  const FoodTile({super.key, required this.food, this.grams, this.onTap, this.trailing});

  @override
  Widget build(BuildContext context) {
    final g = grams ?? food.baseServingG;
    final n = food.nutrientsFor(g);
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 4),
      onTap: onTap,
      title: Text(food.foodName, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: AppTokens.ink)),
      subtitle: Text(
        '${g.round()} g · ${fmtNum(n.energyKcal)} kcal · ${fmtNum(n.sodiumMg)} mg sodium · ${n.sugarG.toStringAsFixed(1)} g sugars',
        style: const TextStyle(fontSize: 13, color: AppTokens.inkMuted),
      ),
      trailing: trailing,
    );
  }
}

class DietDisclaimer extends StatelessWidget {
  const DietDisclaimer({super.key});
  @override
  Widget build(BuildContext context) => const Padding(
    padding: EdgeInsets.symmetric(vertical: 8),
    child: Text(
      Messages.dietDisclaimer,
      style: TextStyle(fontSize: 13, color: AppTokens.inkMuted, fontStyle: FontStyle.italic),
    ),
  );
}
