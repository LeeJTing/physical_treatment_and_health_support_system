import 'package:flutter/material.dart';

import 'package:physical_treatment_and_health_support_system/core/themes/design_tokens.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/diet_plan.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/enums.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/food_item.dart';
import 'package:physical_treatment_and_health_support_system/view/common/tidy_text.dart';
import 'package:physical_treatment_and_health_support_system/view/diet_view/widgets/diet_widgets.dart';
import 'package:physical_treatment_and_health_support_system/view/diet_view/widgets/food_picture.dart';
import 'package:physical_treatment_and_health_support_system/view/diet_view/widgets/plan_widgets.dart';

/// Shared by the draft builder and the saved daily/weekly plan.
class PlanTotalsCard extends StatelessWidget {
  final String title;
  final Nutrients totals;
  final double energyLimit, sodiumLimit, sugarLimit;
  final List<Widget> children;
  const PlanTotalsCard({
    super.key,
    required this.title,
    required this.totals,
    required this.energyLimit,
    required this.sodiumLimit,
    required this.sugarLimit,
    this.children = const [],
  });

  @override
  Widget build(BuildContext context) => Material(
    color: AppTokens.surface,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(20),
      side: const BorderSide(color: AppTokens.cardBorder),
    ),
    clipBehavior: Clip.antiAlias,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              OneLineText(
                title,
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: AppTokens.ink),
              ),
              PlanBar(label: 'Energy', value: totals.energyKcal, limit: energyLimit, unit: 'kcal', isTarget: true),
              PlanBar(label: 'Sodium', value: totals.sodiumMg, limit: sodiumLimit, unit: 'mg'),
              PlanBar(label: 'Free sugars', value: totals.sugarG, limit: sugarLimit, unit: 'g', decimals: 1),
            ],
          ),
        ),
        ...children,
      ],
    ),
  );
}

class PlanMealCard extends StatelessWidget {
  final MealSlot slot;
  final List<PlannedMeal> meals;
  final double usualKcal;
  final List<Widget> rows;
  final VoidCallback? onAdd;
  const PlanMealCard({
    super.key,
    required this.slot,
    required this.meals,
    required this.usualKcal,
    required this.rows,
    this.onAdd,
  });

  @override
  Widget build(BuildContext context) {
    final look = SlotLook.of(slot);
    final kcal = meals.fold(0.0, (sum, m) => sum + m.energyKcal);
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: AppTokens.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppTokens.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: [look.back, AppTokens.surface]),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
            ),
            child: Row(
              children: [
                SlotPicture(slot),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      OneLineText(
                        slot.label,
                        style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w700, color: AppTokens.ink),
                      ),
                      OneLineText(
                        '${look.time} · ${fmtNum(kcal)} kcal of about ${fmtNum(usualKcal)}',
                        style: const TextStyle(fontSize: 14, color: AppTokens.inkMuted),
                      ),
                      const SizedBox(height: 6),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: usualKcal <= 0 ? 0 : (kcal / usualKcal).clamp(0.0, 1.0),
                          minHeight: 6,
                          color: kcal > usualKcal * 1.3 ? AppTokens.caution : look.fore,
                          backgroundColor: AppTokens.surface,
                        ),
                      ),
                    ],
                  ),
                ),
                if (meals.any((m) => m.isLogged))
                  const Padding(
                    padding: EdgeInsets.only(left: 8),
                    child: Column(
                      children: [
                        Icon(Icons.check_circle, color: AppTokens.good, size: 22),
                        Text(
                          'Logged',
                          style: TextStyle(color: AppTokens.good, fontWeight: FontWeight.w600, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          if (meals.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Text(
                tidy('Nothing planned for your ${slot.label.toLowerCase()} yet.'),
                style: const TextStyle(fontSize: 15, color: AppTokens.inkMuted),
              ),
            ),
          ...rows,
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 2, 8, 6),
            child: Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                style: TextButton.styleFrom(minimumSize: const Size(0, AppTokens.minTarget)),
                onPressed: onAdd,
                icon: const Icon(Icons.add_circle_outline),
                label: OneLineText('Add food to ${slot.label.toLowerCase()}'),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class PlanFoodRow extends StatelessWidget {
  final PlannedMeal meal;
  final List<String> warnings;
  final VoidCallback? onTap, onRemove;
  final Widget? actions;
  const PlanFoodRow({super.key, required this.meal, this.warnings = const [], this.onTap, this.onRemove, this.actions});

  @override
  Widget build(BuildContext context) => Semantics(
    container: true,
    identifier: 'plan-food-${meal.food.foodKey}-${meal.plannedMealId}',
    child: Container(
      margin: const EdgeInsets.fromLTRB(8, 6, 8, 2),
      decoration: BoxDecoration(
        color: warnings.isEmpty ? AppTokens.surface : AppTokens.dangerContainer,
        borderRadius: BorderRadius.circular(14),
        border: warnings.isEmpty ? null : Border.all(color: AppTokens.danger),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 10, 0, 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  FoodRoleAvatar(meal.food.planRole, size: 46),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                tidy(meal.food.foodName),
                                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: AppTokens.ink),
                              ),
                            ),
                            if (meal.isLocked)
                              const Padding(
                                padding: EdgeInsets.only(left: 6),
                                child: Icon(Icons.lock, size: 16, color: AppTokens.brandDeep, semanticLabel: 'Locked'),
                              ),
                          ],
                        ),
                        OneLineText(
                          '${FoodLook.of(meal.food.planRole).label} · ${meal.portionSizeG.round()} g · ${fmtNum(meal.energyKcal)} kcal',
                          style: const TextStyle(fontSize: 13, color: AppTokens.inkMuted),
                        ),
                        OneLineText(
                          '${fmtNum(meal.sodiumMg)} mg sodium · ${meal.sugarG.toStringAsFixed(1)} g sugars',
                          style: const TextStyle(fontSize: 13, color: AppTokens.inkMuted),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Remove ${meal.food.foodName}',
                    onPressed: onRemove,
                    icon: const Icon(Icons.close, color: AppTokens.inkMuted),
                  ),
                ],
              ),
              if (warnings.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 8, 10, 4),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.warning_amber_rounded, size: 18, color: AppTokens.danger),
                          SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              'Review this choice',
                              style: TextStyle(color: AppTokens.onDanger, fontWeight: FontWeight.w700),
                            ),
                          ),
                        ],
                      ),
                      for (final warning in warnings)
                        Text(tidy(warning), style: const TextStyle(fontSize: 14, color: AppTokens.onDanger)),
                    ],
                  ),
                ),
              ?actions,
            ],
          ),
        ),
      ),
    ),
  );
}
